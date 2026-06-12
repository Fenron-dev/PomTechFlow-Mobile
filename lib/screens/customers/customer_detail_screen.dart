import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../db/database.dart';
import '../../providers/database_provider.dart';
import '../../providers/customers_provider.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final contactsByCustomerProvider =
    FutureProvider.family<List<Contact>, String>((ref, customerId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.contacts)
        ..where((c) => c.customerId.equals(customerId) & c.isActive.equals(true))
        ..orderBy([
          (c) => drift.OrderingTerm.asc(c.lastName),
          (c) => drift.OrderingTerm.asc(c.firstName),
        ]))
      .get();
});

// ── Detail-Screen ─────────────────────────────────────────────────────────────

class CustomerDetailScreen extends ConsumerWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsByCustomerProvider(customer.id));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(customer.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showCustomerForm(context, ref),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.people_outline), text: 'Kontakte'),
            Tab(icon: Icon(Icons.info_outline), text: 'Details'),
          ]),
        ),
        body: TabBarView(children: [
          // ── Tab: Kontakte ─────────────────────────────────────────────────
          _ContactsTab(customer: customer, contactsAsync: contactsAsync, ref: ref),
          // ── Tab: Details ──────────────────────────────────────────────────
          _DetailsTab(customer: customer),
        ]),
      ),
    );
  }

  Future<void> _showCustomerForm(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerEditForm(customer: customer),
    );
    ref.invalidate(customersProvider);
  }
}

// ── Kontakte-Tab ──────────────────────────────────────────────────────────────

class _ContactsTab extends StatelessWidget {
  final Customer customer;
  final AsyncValue<List<Contact>> contactsAsync;
  final WidgetRef ref;

