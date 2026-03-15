import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../../providers/tasks_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../db/database.dart';

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

class HardwareTab extends ConsumerWidget {
  final String taskId;
  const HardwareTab({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hwAsync = ref.watch(hardwareProvider(taskId));

    return Scaffold(
      body: hwAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text('Noch keine Hardware',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _HardwareCard(
              item: items[i],
              onDelete: () async {
                final db = ref.read(databaseProvider);
                await (db.delete(db.hardware)
                      ..where((h) => h.id.equals(items[i].id)))
                    .go();
                ref.invalidate(hardwareProvider(taskId));
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HardwareForm(taskId: taskId, ref: ref),
    );
    ref.invalidate(hardwareProvider(taskId));
  }
}

class _HardwareCard extends StatelessWidget {
  final HardwareData item;
  final VoidCallback onDelete;

  const _HardwareCard({required this.item, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final icon = _hardwareIcons[item.type] ?? Icons.devices_other;
    final label = _hardwareLabels[item.type] ?? item.type;

    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(item.name ?? label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary)),
            if (item.serial != null)
              Text('S/N: ${item.serial}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (item.notes != null)
              Text(item.notes!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          color: Theme.of(context).colorScheme.error,
          onPressed: onDelete,
        ),
        isThreeLine: item.serial != null || item.notes != null,
      ),
    );
  }
}

class _HardwareForm extends ConsumerStatefulWidget {
  final String taskId;
  final WidgetRef ref;
  const _HardwareForm({required this.taskId, required this.ref});

  @override
  ConsumerState<_HardwareForm> createState() => _HardwareFormState();
}

class _HardwareFormState extends ConsumerState<_HardwareForm> {
  String _type = 'PC';
  final _nameCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serialCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    final existing = await (db.select(db.hardware)
          ..where((h) => h.taskId.equals(widget.taskId)))
        .get();
    await db.into(db.hardware).insert(HardwareCompanion.insert(
          taskId: widget.taskId,
          type: _type,
          name: drift.Value(
              _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim()),
          serial: drift.Value(
              _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim()),
          notes: drift.Value(
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
          sortOrder: drift.Value(existing.length),
        ));
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
          Text('Hardware hinzufügen',
              style: Theme.of(context).textTheme.titleLarge),
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
                labelText: 'Bezeichnung', hintText: 'z.B. Dell Latitude 5540'),
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
            decoration:
                const InputDecoration(labelText: 'Notizen', hintText: 'Optional'),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Hinzufügen')),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
