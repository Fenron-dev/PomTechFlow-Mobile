import 'dart:convert';
import 'dart:math';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  mOptions: MacOsOptions(useDataProtectionKeyChain: false),
);
const _kSecretKey = 'sync_jwt_secret';
const _kRefreshTokensKey = 'sync_refresh_tokens';

// Token lifetimes
const Duration _kAccessTtl = Duration(hours: 24);
const Duration _kRefreshTtl = Duration(days: 7);
const Duration _kPairingTtl = Duration(minutes: 5);

class SyncAuth {
  static Future<String> _getOrCreateSecret() async {
    String? secret = await _kStorage.read(key: _kSecretKey);
    if (secret == null || secret.isEmpty) {
      final rng = Random.secure();
      final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
      secret = base64Url.encode(bytes);
      await _kStorage.write(key: _kSecretKey, value: secret);
    }
    return secret;
  }

  // ── Pairing Token ─────────────────────────────────────────────────────────

  static Future<String> generatePairingToken(String serverDeviceId) async {
    final secret = await _getOrCreateSecret();
    final jwt = JWT({'sub': serverDeviceId, 'type': 'pairing'});
    return jwt.sign(
      SecretKey(secret),
      expiresIn: _kPairingTtl,
    );
  }

  static Future<bool> validatePairingToken(String token, String serverDeviceId) async {
    try {
      final secret = await _getOrCreateSecret();
      final jwt = JWT.verify(token, SecretKey(secret));
      return jwt.payload['type'] == 'pairing' &&
          jwt.payload['sub'] == serverDeviceId;
    } catch (_) {
      return false;
    }
  }

  // ── Access / Refresh Tokens ───────────────────────────────────────────────

  static Future<({String access, String refresh})> issueTokens(
    String clientDeviceId,
    String clientDeviceName,
  ) async {
    final secret = await _getOrCreateSecret();

    final access = JWT({
      'sub': clientDeviceId,
      'name': clientDeviceName,
      'type': 'access',
    }).sign(SecretKey(secret), expiresIn: _kAccessTtl);

    final refresh = JWT({
      'sub': clientDeviceId,
      'name': clientDeviceName,
      'type': 'refresh',
    }).sign(SecretKey(secret), expiresIn: _kRefreshTtl);

    // Persist refresh token set
    final stored = await _loadRefreshTokens();
    stored[clientDeviceId] = refresh;
    await _saveRefreshTokens(stored);

    return (access: access, refresh: refresh);
  }

  static Future<({String access, String refresh})?> refreshTokens(
    String refreshToken,
  ) async {
    try {
      final secret = await _getOrCreateSecret();
      final jwt = JWT.verify(refreshToken, SecretKey(secret));
      if (jwt.payload['type'] != 'refresh') return null;

      final deviceId = jwt.payload['sub'] as String;
      final stored = await _loadRefreshTokens();
      if (stored[deviceId] != refreshToken) return null;

      return issueTokens(deviceId, jwt.payload['name'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Validates an access token and returns the client's deviceId, or null.
  static Future<String?> verifyAccessToken(String token) async {
    try {
      final secret = await _getOrCreateSecret();
      final jwt = JWT.verify(token, SecretKey(secret));
      if (jwt.payload['type'] != 'access') return null;
      return jwt.payload['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> revokeClient(String clientDeviceId) async {
    final stored = await _loadRefreshTokens();
    stored.remove(clientDeviceId);
    await _saveRefreshTokens(stored);
  }

  // ── 6-digit PIN ───────────────────────────────────────────────────────────

  /// Derives a 6-digit PIN from the pairing token (first 6 decimal digits of sha hash).
  static String tokenToPin(String token) {
    var code = 0;
    for (final ch in token.codeUnits) {
      code = (code * 31 + ch) & 0x7FFFFFFF;
    }
    return (code % 1000000).toString().padLeft(6, '0');
  }

  // ── Persist helpers ───────────────────────────────────────────────────────

  static Future<Map<String, String>> _loadRefreshTokens() async {
    final raw = await _kStorage.read(key: _kRefreshTokensKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveRefreshTokens(Map<String, String> tokens) async {
    await _kStorage.write(key: _kRefreshTokensKey, value: jsonEncode(tokens));
  }

  // ── Client-side token storage ─────────────────────────────────────────────

  static const _kClientAccessKey = 'sync_client_access';
  static const _kClientRefreshKey = 'sync_client_refresh';

  static Future<void> saveClientTokens(String access, String refresh) async {
    await _kStorage.write(key: _kClientAccessKey, value: access);
    await _kStorage.write(key: _kClientRefreshKey, value: refresh);
  }

  static Future<String?> loadClientAccessToken() =>
      _kStorage.read(key: _kClientAccessKey);

  static Future<String?> loadClientRefreshToken() =>
      _kStorage.read(key: _kClientRefreshKey);

  static Future<void> clearClientTokens() async {
    await _kStorage.delete(key: _kClientAccessKey);
    await _kStorage.delete(key: _kClientRefreshKey);
  }
}
