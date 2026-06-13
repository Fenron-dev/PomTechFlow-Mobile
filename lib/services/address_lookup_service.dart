import 'dart:convert';
import 'package:http/http.dart' as http;

/// Ein Adressvorschlag aus OSM Nominatim (in Felder zerlegt).
class AddressSuggestion {
  final String label; // vollständige Anzeige
  final String? street; // Straße (ohne Hausnummer)
  final String? houseNumber;
  final String? zip;
  final String? city;

  const AddressSuggestion({
    required this.label,
    this.street,
    this.houseNumber,
    this.zip,
    this.city,
  });

  /// Straße + Hausnummer zusammengesetzt (für Formulare mit einem Straßenfeld).
  String get streetLine =>
      [street, houseNumber].where((s) => s != null && s.isNotEmpty).join(' ');
}

/// Adress-Suche über die kostenlose OSM-Nominatim-API.
/// Hinweis Nutzungsrichtlinie: aussagekräftiger User-Agent, max. ~1 Anfrage/s
/// (Aufrufer debouncen). Nur DE/AT/CH.
class AddressLookupService {
  static Future<List<AddressSuggestion>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '6',
      'countrycodes': 'de,at,ch',
      'q': q,
    });

    final resp = await http.get(uri, headers: {
      'User-Agent': 'PomTechFlow/1.0 (IT-Support Zeiterfassung)',
      'Accept-Language': 'de',
    });
    if (resp.statusCode != 200) return const [];

    final data = jsonDecode(resp.body) as List<dynamic>;
    final out = <AddressSuggestion>[];
    for (final e in data) {
      final m = e as Map<String, dynamic>;
      final a = (m['address'] as Map<String, dynamic>?) ?? const {};
      final road = a['road'] as String?;
      final house = a['house_number'] as String?;
      final zip = a['postcode'] as String?;
      final city = (a['city'] ?? a['town'] ?? a['village'] ?? a['municipality'])
          as String?;
      if (road == null && zip == null && city == null) continue;
      out.add(AddressSuggestion(
        label: m['display_name'] as String? ?? '',
        street: road,
        houseNumber: house,
        zip: zip,
        city: city,
      ));
    }
    return out;
  }
}
