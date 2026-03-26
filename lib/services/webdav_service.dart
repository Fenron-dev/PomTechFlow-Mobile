import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WebDavConfig {
  final String url;
  final String username;
  final String password;

  const WebDavConfig({
    required this.url,
    required this.username,
    required this.password,
  });

  bool get isConfigured => url.trim().isNotEmpty;

  /// Ensures the base URL always ends with '/'.
  String get normalizedUrl {
    final u = url.trim();
    return u.endsWith('/') ? u : '$u/';
  }
}

class WebDavFile {
  final String name;
  const WebDavFile({required this.name});
}

class WebDavService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Config persistence ──────────────────────────────────────────────────────

  static Future<WebDavConfig> loadConfig() async {
    return WebDavConfig(
      url: await _storage.read(key: 'webdav_url') ?? '',
      username: await _storage.read(key: 'webdav_user') ?? '',
      password: await _storage.read(key: 'webdav_password') ?? '',
    );
  }

  static Future<void> saveConfig(WebDavConfig config) async {
    await _storage.write(key: 'webdav_url', value: config.url.trim());
    await _storage.write(key: 'webdav_user', value: config.username.trim());
    await _storage.write(key: 'webdav_password', value: config.password.trim());
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  static String _authHeader(String user, String pass) =>
      'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

  static HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 15);

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Tests the connection. Returns null on success, error message on failure.
  static Future<String?> testConnection(WebDavConfig config) async {
    try {
      final uri = Uri.parse(config.normalizedUrl);
      final client = _client();
      final request = await client.openUrl('PROPFIND', uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.authorizationHeader,
          _authHeader(config.username, config.password));
      request.headers.set('Depth', '0');
      request.headers.contentType =
          ContentType('text', 'xml', charset: 'utf-8');
      request.write(
          '<?xml version="1.0"?><D:propfind xmlns:D="DAV:"><D:prop><D:displayname/></D:prop></D:propfind>');
      final response = await request.close().timeout(const Duration(seconds: 10));
      await response.drain<void>();
      client.close();
      if (response.statusCode == 401) return 'Authentifizierung fehlgeschlagen (401)';
      if (response.statusCode == 404) return 'Verzeichnis nicht gefunden (404)';
      if (response.statusCode >= 400) return 'Serverfehler: HTTP ${response.statusCode}';
      return null; // success
    } on SocketException catch (e) {
      return 'Netzwerkfehler: ${e.message}';
    } on TimeoutException {
      return 'Verbindungstimeout – Server nicht erreichbar';
    } catch (e) {
      return 'Fehler: $e';
    }
  }

  /// Uploads a UTF-8 JSON string to WebDAV as [filename].
  static Future<void> uploadJson(
      WebDavConfig config, String content, String filename) async {
    final uri = Uri.parse('${config.normalizedUrl}$filename');
    final bytes = utf8.encode(content);
    final client = _client();
    final request = await client.openUrl('PUT', uri)
        .timeout(const Duration(seconds: 30));
    request.headers.set(HttpHeaders.authorizationHeader,
        _authHeader(config.username, config.password));
    request.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    request.headers.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(const Duration(seconds: 30));
    await response.drain<void>();
    client.close();
    if (response.statusCode >= 400) {
      throw Exception('Upload fehlgeschlagen: HTTP ${response.statusCode}');
    }
  }

  /// Lists all .json files in the WebDAV directory.
  static Future<List<WebDavFile>> listJsonFiles(WebDavConfig config) async {
    final uri = Uri.parse(config.normalizedUrl);
    final client = _client();
    final request = await client.openUrl('PROPFIND', uri)
        .timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.authorizationHeader,
        _authHeader(config.username, config.password));
    request.headers.set('Depth', '1');
    request.headers.contentType =
        ContentType('text', 'xml', charset: 'utf-8');
    request.write(
        '<?xml version="1.0"?><D:propfind xmlns:D="DAV:"><D:prop><D:displayname/></D:prop></D:propfind>');
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    client.close();
    if (response.statusCode >= 400) {
      throw Exception('Listing fehlgeschlagen: HTTP ${response.statusCode}');
    }

    // Extract href values (works with any XML namespace prefix)
    final hrefs = RegExp(r'<[^:>]*:?href[^>]*>([^<]+)</')
        .allMatches(body)
        .map((m) => Uri.decodeFull(m.group(1)!.trim()))
        .toList();

    // Extract filenames from path segments, skip the directory entry itself
    final baseName = uri.pathSegments
        .where((s) => s.isNotEmpty)
        .lastOrNull
        ?.toLowerCase() ?? '';

    final results = <WebDavFile>[];
    for (final href in hrefs) {
      final segments = href.split('/').where((s) => s.isNotEmpty).toList();
      final name = segments.lastOrNull ?? '';
      if (name.isEmpty) continue;
      if (name.toLowerCase() == baseName) continue; // skip directory itself
      if (!name.toLowerCase().endsWith('.json')) continue;
      results.add(WebDavFile(name: name));
    }

    // Sort newest first (by filename, which typically contains date)
    results.sort((a, b) => b.name.compareTo(a.name));
    return results;
  }

  /// Downloads a file from WebDAV and returns its UTF-8 content.
  static Future<String> downloadJson(
      WebDavConfig config, String filename) async {
    final uri = Uri.parse('${config.normalizedUrl}$filename');
    final client = _client();
    final request = await client.openUrl('GET', uri)
        .timeout(const Duration(seconds: 30));
    request.headers.set(HttpHeaders.authorizationHeader,
        _authHeader(config.username, config.password));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    client.close();
    if (response.statusCode >= 400) {
      throw Exception('Download fehlgeschlagen: HTTP ${response.statusCode}');
    }
    return utf8.decode(bytes);
  }
}
