import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/customers_provider.dart';
import 'customer_quick_create.dart';

/// Ergebnis der Kunden-Auswahl. `customerId == null` bedeutet „Kein Kunde".
/// Ein `null`-Rückgabewert von [showCustomerPicker] bedeutet Abbruch.
class CustomerPickResult {
  final String? customerId;
  const CustomerPickResult(this.customerId);
}

/// Durchsuchbarer Kunden-Picker mit „zuletzt verwendet"-Bereich und
/// Schnellanlage. Ersetzt einfache Dropdowns im Task-Formular & Quick-Assign.
Future<CustomerPickResult?> showCustomerPicker(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
}) {
  return showModalBottomSheet<CustomerPickResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CustomerPickerSheet(selectedId: selectedId),
  );
}

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  final String? selectedId;
  const _CustomerPickerSheet({this.selectedId});

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  String _q = '';

  Widget _tile(Customer c) {
    final sub = [c.zipCode, c.city]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    return ListTile(
      leading: CircleAvatar(
        child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?'),
      ),
      title: Text(c.name),
      subtitle: sub.isEmpty ? null : Text(sub),
      trailing: widget.selectedId == c.id ? const Icon(Icons.check) : null,
      onTap: () => Navigator.pop(context, CustomerPickResult(c.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);
    final recentIds =
        ref.watch(recentCustomerIdsProvider).valueOrNull ?? const <String>[];

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => customersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Fehler: $e')),
          data: (customers) {
            final byId = {for (final c in customers) c.id: c};
            final filtered = _q.isEmpty
                ? customers
                : customers
                    .where((c) =>
                        c.name.toLowerCase().contains(_q) ||
                        (c.city ?? '').toLowerCase().contains(_q) ||
                        (c.email ?? '').toLowerCase().contains(_q))
                    .toList();
            final recents = _q.isEmpty
                ? recentIds
                    .map((id) => byId[id])
                    .whereType<Customer>()
                    .toList()
                : const <Customer>[];

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Kunde suchen…',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        setState(() => _q = v.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.block_outlined),
                        title: const Text('Kein Kunde'),
                        trailing: widget.selectedId == null
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(
                            context, const CustomerPickResult(null)),
                      ),
                      ListTile(
                        leading: const Icon(Icons.person_add_outlined),
                        title: const Text('Neuer Kunde…'),
                        onTap: () async {
                          final id =
                              await showQuickCreateCustomerDialog(context, ref);
                          if (id != null && context.mounted) {
                            Navigator.pop(context, CustomerPickResult(id));
                          }
                        },
                      ),
                      if (recents.isNotEmpty) ...[
                        const _PickerHeader('Zuletzt verwendet'),
                        ...recents.map(_tile),
                        const _PickerHeader('Alle Kunden'),
                      ],
                      ...filtered.map(_tile),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Keine Treffer')),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PickerHeader extends StatelessWidget {
  final String title;
  const _PickerHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