  const _ContactsTab({
    required this.customer,
    required this.contactsAsync,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (contacts) {
          if (contacts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  const Text('Noch keine Kontakte'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (ctx, i) => _ContactCard(
              contact: contacts[i],
              onEdit: () => _showContactForm(ctx, contacts[i]),
              onDelete: () => _deleteContact(ctx, contacts[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showContactForm(context, null),
        child: const Icon(Icons.person_add_outlined),
      ),
    );
  }

  Future<void> _showContactForm(BuildContext context, Contact? contact) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ContactForm(customerId: customer.id, contact: contact),
    );
    ref.invalidate(contactsByCustomerProvider(customer.id));
  }

  Future<void> _deleteContact(BuildContext context, Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kontakt löschen?'),
        content: Text(
            '${contact.firstName} ${contact.lastName} wird entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.contacts)..where((c) => c.id.equals(contact.id)))
        .write(const ContactsCompanion(isActive: drift.Value(false)));
    ref.invalidate(contactsByCustomerProvider(contact.customerId));
  }
}

// ── Kontakt-Karte ─────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  final Contact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactCard(
      {required this.contact, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final details = [
      if (contact.position != null) contact.position!,
      if (contact.email != null) contact.email!,
      if (contact.phoneMobile != null) contact.phoneMobile!,
      if (contact.phoneLandline != null &&
          contact.phoneLandline != contact.phoneMobile)
        contact.phoneLandline!,
    ];

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.secondaryContainer,
          child: Text(
            contact.firstName.isNotEmpty ? contact.firstName[0].toUpperCase() : '?',
            style: TextStyle(color: cs.secondary),
          ),
        ),
        title: Text('${contact.firstName} ${contact.lastName}'),
        subtitle: details.isNotEmpty
            ? Text(details.join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.edit_outlined),
                visualDensity: VisualDensity.compact,
                onPressed: onEdit),
            IconButton(
                icon: Icon(Icons.delete_outline, color: cs.error),
                visualDensity: VisualDensity.compact,
                onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

// ── Details-Tab ───────────────────────────────────────────────────────────────

class _DetailsTab extends StatelessWidget {
  final Customer customer;
  const _DetailsTab({required this.customer});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Adresse zusammenbauen
    final addressLines = <String>[];
    final streetLine = [customer.street, customer.houseNumber]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    if (streetLine.isNotEmpty) addressLines.add(streetLine);
    final cityLine = [customer.zipCode, customer.city]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    if (cityLine.isNotEmpty) addressLines.add(cityLine);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customer.email != null)
                  _InfoRow(Icons.email_outlined, customer.email!),
                if (customer.phone != null)
                  _InfoRow(Icons.phone_outlined, customer.phone!),
                if (addressLines.isNotEmpty)
                  _InfoRow(Icons.location_on_outlined,
                      addressLines.join('\n')),
                if (customer.notes != null && customer.notes!.isNotEmpty)
                  _InfoRow(Icons.notes_outlined, customer.notes!),
                if (customer.email == null &&
                    customer.phone == null &&
                    addressLines.isEmpty &&
                    (customer.notes == null || customer.notes!.isEmpty))
                  Text('Keine weiteren Details.',
                      style: TextStyle(color: cs.outline)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

// ── Kontakt-Formular ──────────────────────────────────────────────────────────

class _ContactForm extends ConsumerStatefulWidget {
  final String customerId;
  final Contact? contact;
  const _ContactForm({required this.customerId, this.contact});

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _landlineCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    if (c != null) {
      _firstNameCtrl.text = c.firstName;
      _lastNameCtrl.text = c.lastName;
      _positionCtrl.text = c.position ?? '';
      _emailCtrl.text = c.email ?? '';
      _mobileCtrl.text = c.phoneMobile ?? '';
      _landlineCtrl.text = c.phoneLandline ?? '';
      _locationCtrl.text = c.location ?? '';
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _positionCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _landlineCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_firstNameCtrl.text.trim().isEmpty ||
        _lastNameCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    drift.Value<String?> v(TextEditingController c) =>
        drift.Value(c.text.trim().isEmpty ? null : c.text.trim());
    final now = DateTime.now();

    if (widget.contact == null) {
      await db.into(db.contacts).insert(ContactsCompanion.insert(
            customerId: widget.customerId,
            firstName: _firstNameCtrl.text.trim(),
            lastName: _lastNameCtrl.text.trim(),
            position: v(_positionCtrl),
            email: v(_emailCtrl),
            phoneMobile: v(_mobileCtrl),
            phoneLandline: v(_landlineCtrl),
            location: v(_locationCtrl),
          ));
    } else {
      await (db.update(db.contacts)
            ..where((c) => c.id.equals(widget.contact!.id)))
          .write(ContactsCompanion(
        firstName: drift.Value(_firstNameCtrl.text.trim()),
        lastName: drift.Value(_lastNameCtrl.text.trim()),
        position: v(_positionCtrl),
        email: v(_emailCtrl),
        phoneMobile: v(_mobileCtrl),
        phoneLandline: v(_landlineCtrl),
        location: v(_locationCtrl),
        modifiedAt: drift.Value(now),
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
              widget.contact == null ? 'Neuer Kontakt' : 'Kontakt bearbeiten',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _firstNameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Vorname *',
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lastNameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nachname *',
                      border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _positionCtrl,
              decoration: const InputDecoration(
                  labelText: 'Position / Abteilung',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'E-Mail',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Mobil',
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _landlineCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Festnetz',
                      border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                  labelText: 'Standort / Büro',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(widget.contact == null ? 'Anlegen' : 'Speichern'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Kunden-Bearbeiten-Formular (inline) ──────────────────────────────────────

class _CustomerEditForm extends ConsumerStatefulWidget {
  final Customer customer;
  const _CustomerEditForm({required this.customer});

  @override
  ConsumerState<_CustomerEditForm> createState() => _CustomerEditFormState();
}

class _CustomerEditFormState extends ConsumerState<_CustomerEditForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _streetCtrl;
  late final TextEditingController _houseNumberCtrl;
  late final TextEditingController _zipCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl = TextEditingController(text: c.name);
    _emailCtrl = TextEditingController(text: c.email ?? '');
    _phoneCtrl = TextEditingController(text: c.phone ?? '');
    _streetCtrl = TextEditingController(text: c.street ?? '');
    _houseNumberCtrl = TextEditingController(text: c.houseNumber ?? '');
    _zipCtrl = TextEditingController(text: c.zipCode ?? '');
    _cityCtrl = TextEditingController(text: c.city ?? '');
    _notesCtrl = TextEditingController(text: c.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _streetCtrl.dispose();
    _houseNumberCtrl.dispose();
    _zipCtrl.dispose();
    _cityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    drift.Value<String?> v(TextEditingController c) =>
        drift.Value(c.text.trim().isEmpty ? null : c.text.trim());
    await (db.update(db.customers)
          ..where((c) => c.id.equals(widget.customer.id)))
        .write(CustomersCompanion(
      name: drift.Value(_nameCtrl.text.trim()),
      email: v(_emailCtrl),
      phone: v(_phoneCtrl),
      street: v(_streetCtrl),
      houseNumber: v(_houseNumberCtrl),
      zipCode: v(_zipCtrl),
      city: v(_cityCtrl),
      notes: v(_notesCtrl),
      modifiedAt: drift.Value(DateTime.now()),
    ));
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
            Text('Kunde bearbeiten',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Name *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'E-Mail', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Telefon', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _streetCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Straße', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _houseNumberCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nr.', border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _zipCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'PLZ', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _cityCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Ort', border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Notizen', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Speichern')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
