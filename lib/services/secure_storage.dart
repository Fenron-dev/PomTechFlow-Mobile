import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// macOS: Data-Protection-Keychain erfordert keychain-access-groups mit
// gültigem Provisioning-Profil (Team-ID). Für Desktop-Builds nutzen wir
// SharedPreferences — die App-Sandbox isoliert die Daten ausreichend.

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

bool get _useMacOsFallback => !kIsWeb && Platform.isMacOS;

Future<String?> secureRead(String key) async {
  if (_useMacOsFallback) {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('_sec_$key');
  }
  return _storage.read(key: key);
}

Future<void> secureWrite(String key, String value) async {
  if (_useMacOsFallback) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('_sec_$key', value);
    return;
  }
  await _storage.write(key: key, value: value);
}

Future<void> secureDelete(String key) async {
  if (_useMacOsFallback) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('_sec_$key');
    return;
  }
  await _storage.delete(key: key);
}
