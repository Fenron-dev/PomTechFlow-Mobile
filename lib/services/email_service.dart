import 'package:url_launcher/url_launcher.dart';

class EmailService {
  /// Öffnet den E-Mail-Client mit vorausgefüllten Feldern.
  /// [recipient] – E-Mail-Adresse des Empfängers (optional, z.B. Kunden-E-Mail)
  /// [subject] – Betreff
  /// [body] – Nachrichtentext
  static Future<void> sendEmail({
    String? recipient,
    required String subject,
    required String body,
  }) async {
    final encoded = Uri(
      scheme: 'mailto',
      path: recipient ?? '',
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );
    if (await canLaunchUrl(encoded)) {
      await launchUrl(encoded);
    }
  }

  /// Interner Abrechnungsentwurf — geht an die interne Billing-Adresse, NICHT an den Kunden.
  static Future<void> sendBillingDraft({
    required String billingEmail,
    required String taskTitle,
    String? customerName,
    required int totalMinutes,
    required int aeCount,
    required String technicianName,
    required String companyName,
    DateTime? billedAt,
    int? estimatedMinutes,
  }) async {
    final subject = 'Abrechnung: $taskTitle'
        '${customerName != null ? ' – $customerName' : ''}';
    final statusLine = billedAt != null
        ? 'Abgerechnet: ${billedAt.toLocal().day.toString().padLeft(2, '0')}.${billedAt.toLocal().month.toString().padLeft(2, '0')}.${billedAt.toLocal().year}'
        : 'Status: Noch nicht abgerechnet';
    final budgetLine = estimatedMinutes != null
        ? '\nBudget:      $estimatedMinutes Min (${totalMinutes > estimatedMinutes ? '⚠ überschritten' : 'eingehalten'})'
        : '';
    final body =
        'Interner Abrechnungsvorschlag\n\n'
        'Auftrag:    $taskTitle\n'
        '${customerName != null ? 'Kunde:      $customerName\n' : ''}'
        'Zeitaufwand: $totalMinutes Min\n'
        'AE:          $aeCount'
        '$budgetLine\n'
        'Techniker:  $technicianName\n'
        'Firma:      $companyName\n'
        '$statusLine';
    await sendEmail(
      recipient: billingEmail.isEmpty ? null : billingEmail,
      subject: subject,
      body: body,
    );
  }

  /// Erstellt eine vorausgefüllte E-Mail für einen IT-Support-Bericht.
  static Future<void> sendReportEmail({
    String? customerEmail,
    String? customerName,
    required String taskTitle,
    required int totalMinutes,
    required int aeCount,
    required String technicianName,
    required String companyName,
  }) async {
    final subject = 'IT-Support Bericht: $taskTitle';
    final body = '''Sehr geehrte Damen und Herren,${customerName != null ? '\nSehr geehrte/r $customerName,' : ''}

anbei erhalten Sie den IT-Support Bericht für den Auftrag:

  Auftrag: $taskTitle
  Zeitaufwand: $totalMinutes Minuten ($aeCount AE)
  Techniker: $technicianName

Für Rückfragen stehen wir Ihnen gerne zur Verfügung.

Mit freundlichen Grüßen
$technicianName
$companyName''';

    await sendEmail(
      recipient: customerEmail,
      subject: subject,
      body: body,
    );
  }
}
