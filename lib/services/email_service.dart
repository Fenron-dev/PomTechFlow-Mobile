import 'dart:io';
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
