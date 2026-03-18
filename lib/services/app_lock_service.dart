import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Manages the optional PIN-based App-Lock.
///
/// PIN hash + salt + recovery code are stored in the device's secure enclave
/// (iOS Keychain, Android Keystore). No PIN data ever reaches the database.
class AppLockService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyHash = 'ptf_lock_hash';
  static const _keySalt = 'ptf_lock_salt';
  static const _keyRecovery = 'ptf_lock_recovery';

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
    final hash = _hashPin(pin, salt);
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
  }

  // ── Verification ──────────────────────────────────────────────────────

  /// Verifies the entered PIN. Returns true on match.
  static Future<bool> verifyPIN(String pin) async {
    final salt = await _storage.read(key: _keySalt);
    final stored = await _storage.read(key: _keyHash);
    if (salt == null || stored == null) return false;
    return _hashPin(pin, salt) == stored;
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

  static String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$pin:$salt:pomtechflow');
    return sha256.convert(bytes).toString();
  }

  static String _randomHex(int byteCount) {
    final rng = Random.secure();
    return List.generate(byteCount, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
