import 'package:bonsoir/bonsoir.dart';

const _kServiceType = '_pomflow._tcp';

class DiscoveredServer {
  final String name;
  final String host;
  final int port;

  const DiscoveredServer({required this.name, required this.host, required this.port});
}

/// Advertises this device as a PomTechFlow sync server on the local network.
class MdnsAdvertiser {
  BonsoirBroadcast? _broadcast;

  Future<void> start(int port, String deviceName) async {
    final service = BonsoirService(
      name: deviceName,
      type: _kServiceType,
      port: port,
    );
    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.ready;
    await _broadcast!.start();
  }

  Future<void> stop() async {
    await _broadcast?.stop();
    _broadcast = null;
  }
}

/// Discovers PomTechFlow sync servers on the local network.
class MdnsDiscovery {
  BonsoirDiscovery? _discovery;
  final List<DiscoveredServer> _found = [];
  final void Function(DiscoveredServer) onFound;
  final void Function(String name) onLost;

  MdnsDiscovery({required this.onFound, required this.onLost});

  List<DiscoveredServer> get servers => List.unmodifiable(_found);

  Future<void> start() async {
    _discovery = BonsoirDiscovery(type: _kServiceType);
    await _discovery!.ready;

    _discovery!.eventStream!.listen((event) {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        event.service?.resolve(_discovery!.serviceResolver);
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
        final svc = event.service as ResolvedBonsoirService?;
        if (svc == null) return;
        final host = svc.host;
        final port = svc.port;
        if (host == null) return;
        final server = DiscoveredServer(name: svc.name, host: host, port: port);
        _found.removeWhere((s) => s.name == svc.name);
        _found.add(server);
        onFound(server);
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
        final name = event.service?.name ?? '';
        _found.removeWhere((s) => s.name == name);
        onLost(name);
      }
    });

    await _discovery!.start();
  }

  Future<void> stop() async {
    await _discovery?.stop();
    _discovery = null;
    _found.clear();
  }
}
