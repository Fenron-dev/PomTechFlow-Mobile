import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../../db/database.dart';
import 'sync_auth.dart';
import 'routes/health_routes.dart';
import 'routes/pairing_routes.dart';
import 'routes/sync_routes.dart';

const kSyncPort = 8765;

class SyncServer {
  HttpServer? _server;
  bool get isRunning => _server != null;

  Future<void> start({
    required AppDatabase db,
    required String serverDeviceId,
    required String serverName,
    required bool syncAppSettings,
  }) async {
    if (_server != null) return;

    final router = Router();
    final jwtMiddleware = _jwtAuth();

    // Public routes
    final health = healthRouter(serverName, serverDeviceId);
    final pairing = pairingRouter(serverDeviceId, serverName);

    // Protected sync routes
    final sync = syncRouter(db, serverDeviceId, syncAppSettings);

    router.mount('/', health.call);
    router.mount('/', pairing.call);
    // Wrap sync routes with auth middleware
    router.mount('/api/v1/', Pipeline().addMiddleware(jwtMiddleware).addHandler(sync.call));
    // Also handle /api/v1/sync directly (shelf_router mounts)
    router.get('/api/v1/sync', Pipeline().addMiddleware(jwtMiddleware).addHandler(sync.call));
    router.post('/api/v1/sync/push', Pipeline().addMiddleware(jwtMiddleware).addHandler(sync.call));

    final handler = Pipeline()
        .addMiddleware(_corsHeaders())
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, kSyncPort);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── CORS (for possible web/desktop clients) ───────────────────────────────

  Middleware _corsHeaders() => (handler) => (req) async {
        final res = await handler(req);
        return res.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          ...res.headers,
        });
      };

  // ── JWT Auth Middleware ───────────────────────────────────────────────────

  Middleware _jwtAuth() => (handler) => (req) async {
        // Allow OPTIONS pre-flight
        if (req.method == 'OPTIONS') return Response.ok('');

        final authHeader = req.headers['authorization'];
        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return Response(401,
              body: '{"error":"missing_token"}',
              headers: {'content-type': 'application/json'});
        }

        final token = authHeader.substring(7);
        final deviceId = await SyncAuth.verifyAccessToken(token);
        if (deviceId == null) {
          return Response(401,
              body: '{"error":"invalid_token"}',
              headers: {'content-type': 'application/json'});
        }

        return handler(req.change(context: {'clientDeviceId': deviceId}));
      };
}
