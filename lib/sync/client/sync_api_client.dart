import 'dart:convert';
import 'package:http/http.dart' as http;
import '../server/sync_auth.dart';

class SyncApiClient {
  final String host;
  final int port;

  SyncApiClient({required this.host, required this.port});

  String get _base => 'http://$host:$port';

  // ── Health Check ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> checkHealth() async {
    try {
      final res = await http.get(Uri.parse('$_base/health')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  // ── Pairing ───────────────────────────────────────────────────────────────

  Future<bool> claim({
    required String pairingToken,
    required String deviceId,
    required String deviceName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/api/pairing/claim'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'pairingToken': pairingToken,
          'deviceId': deviceId,
          'deviceName': deviceName,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await SyncAuth.saveClientTokens(
          data['accessToken'] as String,
          data['refreshToken'] as String,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Sync Pull ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> pull({DateTime? since}) async {
    final token = await _getToken();
    if (token == null) return null;

    try {
      final uri = Uri.parse('$_base/api/v1/sync').replace(
        queryParameters: since != null ? {'since': since.toUtc().toIso8601String()} : null,
      );
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'content-type': 'application/json',
      }).timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      if (res.statusCode == 401) {
        // Try refresh
        final refreshed = await _tryRefreshToken();
        if (refreshed) return pull(since: since);
      }
    } catch (_) {}
    return null;
  }

  // ── Sync Push ─────────────────────────────────────────────────────────────

  /// Returns list of conflict maps, or null on error.
  Future<List<Map<String, dynamic>>?> push(Map<String, dynamic> payload) async {
    final token = await _getToken();
    if (token == null) return null;

    try {
      final res = await http.post(
        Uri.parse('$_base/api/v1/sync/push'),
        headers: {
          'Authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return (body['conflicts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      }
      if (res.statusCode == 401) {
        final refreshed = await _tryRefreshToken();
        if (refreshed) return push(payload);
      }
    } catch (_) {}
    return null;
  }

  // ── Token helpers ─────────────────────────────────────────────────────────

  Future<String?> _getToken() => SyncAuth.loadClientAccessToken();

  Future<bool> _tryRefreshToken() async {
    final refreshToken = await SyncAuth.loadClientRefreshToken();
    if (refreshToken == null) return false;
    try {
      final res = await http.post(
        Uri.parse('$_base/api/pairing/refresh'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await SyncAuth.saveClientTokens(
          data['accessToken'] as String,
          data['refreshToken'] as String,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }
}
