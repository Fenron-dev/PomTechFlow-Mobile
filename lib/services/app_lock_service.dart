import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

// ── PBKDF2 top-level function (needed for compute() isolate) ─────────────────

/// PBKDF2-HMAC-SHA256, single block (32 bytes output).
/// Input: Map with keys 'p' (password), 's' (salt), 'i' (iterations).
String _runPbkdf2(Map<String, dynamic> args) {
  final pBytes = utf8.encode(args['p'] as String);
  final sBytes = utf8.encode(args['s'] as String);
  final iterations = args['i'] as int;

  final hmac = Hmac(sha256, pBytes);

  // Build first block input: salt || INT(1) in big-endian
  final blockInput = Uint8List(sBytes.length + 4);
  for (var k = 0; k < sBytes.length; k++) {
    blockInput[k] = sBytes[k];
  }
  blockInput[sBytes.length + 3] = 1; // block index = 1

  var u = hmac.convert(blockInput).bytes;
  final dk = List<int>.from(u);

  for (var iter = 1; iter < iterations; iter++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < dk.length; j++) {
      dk[j] ^= u[j];
    }
  }

  return base64Encode(dk);
}

/// Manages the optional PIN-based App-Lock.
///
/// PIN hash + salt + recovery code are stored in the device's secure enclave
/// (iOS Keychain, Android Keystore). No PIN data ever reaches the database.
class AppLockService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );
  static const _keyHash        = 'ptf_lock_hash';
  static const _keySalt        = 'ptf_lock_salt';
  static const _keyRecovery    = 'ptf_lock_recovery';
  static const _keyAttempts    = 'ptf_lock_attempts';
  static const _keyLockedUntil = 'ptf_lock_until';

  /// Prefix written into stored hashes to identify PBKDF2 v1 format.
  /// Legacy hashes (plain SHA-256) have no prefix.
  static const _kPbkdf2Prefix = 'pbkdf2v1:';
  static const _kIterations   = 100000;

  static final _localAuth = LocalAuthentication();

  // ── Setup / Status ─────────────────────────────────────────────────────

  /// Returns true when a PIN has been configured.
  static Future<bool> isSetup() async {
    final hash = await _storage.read(key: _keyHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Sets up a new PIN. Returns the 8-character recovery code (uppercase hex).
  /// Call this only after the user has confirmed their PIN twice.
  static Future<String> setup(String pin) async {
    final salt = _randomHex(16);
    final hash = await _hashPin(pin, salt);
    final recovery = _randomHex(4).toUpperCase(); // e.g. "A3F9B02C"

    await _storage.write(key: _keySalt, value: salt);
    await _storage.write(key: _keyHash, value: hash);
    await _storage.write(key: _keyRecovery, value: recovery);
    return recovery;
  }

  /// Changes the PIN. Returns the new recovery code.
  static Future<String> changePIN(String newPin) => setup(newPin);

  /// Removes the PIN lock entirely.
  static Future<void> disable() async {
    await _storage.delete(key: _keyHash);
    await _storage.delete(key: _keySalt);
    await _storage.delete(key: _keyRecovery);
    await _storage.delete(key: _keyAttempts);
    await _storage.delete(key: _keyLockedUntil);
  }

  // ── Rate Limiting ──────────────────────────────────────────────────────

  /// Lockout durations indexed by attempt threshold:
  /// ≥5 → 30 s, ≥10 → 5 min, ≥15 → 30 min.
  static Duration _lockoutFor(int attempts) {
    if (attempts >= 15) return const Duration(minutes: 30);
    if (attempts >= 10) return const Duration(minutes: 5);
    if (attempts >= 5)  return const Duration(seconds: 30);
    return Duration.zero;
  }

  /// Returns the [DateTime] until which the PIN pad is locked, or null if not locked.
  static Future<DateTime?> getLockoutEnd() async {
    final raw = await _storage.read(key: _keyLockedUntil);
    if (raw == null) return null;
    final until = DateTime.tryParse(raw);
    if (until == null || until.isBefore(DateTime.now())) return null;
    return until;
  }

  /// Records a failed PIN attempt. Returns the new [DateTime] lockout end
  /// (or null if no lockout applies yet).
  static Future<DateTime?> recordFailedAttempt() async {
    final raw = await _storage.read(key: _keyAttempts);
    final attempts = (int.tryParse(raw ?? '') ?? 0) + 1;
    await _storage.write(key: _keyAttempts, value: attempts.toString());

    final duration = _lockoutFor(attempts);
    if (duration == Duration.zero) return null;
    final until = DateTime.now().add(duration);
    await _storage.write(key: _keyLockedUntil, value: until.toIso8601String());
    return until;
  }

  /// Clears the failed-attempt counter and any active lockout.
  static Future<void> resetFailedAttempts() async {
    await _storage.delete(key: _keyAttempts);
    await _storage.delete(key: _keyLockedUntil);
  }

  // ── Verification ──────────────────────────────────────────────────────

  /// Verifies the entered PIN. Returns true on match.
  /// Automatically upgrades legacy SHA-256 hashes to PBKDF2 on success.
  static Future<bool> verifyPIN(String pin) async {
    final salt   = await _storage.read(key: _keySalt);
    final stored = await _storage.read(key: _keyHash);
    if (salt == null || stored == null) return false;

    // ── New PBKDF2 hash ──────────────────────────────────────────────────────
    if (stored.startsWith(_kPbkdf2Prefix)) {
      final expected = await compute(_runPbkdf2,
          {'p': pin, 's': salt, 'i': _kIterations});
      final ok = '$_kPbkdf2Prefix$expected' == stored;
      if (ok) await resetFailedAttempts();
      return ok;
    }

    // ── Legacy SHA-256 hash (upgrade silently on success) ────────────────────
    final legacyMatch = _legacySha256(pin, salt) == stored;
    if (legacyMatch) {
      final newHash = await _hashPin(pin, salt);
      await _storage.write(key: _keyHash, value: newHash);
      await resetFailedAttempts();
    }
    return legacyMatch;
  }

  /// Verifies the recovery code (case-insensitive).
  static Future<bool> verifyRecoveryCode(String code) async {
    final stored = await _storage.read(key: _keyRecovery);
    if (stored == null) return false;
    return stored.toUpperCase() == code.trim().toUpperCase();
  }

  // ── Biometrics ────────────────────────────────────────────────────────

  /// Returns true when the device can use biometrics or device credentials.
  static Future<bool> canUseBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Triggers the biometric / device-credentials prompt.
  static Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'PomTechFlow entsperren',
        options: const AuthenticationOptions(
          biometricOnly: false, // also allow PIN/pattern as OS fallback
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// New: PBKDF2-HMAC-SHA256, runs in background isolate via compute().
  static Future<String> _hashPin(String pin, String salt) async {
    final raw = await compute(_runPbkdf2, {'p': pin, 's': salt, 'i': _kIterations});
    return '$_kPbkdf2Prefix$raw';
  }

  /// Legacy SHA-256 (kept only for migration of existing stored hashes).
  static String _legacySha256(String pin, String salt) {
    final bytes = utf8.encode('$pin:$salt:pomtechflow');
    return sha256.convert(bytes).toString();
  }

  static String _randomHex(int byteCount) {
    final rng = Random.secure();
    return List.generate(byteCount, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
