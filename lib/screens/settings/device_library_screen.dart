import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/device_library_provider.dart';
import '../../providers/database_provider.dart';
import '../../db/database.dart';

const _hardwareTypes = [
  'PC', 'LAPTOP', 'MONITOR', 'PRINTER', 'ROUTER',
  'SWITCH', 'SERVER', 'PHONE', 'TABLET', 'OTHER',
];

const _hardwareLabels = {
  'PC': 'PC', 'LAPTOP': 'Laptop', 'MONITOR': 'Monitor',
  'PRINTER': 'Drucker', 'ROUTER': 'Router', 'SWITCH': 'Switch',
  'SERVER': 'Server', 'PHONE': 'Telefon', 'TABLET': 'Tablet',
  'OTHER': 'Sonstiges',
};

const _hardwareIcons = {
  'PC': Icons.computer, 'LAPTOP': Icons.laptop, 'MONITOR': Icons.monitor,
  'PRINTER': Icons.print, 'ROUTER': Icons.router, 'SWITCH': Icons.device_hub,
  'SERVER': Icons.dns, 'PHONE': Icons.phone_android, 'TABLET': Icons.tablet,
  'OTHER': Icons.devices_other,
};

class DeviceLibraryScreen extends ConsumerStatefulWidget {
  const DeviceLibraryScreen({super.key});

  @override
  ConsumerState<DeviceLibraryScreen> createState() =>
      _DeviceLibraryScreenState();
}

class _DeviceLibraryScreenState extends ConsumerState<DeviceLibraryScreen> {
  String _filter = '';
  String? _typeFilter;

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(deviceLibraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geräte-Bibliothek'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Gerät hinzufügen',
            onPressed: () => _showForm(context, ref, null),
          ),
        ],
      ),
      body: Column(
        children: [
          // Suchleiste + Typ-Filter
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Suchen...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Alle'),
                  selected: _typeFilter == null,
                  onSelected: (_) => setState(() => _typeFilter = null),
                ),
                const SizedBox(width: 6),
                ..._hardwareTypes.map((t) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(_hardwareLabels[t] ?? t),
                        selected: _typeFilter == t,
                        avatar: Icon(_hardwareIcons[t], size: 16),
                        onSelected: (_) =>
                            setState(() => _typeFilter = _typeFilter == t ? null : t),
                      ),
                    )),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: devicesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (devices) {
                final filtered = devices.where((d) {
                  if (_typeFilter != null && d.type != _typeFilter) {
                    return false;
                  }
                  if (_filter.isEmpty) return true;
                  return d.name.toLowerCase().contains(_filter) ||
                      (d.serial?.toLowerCase().contains(_filter) ?? false) ||
                      (d.notes?.toLowerCase().contains(_filter) ?? false) ||
                      (_hardwareLabels[d.type]?.toLowerCase().contains(_filter) ??
                          false);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.devices_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          devices.isEmpty
                              ? 'Noch keine Geräte in der Bibliothek'
                              : 'Keine Geräte gefunden',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline),
                        ),
                        if (devices.isEmpty) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _showForm(context, ref, null),
                            icon: const Icon(Icons.add),
                            label: const Text('Gerät hinzufügen'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final d = filtered[i];
                    return _DeviceCard(
                      device: d,
                      onEdit: () => _showForm(context, ref, d),
                      onDelete: () => _delete(context, ref, d.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showForm(
      BuildContext context, WidgetRef ref, DevicePreset? device) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DeviceForm(existing: device),
    );
    ref.invalidate(deviceLibraryProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Gerät löschen?'),
        content: const Text('Das Gerät wird aus der Bibliothek entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.devicePresets)..where((d) => d.id.equals(id))).go();
    ref.invalidate(deviceLibraryProvider);
  }
}

class _DeviceCard extends StatelessWidget {
  final DevicePreset device;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DeviceCard(
      {required this.device, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final icon = _hardwareIcons[device.type] ?? Icons.devices_other;
    final label = _hardwareLabels[device.type] ?? device.type;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(device.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.primary)),
            if (device.serial != null)
              Text('S/N: ${device.serial}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (device.notes != null)
              Text(device.notes!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline)),
          ],
        ),
        isThreeLine: device.serial != null || device.notes != null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Formular ─────────────────────────────────────────────────────────────────

class _DeviceForm extends ConsumerStatefulWidget {
  final DevicePreset? existing;
  const _DeviceForm({this.existing});

  @override
  ConsumerState<_DeviceForm> createState() => _DeviceFormState();
}

class _DeviceFormState extends ConsumerState<_DeviceForm> {
  late String _type;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _serialCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _type = widget.existing?.type ?? 'PC';
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _serialCtrl = TextEditingController(text: widget.existing?.serial ?? '');
    _notesCtrl = TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serialCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final db = ref.read(databaseProvider);
    if (widget.existing == null) {
      await db.into(db.devicePresets).insert(DevicePresetsCompanion.insert(
            type: _type,
            name: name,
            serial: drift.Value(_serialCtrl.text.trim().isEmpty
                ? null
                : _serialCtrl.text.trim()),
            notes: drift.Value(_notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim()),
          ));
    } else {
      await (db.update(db.devicePresets)
            ..where((d) => d.id.equals(widget.existing!.id)))
          .write(DevicePresetsCompanion(
        type: drift.Value(_type),
        name: drift.Value(name),
        serial: drift.Value(_serialCtrl.text.trim().isEmpty
            ? null
            : _serialCtrl.text.trim()),
        notes: drift.Value(_notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim()),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null
                ? 'Gerät hinzufügen'
                : 'Gerät bearbeiten',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Typ'),
            items: _hardwareTypes
                .map((t) => DropdownMenuItem(
                    value: t, child: Text(_hardwareLabels[t] ?? t)))
                .toList(),
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Bezeichnung *',
                hintText: 'z.B. Dell Latitude 5540'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _serialCtrl,
            decoration: const InputDecoration(
                labelText: 'Seriennummer', hintText: 'Optional'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
                labelText: 'Notizen', hintText: 'Optional'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: Text(widget.existing == null ? 'Hinzufügen' : 'Speichern'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
