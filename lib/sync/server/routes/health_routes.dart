import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

Router healthRouter(String serverName, String serverDeviceId) {
  final router = Router();

  router.get('/health', (_) {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'name': serverName,
        'deviceId': serverDeviceId,
        'app': 'PomTechFlow',
        'version': '1.0',
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}
