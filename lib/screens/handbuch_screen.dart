import 'package:flutter/material.dart';

class HandbuchScreen extends StatelessWidget {
  const HandbuchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Handbuch')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Section(
            icon: Icons.dashboard_outlined,
            title: 'Dashboard',
            children: [
              _Entry(
                title: 'Laufender Task',
                body:
                    'Das Dashboard zeigt den aktuell aktiven Task mit Echtzeit-Timer, Status-Badge und dem zuletzt gespeicherten Sitzungstyp. Über die Statusleiste kannst du den Task direkt auf Abgeschlossen setzen.',
              ),
              _Entry(
                title: 'Neuen Task erstellen (+ Taste)',
                body:
                    'Tippe auf das + oben rechts. Es erscheinen drei Optionen:\n'
                    '• Standard-Task – öffnet das Erfassungsformular\n'
                    '• Aus Vorlage – wähle eine gespeicherte Task-Vorlage\n'
                    '• Schnellstart – legt sofort einen Zeitmess-Task an; Titel und Details kannst du später ergänzen',
              ),
              _Entry(
                title: 'Hamburger-Menü (⋮)',
                body:
                    'Das Dreipunkte-Menü oben rechts führt zu Einstellungen, Statistiken und dem Monatsabschluss-Bericht, ohne dass du den aktuellen Task verlässt.',
              ),
            ],
          ),
          _Section(
            icon: Icons.checklist_outlined,
            title: 'Tasks',
            children: [
              _Entry(
                title: 'Status-Workflow',
                body:
                    'Geplant → Aktiv → Abgeschlossen\n'
                    'Den Status änderst du in der Task-Übersicht per Dropdown oder über den Timer-Start (setzt Task automatisch auf Aktiv).',
              ),
              _Entry(
                title: 'Priorität',
                body:
                    'Normal · Hoch · Kritisch\n'
                    'Kritische Tasks erscheinen rot markiert in der Liste. Hohe Priorität wird mit einem orangefarbenen Balken hervorgehoben.',
              ),
              _Entry(
                title: 'Zeiterfassung & AE',
                body:
                    'Der Timer läuft pro Sitzung. Typen: Arbeit, Pause, Fahrt, Telefon.\n'
                    'AE (Arbeitseinheit) wird automatisch aus den Gesamtminuten berechnet: 1 AE = einstellbares Intervall (Standard 10 Min, aufrunden).\n'
                    'AE kopieren: In der Übersicht gibt es einen Button "AE kopieren" für die Zwischenablage.',
              ),
              _Entry(
                title: 'Zeitbudget & Warnanzeige',
                body:
                    'Im Formular kannst du ein Zeitbudget in Minuten setzen. Sobald die erfasste Zeit das Budget übersteigt, erscheint in der Task-Karte ein oranges Warnsymbol und in der Übersicht eine Fortschrittsleiste.',
              ),
              _Entry(
                title: 'Wiederkehrende Tasks',
                body:
                    'Aktiviere "Wiederkehrend" im Formular und wähle Intervall (täglich, wöchentlich, monatlich). Beim Abschließen wird automatisch ein neuer Task für den nächsten Termin angelegt.',
              ),
              _Entry(
                title: 'Verknüpfte Tasks (Backlinks)',
                body:
                    'In der Übersicht können Tasks miteinander verknüpft werden (Typen: Verwandt, Blockiert, Nachfolger).\n'
                    'Eine Verknüpfung ist bidirektional: Sie erscheint auf beiden Tasks als klickbarer Link. Rückverweise sind mit ↩ gekennzeichnet.',
              ),
              _Entry(
                title: 'Checkliste (Todos)',
                body:
                    'Todos können manuell hinzugefügt oder aus einem Workflow-Template übernommen werden. Erledigte Punkte werden durchgestrichen und im Fortschrittsbalken gezählt.',
              ),
              _Entry(
                title: 'Hardware',
                body:
                    'Im Tab Hardware kannst du Geräte dem Task zuordnen:\n'
                    '• Aus Geräte-Bibliothek wählen\n'
                    '• Ganzes Hardware-Bundle anwenden\n'
                    '• Manuell erfassen\n'
                    'Typ, Bezeichnung und Seriennummer werden im PDF-Bericht aufgeführt.',
              ),
              _Entry(
                title: 'Notizen (Task-Notizen)',
                body:
                    'Zeitgestempelte Einträge pro Task. Im Tab "Notizen" gibt es eine Fernwartungs-Vorlage (Problem / Ursache / Lösung / Ergebnis), die als formatierten Block gespeichert wird.',
              ),
              _Entry(
                title: 'Fotos',
                body:
                    'Fotos per Kamera, Galerie (mobil) oder Datei-Picker (Desktop) hinzufügen.\n'
                    'Lang-Drücken auf ein Foto öffnet Optionen: Beschriftung bearbeiten oder löschen.\n'
                    'Beschriftungen erscheinen als halbtransparentes Overlay im Raster.',
              ),
              _Entry(
                title: 'PDF-Export',
                body:
                    'In der Task-Übersicht: Button "PDF erstellen". Der Bericht enthält Task-Details, Sitzungen, Todos, Hardware und Fotos.\n'
                    'Speicherort: konfigurierbar in den Einstellungen.',
              ),
              _Entry(
                title: 'E-Mail-Entwurf',
                body:
                    'Über den Mail-Button in der Übersicht öffnet sich ein Abrechnungs-Entwurf im E-Mail-Client mit vorausgefülltem Betreff, Zeitangabe und AE. Empfänger kommt aus den Einstellungen (Abrechnungs-E-Mail).',
              ),
              _Entry(
                title: 'Task-Übergabe (.ptf)',
                body:
                    'Tasks können als .ptf-Datei exportiert und auf einem anderen Gerät importiert werden. Fotos werden base64-kodiert eingebettet.',
              ),
            ],
          ),
          _Section(
            icon: Icons.note_outlined,
            title: 'Allgemeine Notizen',
            children: [
              _Entry(
                title: 'Zweck',
                body:
                    'Der Notizen-Tab ist für geräteübergreifende Inhalte: FAQs, Gesprächsnotizen, Ideen, Wissensbasis. Im Gegensatz zu Task-Notizen sind sie keinem Task zugeordnet.',
              ),
              _Entry(
                title: 'Tags & Subtags',
                body:
                    'Tags werden beim Erstellen/Bearbeiten vergeben. Subtags mit Schrägstrich trennen: z.B. on/linux/install.\n'
                    'In der Tag-Leiste kannst du nach einem Tag filtern. Der Filter kombiniert sich mit der Suche.',
              ),
              _Entry(
                title: 'Suche',
                body:
                    'Das Lupen-Symbol in der AppBar blendet ein Suchfeld ein. Die Suche filtert Inhalt und Tags gleichzeitig.',
              ),
            ],
          ),
          _Section(
            icon: Icons.devices_outlined,
            title: 'Geräte-Bibliothek & Hardware-Bundles',
            children: [
              _Entry(
                title: 'Geräte-Bibliothek',
                body:
                    'Eine Sammlung wiederverwendbarer Einzel-Geräte (Typ, Bezeichnung, Seriennummer, Notizen). Erreichbar über Einstellungen → Stammdaten → Geräte-Bibliothek.\n'
                    'Aus der Bibliothek kann direkt ein Gerät in einen Task-Hardware-Tab übernommen werden.',
              ),
              _Entry(
                title: 'Hardware-Bundles',
                body:
                    'Bundles gruppieren mehrere Geräte zu einem wiederverwendbaren Paket.\n'
                    '• "Aus Bibliothek" – wähle ein gespeichertes Gerät; es wird mit Typ, Bezeichnung und S/N vorausgefüllt\n'
                    '• "Manuell" – freie Eingabe\n'
                    '• Lesezeichen-Symbol (🔖) – manuell erfasste Geräte können beim Speichern des Bundles automatisch in die Geräte-Bibliothek übertragen werden',
              ),
            ],
          ),
          _Section(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Berichte',
            children: [
              _Entry(
                title: 'Task-PDF',
                body:
                    'Einzelbericht pro Task aus der Task-Übersicht. Enthält alle Daten des Tasks.',
              ),
              _Entry(
                title: 'Monatsabschluss',
                body:
                    'Erreichbar über Hamburger-Menü auf dem Dashboard oder Einstellungen → Berichte.\n'
                    'Kunden- und Monats-Filter, Vorschau der enthaltenen Tasks mit AE-Summe.\n'
                    'Optional: "Alle als abgerechnet markieren" – setzt billedAt auf alle Tasks.',
              ),
              _Entry(
                title: 'Alle Berichte',
                body:
                    'Liste aller bisher erzeugten PDFs mit Download- und Teilen-Optionen.',
              ),
            ],
          ),
          _Section(
            icon: Icons.settings_outlined,
            title: 'Einstellungen',
            children: [
              _Entry(
                title: 'Firmendaten & Branding',
                body:
                    'Firmenname, Techniker-Name und Logo werden in PDF-Berichten verwendet.',
              ),
              _Entry(
                title: 'AE-Intervall',
                body:
                    'Legt fest, wie viele Minuten eine Arbeitseinheit beträgt (Standard: 10 Min). Ändert die AE-Berechnung für alle Tasks.',
              ),
              _Entry(
                title: 'Speicherort',
                body:
                    'Optionaler Basis-Pfad für PDFs und Fotos auf diesem Gerät. Leer = App-Dokumente-Ordner.',
              ),
              _Entry(
                title: 'Abrechnungs-E-Mail',
                body:
                    'Interne E-Mail-Adresse für Abrechnungs-Entwürfe. Wird als Empfänger im Mail-Button vorausgefüllt.',
              ),
              _Entry(
                title: 'Timer-Einstellungen',
                body:
                    'Standard-Pausen-Minuten für die Schnellpausen-Buttons auf dem Dashboard.',
              ),
              _Entry(
                title: 'Workflows',
                body:
                    'Checklisten-Vorlagen. Ein Workflow enthält beliebig viele Einträge, die beim Anwenden als Todos in einen Task eingefügt werden.',
              ),
              _Entry(
                title: 'Task-Vorlagen',
                body:
                    'Vollständige Task-Vorlagen mit vorausgefüllten Todos, Hardware-Bundles und Workflow-Zuweisung. Aus dem Dashboard (+ → Aus Vorlage) anwendbar.',
              ),
              _Entry(
                title: 'Backup & Wiederherstellung',
                body:
                    'Erstellt eine vollständige JSON-Sicherung aller Daten (Tasks, Kunden, Workflows, Einstellungen). Backup vor App-Updates oder Gerätewechsel empfohlen.',
              ),
            ],
          ),
          _Section(
            icon: Icons.info_outline,
            title: 'Tipps & Tastenkürzel',
            children: [
              _Entry(
                title: 'Navigation zurück zur Root-Ansicht',
                body:
                    'Tippe auf den aktiven Tab (Dashboard, Tasks oder Notizen) erneut, um zur Startansicht des Tabs zurückzukehren – statt den Zurück-Button zu verwenden.',
              ),
              _Entry(
                title: 'Foto-Beschriftung',
                body:
                    'Lang-Drücken auf ein Foto im Foto-Tab öffnet ein Menü mit "Beschriftung bearbeiten". Die Beschriftung erscheint als Text-Overlay direkt auf dem Foto.',
              ),
              _Entry(
                title: 'Schnellstart-Timer',
                body:
                    'Dashboard → + → Schnellstart. Erstellt sofort einen Task mit Zeitstempel als Titel und startet den Timer. Details können später ergänzt werden.',
              ),
              _Entry(
                title: 'Desktop (Windows/Linux/macOS)',
                body:
                    'Auf Desktop-Plattformen wird eine Seitenleiste (NavigationRail) angezeigt. Bei breiten Fenstern (≥ 1200 px) erscheinen die Labels. Die Menüleiste oben bietet Datei- und Ansicht-Schnellzugriff.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Section ──────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<_Entry> children;

  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: EdgeInsets.zero,
        children: children
            .map((e) => _EntryTile(entry: e))
            .toList(),
      ),
    );
  }
}

class _Entry {
  final String title;
  final String body;
  const _Entry({required this.title, required this.body});
}

class _EntryTile extends StatelessWidget {
  final _Entry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text(
            entry.title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            entry.body,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}
