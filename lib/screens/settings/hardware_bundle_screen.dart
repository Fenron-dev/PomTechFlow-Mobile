import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/hardware_bundle_provider.dart';
import '../../providers/database_provider.dart';
import '../../db/database.dart';

const _hwTypes = [
  'PC', 'LAPTOP', 'MONITOR', 'PRINTER', 'ROUTER',
  'SWITCH', 'SERVER', 'PHONE', 'TABLET', 'OTHER',
];
const _hwLabels = {
  'PC': 'PC', 'LAPTOP': 'Laptop', 'MONITOR': 'Monitor',
  'PRINTER': 'Drucker', 'ROUTER': 'Router', 'SWITCH': 'Switch',
  'SERVER': 'Server', 'PHONE': 'Telefon', 'TABLET': 'Tablet',
  'OTHER': 'Sonstiges',
};
const _hwIcons = {
  'PC': Icons.computer, 'LAPTOP': Icons.laptop, 'MONITOR': Icons.monitor,
  'PRINTER': Icons.print, 'ROUTER': Icons.router, 'SWITCH': Icons.device_hub,
  'SERVER': Icons.dns, 'PHONE': Icons.phone_android, 'TABLET': Icons.tablet,
  'OTHER': Icons.devices_other,
};

class HardwareBundleScreen extends ConsumerWidget {
  const HardwareBundleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundlesAsync = ref.watch(hardwareBundlesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Hardware Bundles')),
      body: bundlesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (bundles) {
          if (bundles.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('Noch keine Bundles'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showForm(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Neues Bundle'),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: bundles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _BundleCard(
              bundle: bundles[i],
              onEdit: () => _showForm(context, ref, bundles[i]),
              onDelete: () => _delete(context, ref, bundles[i].bundle.id),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showForm(
      BuildContext context, WidgetRef ref, BundleWithItems? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BundleForm(existing: existing),
    );
    ref.invalidate(hardwareBundlesProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Bundle löschen?'),
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
    await (db.delete(db.hardwareBundles)..where((b) => b.id.equals(id))).go();
    ref.invalidate(hardwareBundlesProvider);
  }
}

class _BundleCard extends StatelessWidget {
  final BundleWithItems bundle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _BundleCard(
      {required this.bundle, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(bundle.bundle.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact),
                IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact),
              ],
            ),
            if (bundle.bundle.description != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(bundle.bundle.description!,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: bundle.items
                  .map((item) => Chip(
                        avatar: Icon(
                            _hwIcons[item.type] ?? Icons.devices_other,
                            size: 14),
                        label: Text(item.name ?? _hwLabels[item.type] ?? item.type),
                        visualDensity: VisualDensity.compact,
                        labelStyle: Theme.of(context).textTheme.labelSmall,
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Formular ────────────────────────────────────────────────────────────────

class _BundleForm extends ConsumerStatefulWidget {
  final BundleWithItems? existing;
  const _BundleForm({this.existing});

  @override
  ConsumerState<_BundleForm> createState() => _BundleFormState();
}

class _BundleFormState extends ConsumerState<_BundleForm> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  List<_ItemDraft> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.bundle.name;
      _descCtrl.text = widget.existing!.bundle.description ?? '';
      _items = widget.existing!.items
          .map((i) => _ItemDraft(
                type: i.type,
                name: i.name ?? '',
                serial: i.serial ?? '',
                notes: i.notes ?? '',
              ))
          .toList();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _addItem() {
    setState(() => _items.add(_ItemDraft(type: 'LAPTOP')));
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);

    String bundleId;
    if (widget.existing == null) {
      bundleId = 'bundle_${DateTime.now().millisecondsSinceEpoch}';
      await db.into(db.hardwareBundles).insert(
            HardwareBundlesCompanion.insert(
              id: drift.Value(bundleId),
              name: _nameCtrl.text.trim(),
              description: drift.Value(_descCtrl.text.trim().isEmpty
                  ? null
                  : _descCtrl.text.trim()),
            ),
          );
    } else {
      bundleId = widget.existing!.bundle.id;
      await (db.update(db.hardwareBundles)
            ..where((b) => b.id.equals(bundleId)))
          .write(HardwareBundlesCompanion(
        name: drift.Value(_nameCtrl.text.trim()),
        description: drift.Value(_descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim()),
      ));
      await (db.delete(db.hardwareBundleItems)
            ..where((i) => i.bundleId.equals(bundleId)))
          .go();
    }

    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      await db.into(db.hardwareBundleItems).insert(
            HardwareBundleItemsCompanion.insert(
              bundleId: bundleId,
              type: item.type,
              name: drift.Value(item.name.isEmpty ? null : item.name),
              serial: drift.Value(item.serial.isEmpty ? null : item.serial),
              notes: drift.Value(item.notes.isEmpty ? null : item.notes),
              sortOrder: drift.Value(i),
            ),
          );
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.existing == null ? 'Neues Bundle' : 'Bundle bearbeiten',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton(onPressed: _save, child: const Text('Speichern')),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Beschreibung'),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('Geräte',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.primary)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Gerät'),
                    ),
                  ],
                ),
                ..._items.asMap().entries.map((e) => _ItemRow(
                      draft: e.value,
                      onRemove: () =>
                          setState(() => _items.removeAt(e.key)),
                      onChanged: (d) =>
                          setState(() => _items[e.key] = d),
                    )),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemDraft {
  String type;
  String name;
  String serial;
  String notes;
  _ItemDraft({
    this.type = 'LAPTOP',
    this.name = '',
    this.serial = '',
    this.notes = '',
  });
  _ItemDraft copyWith({String? type, String? name, String? serial, String? notes}) =>
      _ItemDraft(
          type: type ?? this.type,
          name: name ?? this.name,
          serial: serial ?? this.serial,
          notes: notes ?? this.notes);
}

class _ItemRow extends StatefulWidget {
  final _ItemDraft draft;
  final VoidCallback onRemove;
  final ValueChanged<_ItemDraft> onChanged;
  const _ItemRow(
      {required this.draft, required this.onRemove, required this.onChanged});

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _serialCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.draft.name);
    _serialCtrl = TextEditingController(text: widget.draft.serial);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serialCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: widget.draft.type,
                    decoration: const InputDecoration(
                        labelText: 'Typ', isDense: true),
                    items: _hwTypes
                        .map((t) => DropdownMenuItem(
                            value: t, child: Text(_hwLabels[t] ?? t)))
                        .toList(),
                    onChanged: (v) =>
                        widget.onChanged(widget.draft.copyWith(type: v)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.red),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Bezeichnung', isDense: true),
              onChanged: (v) => widget.onChanged(widget.draft.copyWith(name: v)),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _serialCtrl,
              decoration: const InputDecoration(
                  labelText: 'Seriennummer', isDense: true),
              onChanged: (v) => widget.onChanged(widget.draft.copyWith(serial: v)),
            ),
          ],
        ),
      ),
    );
  }
}
