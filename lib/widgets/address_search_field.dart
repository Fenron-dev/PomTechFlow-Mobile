import 'package:flutter/material.dart';
import '../services/address_lookup_service.dart';

/// Eingabefeld mit Adress-Autovervollständigung (OSM Nominatim).
/// Ruft [onSelected] mit dem gewählten Vorschlag auf, damit das umgebende
/// Formular Straße/PLZ/Ort befüllen kann. Debounct intern (~400 ms).
class AddressSearchField extends StatefulWidget {
  final void Function(AddressSuggestion) onSelected;
  const AddressSearchField({super.key, required this.onSelected});

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  String _latest = '';

  Future<Iterable<AddressSuggestion>> _options(String text) async {
    final q = text.trim();
    if (q.length < 3) return const [];
    _latest = q;
    // Debounce + Nominatim-Ratelimit schonen.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (q != _latest) return const []; // durch neuere Eingabe überholt
    try {
      return await AddressLookupService.search(q);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<AddressSuggestion>(
      displayStringForOption: (s) => s.label,
      optionsBuilder: (value) => _options(value.text),
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Adresse suchen (OSM)',
            hintText: 'z.B. Musterstraße 1, Berlin',
            prefixIcon: Icon(Icons.travel_explore_outlined),
          ),
          textCapitalization: TextCapitalization.words,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final o = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 18),
                    title: Text(o.label,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => onSelected(o),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
