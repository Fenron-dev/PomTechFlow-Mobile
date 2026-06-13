import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../providers/customers_provider.dart';

/// Schneller „Neuer Kunde"-Dialog: Name + aufklappbar Adresse/Kontakt.
/// Legt den Kunden an und gibt dessen ID zurück, oder null bei Abbruch.
/// Wird im Task-Formular und im Quick-Assign-Sheet wiederverwendet.
Future<String?> showQuickCreateCustomerDialog(
    BuildContext context, WidgetRef ref) async {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final streetCtrl = TextEditingController();
  final zipCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  bool showMore = false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.person_add_outlined),
          SizedBox(width: 10),
          Text('Neuer Kunde'),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'z.B. Müller GmbH',
                ),
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
              if (!showMore)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setLocal(() => showMore = true),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Adresse & Kontakt'),
                  ),
                )
              else ...[
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: streetCtrl,
                  decoration: const InputDecoration(labelText: 'Straße / Nr.'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 8),
                Row(children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: zipCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'PLZ'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: cityCtrl,
                      decoration: const InputDecoration(labelText: 'Ort'),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    ),
  );

  final name = nameCtrl.text.trim();
  drift.Value<String?> v(TextEditingController c) =>
      drift.Value(c.text.trim().isEmpty ? null : c.text.trim());
  final companion = CustomersCompanion.insert(
    name: name,
    phone: v(phoneCtrl),
    email: v(emailCtrl),
    street: v(streetCtrl),
    zipCode: v(zipCtrl),
    city: v(cityCtrl),
  );
  for (final c in [
    nameCtrl, phoneCtrl, emailCtrl, streetCtrl, zipCtrl, cityCtrl
  ]) {
    c.dispose();
  }
  if (confirmed != true || name.isEmpty) return null;

  final db = ref.read(databaseProvider);
  final newId = await db.into(db.customers).insertReturning(companion);
  ref.invalidate(customersProvider);
  return newId.id;
}
