import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';

// ─── Data Models ─────────────────────────────────────────────────────────────

class _TaskRef {
  final String taskId;
  final String taskTitle;
  final String taskStatus;
  final DateTime? plannedDate;
  final DateTime createdAt;

  const _TaskRef({
    required this.taskId,
    required this.taskTitle,
    required this.taskStatus,
    this.plannedDate,
    required this.createdAt,
  });
}

class _DeviceGroup {
  final String type;
  final String displayName;
  final String? serial;
  final List<_TaskRef> tasks;

  const _DeviceGroup({
    required this.type,
    required this.displayName,
    this.serial,
    required this.tasks,
  });

  String get groupKey =>
      '$type|${(serial?.trim().toLowerCase() ?? '')}|${serial == null || serial!.trim().isEmpty ? displayName.toLowerCase() : ''}';
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class DeviceHistoryScreen extends ConsumerStatefulWidget {
  const DeviceHistoryScreen({super.key});

  @override
  ConsumerState<DeviceHistoryScreen> createState() =>
      _DeviceHistoryScreenState();
}

class _DeviceHistoryScreenState extends ConsumerState<DeviceHistoryScreen> {
  List<_DeviceGroup> _all = [];
  List<_DeviceGroup> _filtered = [];
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  // tracks which group keys are expanded
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);

    // Load all hardware entries
    final hardwareList = await db.select(db.hardware).get();

    // Load all tasks (id → task) for joining
    final taskList = await db.select(db.tasks).get();
    final taskMap = {for (final t in taskList) t.id: t};

    // Group hardware by (type, normalized serial) or (type, name) if no serial
    final Map<String, _DeviceGroup> groups = {};
    for (final hw in hardwareList) {
      final serial = hw.serial?.trim();
      final hasSerial = serial != null && serial.isNotEmpty;
      final name = hw.name?.trim() ?? hw.type;

      final key = hasSerial
          ? '${hw.type}|${serial.toLowerCase()}'
          : '${hw.type}|name:${name.toLowerCase()}';

      final task = taskMap[hw.taskId];
      final ref = task == null
          ? null
          : _TaskRef(
              taskId: task.id,
              taskTitle: task.title,
              taskStatus: task.status,
              plannedDate: task.plannedDate,
              createdAt: task.createdAt,
            );

      if (groups.containsKey(key)) {
        if (ref != null) {
          groups[key] = _DeviceGroup(
            type: groups[key]!.type,
            displayName: groups[key]!.displayName,
            serial: groups[key]!.serial,
            tasks: [...groups[key]!.tasks, ref],
          );
        }
      } else {
        groups[key] = _DeviceGroup(
          type: hw.type,
          displayName: name,
          serial: hasSerial ? serial : null,
          tasks: ref != null ? [ref] : [],
        );
      }
    }

    // Sort: devices used in multiple tasks first, then by name
    final sorted = groups.values.toList()
      ..sort((a, b) {
        final c = b.tasks.length.compareTo(a.tasks.length);
        return c != 0 ? c : a.displayName.compareTo(b.displayName);
      });

    if (mounted) {
      setState(() {
        _all = sorted;
        _filtered = sorted;
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = _all);
      return;
    }
    setState(() {
      _filtered = _all.where((d) {
        return d.displayName.toLowerCase().contains(q) ||
            (d.serial?.toLowerCase().contains(q) ?? false) ||
            d.type.toLowerCase().contains(q) ||
            d.tasks.any((t) => t.taskTitle.toLowerCase().contains(q));
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geräteverlauf'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Gerät, Seriennummer oder Task suchen…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? Center(
                  child: Text(
                    _searchCtrl.text.isNotEmpty
                        ? 'Keine Geräte gefunden.'
                        : 'Noch keine Hardware in Tasks erfasst.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _DeviceTile(
                    device: _filtered[i],
                    expanded: _expanded.contains(_filtered[i].groupKey),
                    onToggle: () => setState(() {
                      final k = _filtered[i].groupKey;
                      if (_expanded.contains(k)) {
                        _expanded.remove(k);
                      } else {
                        _expanded.add(k);
                      }
                    }),
                  ),
                ),
    );
  }
}

// ─── Device Tile ─────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final _DeviceGroup device;
  final bool expanded;
  final VoidCallback onToggle;

  const _DeviceTile({
    required this.device,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.secondaryContainer,
              child: Icon(_iconFor(device.type),
                  color: cs.onSecondaryContainer, size: 20),
            ),
            title: Text(device.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [
                _labelFor(device.type),
                if (device.serial != null) 'S/N: ${device.serial}',
              ].join(' · '),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text('${device.tasks.length} Task${device.tasks.length == 1 ? '' : 's'}'),
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Icon(expanded
                    ? Icons.expand_less
                    : Icons.expand_more),
              ],
            ),
            onTap: device.tasks.isEmpty ? null : onToggle,
          ),
          if (expanded && device.tasks.isNotEmpty) ...[
            const Divider(height: 1),
            ...device.tasks.map((t) => _TaskRow(task: t)),
          ],
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final _TaskRef task;
  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (task.taskStatus) {
      'COMPLETED' => Colors.green,
      'ACTIVE'    => cs.primary,
      'PAUSED'    => Colors.orange,
      _           => cs.outline,
    };
    final label = switch (task.taskStatus) {
      'COMPLETED' => 'Erledigt',
      'ACTIVE'    => 'Aktiv',
      'PAUSED'    => 'Pausiert',
      _           => 'Geplant',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(task.taskTitle,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

IconData _iconFor(String type) => switch (type) {
      'PC'      => Icons.computer,
      'LAPTOP'  => Icons.laptop,
      'MAC'     => Icons.desktop_mac,
      'MACBOOK' => Icons.laptop_mac,
      'MONITOR' => Icons.monitor,
      'PRINTER' => Icons.print,
      'ROUTER'  => Icons.router,
      'SWITCH'  => Icons.device_hub,
      'SERVER'  => Icons.dns,
      'PHONE'   => Icons.phone_android,
      'TABLET'  => Icons.tablet,
      _         => Icons.devices_other,
    };

String _labelFor(String type) => switch (type) {
      'PC'      => 'PC',
      'LAPTOP'  => 'Laptop',
      'MAC'     => 'Mac',
      'MACBOOK' => 'MacBook',
      'MONITOR' => 'Monitor',
      'PRINTER' => 'Drucker',
      'ROUTER'  => 'Router',
      'SWITCH'  => 'Switch',
      'SERVER'  => 'Server',
      'PHONE'   => 'Telefon',
      'TABLET'  => 'Tablet',
      _         => 'Gerät',
    };
