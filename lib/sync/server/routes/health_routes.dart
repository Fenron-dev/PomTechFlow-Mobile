import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

Router healthRouter(
  String serverName,
  String serverDeviceId, {
  int Function()? getNudgeCounter,
  void Function()? doNudge,
}) {
  final router = Router();

  router.get('/health', (_) {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'name': serverName,
        'deviceId': serverDeviceId,
        'app': 'PomTechFlow',
        'version': '1.0',
        if (getNudgeCounter != null) 'nudge': getNudgeCounter(),
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  // GET /api/v1/nudge — check current nudge counter (used by clients)
  router.get('/api/v1/nudge', (_) {
    return Response.ok(
      jsonEncode({'nudge': getNudgeCounter?.call() ?? 0}),
      headers: {'content-type': 'application/json'},
    );
  });

  // POST /api/v1/nudge — trigger nudge (server-initiated sync request)
  router.post('/api/v1/nudge', (_) {
    doNudge?.call();
    return Response.ok(
      jsonEncode({'nudge': getNudgeCounter?.call() ?? 0}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}
