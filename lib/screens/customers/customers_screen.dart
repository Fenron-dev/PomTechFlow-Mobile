import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:url_launcher/url_launcher.dart';
import '../../providers/customers_provider.dart';
import '../../providers/database_provider.dart';
import '../../db/database.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kunden')),
      body: customersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (customers) {
          if (customers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.business_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('Noch keine Kunden'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: customers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _CustomerCard(
              customer: customers[i],
              onEdit: () => _showForm(context, ref, customers[i]),
              onDelete: () => _delete(context, ref, customers[i].id),
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
      BuildContext context, WidgetRef ref, Customer? customer) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerForm(customer: customer),
    );
    ref.invalidate(customersProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kunden löschen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.customers)..where((c) => c.id.equals(id))).go();
    ref.invalidate(customersProvider);
  }
}

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomerCard(
      {required this.customer, required this.onEdit, required this.onDelete});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Text(customer.name[0].toUpperCase(),
                      style: TextStyle(color: cs.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer.name,
                          style: Theme.of(context).textTheme.titleSmall),
                      if (customer.address != null)
                        Text(customer.address!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.outline),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (customer.phone != null ||
                customer.email != null ||
                customer.address != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (customer.phone != null)
                    ActionChip(
                      avatar: const Icon(Icons.phone_outlined, size: 16),
                      label: Text(customer.phone!),
                      onPressed: () =>
                          _launch('tel:${customer.phone}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (customer.email != null)
                    ActionChip(
                      avatar: const Icon(Icons.email_outlined, size: 16),
                      label: Text(customer.email!),
                      onPressed: () =>
                          _launch('mailto:${customer.email}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (customer.address != null)
                    ActionChip(
                      avatar:
                          const Icon(Icons.directions_outlined, size: 16),
                      label: const Text('Navigation'),
                      onPressed: () => _launch(
                          'https://maps.google.com/?q=${Uri.encodeComponent(customer.address!)}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (customer.notes != null && customer.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(customer.notes!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomerForm extends ConsumerStatefulWidget {
  final Customer? customer;
  const _CustomerForm({this.customer});

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) {
      _nameCtrl.text = widget.customer!.name;
      _emailCtrl.text = widget.customer!.email ?? '';
      _phoneCtrl.text = widget.customer!.phone ?? '';
      _addressCtrl.text = widget.customer!.address ?? '';
      _notesCtrl.text = widget.customer!.notes ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    v(String s) => drift.Value(s.trim().isEmpty ? null : s.trim());

    if (widget.customer == null) {
      await db.into(db.customers).insert(CustomersCompanion.insert(
            name: _nameCtrl.text.trim(),
            email: v(_emailCtrl.text),
            phone: v(_phoneCtrl.text),
            address: v(_addressCtrl.text),
            notes: v(_notesCtrl.text),
          ));
    } else {
      await (db.update(db.customers)
            ..where((c) => c.id.equals(widget.customer!.id)))
          .write(CustomersCompanion(
        name: drift.Value(_nameCtrl.text.trim()),
        email: v(_emailCtrl.text),
        phone: v(_phoneCtrl.text),
        address: v(_addressCtrl.text),
        notes: v(_notesCtrl.text),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.customer == null ? 'Neuer Kunde' : 'Kunde bearbeiten',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'E-Mail'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Telefon'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Adresse'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notizen'),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Speichern')),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
