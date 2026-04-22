import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../sync_auth.dart';

Router pairingRouter(String serverDeviceId, String serverName) {
  final router = Router();

  // POST /api/pairing/claim
  // Body: { "pairingToken": "...", "deviceId": "...", "deviceName": "..." }
  // Returns: { "accessToken": "...", "refreshToken": "...", "serverDeviceId": "..." }
  router.post('/api/pairing/claim', (Request req) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response(400, body: jsonEncode({'error': 'invalid_json'}),
          headers: {'content-type': 'application/json'});
    }

    final pairingToken = body['pairingToken'] as String?;
    final clientDeviceId = body['deviceId'] as String?;
    final clientDeviceName = body['deviceName'] as String? ?? '';

    if (pairingToken == null || clientDeviceId == null) {
      return Response(400,
          body: jsonEncode({'error': 'missing_fields'}),
          headers: {'content-type': 'application/json'});
    }

    final valid = await SyncAuth.validatePairingToken(pairingToken, serverDeviceId);
    if (!valid) {
      return Response(401,
          body: jsonEncode({'error': 'invalid_or_expired_token'}),
          headers: {'content-type': 'application/json'});
    }

    final tokens = await SyncAuth.issueTokens(clientDeviceId, clientDeviceName);
    return Response.ok(
      jsonEncode({
        'accessToken': tokens.access,
        'refreshToken': tokens.refresh,
        'serverDeviceId': serverDeviceId,
        'serverName': serverName,
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  // POST /api/pairing/refresh
  // Body: { "refreshToken": "..." }
  router.post('/api/pairing/refresh', (Request req) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response(400, body: '{}',
          headers: {'content-type': 'application/json'});
    }

    final refreshToken = body['refreshToken'] as String?;
    if (refreshToken == null) {
      return Response(400,
          body: jsonEncode({'error': 'missing_refresh_token'}),
          headers: {'content-type': 'application/json'});
    }

    final tokens = await SyncAuth.refreshTokens(refreshToken);
    if (tokens == null) {
      return Response(401,
          body: jsonEncode({'error': 'invalid_refresh_token'}),
          headers: {'content-type': 'application/json'});
    }

    return Response.ok(
      jsonEncode({'accessToken': tokens.access, 'refreshToken': tokens.refresh}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}
