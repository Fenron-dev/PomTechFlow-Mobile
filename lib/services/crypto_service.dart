import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// AES-256-CBC encryption with PBKDF2-HMAC-SHA256 key derivation.
///
/// Encrypted backup format (JSON wrapper):
/// ```json
/// {
///   "pomtechflow_encrypted": true,
///   "version": 1,
///   "salt": "<base64 16 bytes>",
///   "iv":   "<base64 16 bytes>",
///   "mac":  "<base64 32 bytes – HMAC-SHA256 of salt+iv+ciphertext>",
///   "data": "<base64 AES-256-CBC ciphertext>"
/// }
/// ```
class CryptoService {
  static const int _iterations = 10000;
  static const int _keyLength = 32; // AES-256

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns true when [jsonStr] looks like an encrypted backup.
  static bool isEncrypted(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr);
      return m is Map && m['pomtechflow_encrypted'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Encrypts [plaintext] with [password].  Returns a JSON wrapper string.
  static String encryptBackup(String plaintext, String password) {
    final salt = _randomBytes(16);
    final iv = _randomBytes(16);
    final key = _pbkdf2(password, salt);

    final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: enc.IV(iv));
    final cipherBytes = base64Decode(encrypted.base64);

    // MAC = HMAC-SHA256(salt ++ iv ++ ciphertext)
    final macInput = Uint8List(salt.length + iv.length + cipherBytes.length)
      ..setRange(0, salt.length, salt)
      ..setRange(salt.length, salt.length + iv.length, iv)
      ..setRange(salt.length + iv.length, salt.length + iv.length + cipherBytes.length, cipherBytes);

    final mac = Hmac(sha256, key).convert(macInput).bytes;

    final wrapper = {
      'pomtechflow_encrypted': true,
      'version': 1,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'mac': base64Encode(mac),
      'data': encrypted.base64,
    };
    return const JsonEncoder.withIndent('  ').convert(wrapper);
  }

  /// Decrypts an encrypted backup wrapper.
  /// Throws [WrongPasswordException] on wrong password / corrupted data.
  static String decryptBackup(String encryptedJson, String password) {
    final Map<String, dynamic> wrapper;
    try {
      wrapper = jsonDecode(encryptedJson) as Map<String, dynamic>;
    } catch (_) {
      throw WrongPasswordException('Ungültiges Format');
    }

    final salt = base64Decode(wrapper['salt'] as String);
    final iv = base64Decode(wrapper['iv'] as String);
    final storedMac = base64Decode(wrapper['mac'] as String);
    final cipherBytes = base64Decode(wrapper['data'] as String);

    final key = _pbkdf2(password, salt);

    // Verify MAC before decrypting (prevents padding oracle attacks)
    final macInput = Uint8List(salt.length + iv.length + cipherBytes.length)
      ..setRange(0, salt.length, salt)
      ..setRange(salt.length, salt.length + iv.length, iv)
      ..setRange(salt.length + iv.length, salt.length + iv.length + cipherBytes.length, cipherBytes);

    final expectedMac = Hmac(sha256, key).convert(macInput).bytes;
    if (!_constantTimeEqual(storedMac, expectedMac)) {
      throw WrongPasswordException('Falsches Passwort oder beschädigte Datei');
    }

    try {
      final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
      return encrypter.decrypt(
        enc.Encrypted(cipherBytes),
        iv: enc.IV(iv),
      );
    } catch (_) {
      throw WrongPasswordException('Entschlüsselung fehlgeschlagen');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static Uint8List _pbkdf2(String password, Uint8List salt) {
    final passwordBytes = utf8.encode(password);
    final hmac = Hmac(sha256, passwordBytes);
    final result = <int>[];
    var blockNum = 1;

    while (result.length < _keyLength) {
      // U₁ = PRF(Password, Salt || INT(blockNum))
      final u0 = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt);
      u0[salt.length] = (blockNum >> 24) & 0xff;
      u0[salt.length + 1] = (blockNum >> 16) & 0xff;
      u0[salt.length + 2] = (blockNum >> 8) & 0xff;
      u0[salt.length + 3] = blockNum & 0xff;

      var u = Uint8List.fromList(hmac.convert(u0).bytes);
      final xor = u.toList();

      for (int i = 1; i < _iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (int j = 0; j < xor.length; j++) {
          xor[j] ^= u[j];
        }
      }
      result.addAll(xor);
      blockNum++;
    }

    return Uint8List.fromList(result.sublist(0, _keyLength));
  }

  static Uint8List _randomBytes(int count) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(count, (_) => rng.nextInt(256)));
  }

  /// Constant-time byte comparison to prevent timing attacks.
  static bool _constantTimeEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

class WrongPasswordException implements Exception {
  final String message;
  WrongPasswordException(this.message);
  @override
  String toString() => message;
}
