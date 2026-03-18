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
                    'Das Dashboard zeigt aktive und geplante Tasks mit Echtzeit-Timer, Status-Badge und Prioritätsbalken. Play/Pause/Stopp direkt in der Karte bedienbar.',
              ),
              _Entry(
                title: 'Prioritätsbalken',
                body:
                    'Tasks mit erhöhter Priorität zeigen einen farbigen 4px-Balken links:\n'
                    '• Rot = Kritisch\n'
                    '• Orange = Hoch\n'
                    '• Blaugrau = Niedrig\n'
                    'Sichtbar in der Task-Liste und auf dem Dashboard.',
              ),
              _Entry(
                title: 'Schnell-Stoppuhr',
                body:
                    'Oben auf dem Dashboard befindet sich eine eigenständige Stoppuhr – unabhängig von Tasks.\n'
                    '• Start: Zähler läuft sofort\n'
                    '• Pause/Resume: erscheint sobald die Stoppuhr aktiv ist\n'
                    '• Stopp: fragt ob die gemessene Zeit als neuer Task gespeichert werden soll (mit optionalem Kunden)\n'
                    'Shortcut: Ctrl+Shift+Space (Start/Pause), Ctrl+Shift+Enter (Stopp)',
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
                    'Der Timer startet sofort ohne Dialog – direkt auf Play drücken.\n'
                    'AE (Arbeitseinheit) wird automatisch aus den Gesamtminuten berechnet: 1 AE = einstellbares Intervall (Standard 10 Min, aufrunden).\n'
                    'AE kopieren: In der Übersicht gibt es einen Button "AE kopieren" für die Zwischenablage.\n'
                    'Beim Stoppen erscheint ein Dialog: erledigte Todos abhaken + optionale Sitzungsnotiz.',
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
                    'Unterstützte Typen: PC, Laptop, Mac, MacBook, Monitor, Drucker, Router, Switch, Server, Telefon, Tablet, Sonstiges.\n'
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
                title: 'Notiz-Vorlagen',
                body:
                    'Notiz-Vorlagen sind wiederverwendbare Textbausteine mit vorausgefüllten Tags.\n\n'
                    'Verwaltung:\n'
                    '• Einstellungen → Datenpflege → Notiz-Vorlagen\n'
                    '• Oder: Notizen-Tab → Vorlagen-Symbol (oben rechts)\n\n'
                    'Vorlage anwenden:\n'
                    '1. Neue Notiz erstellen (+)\n'
                    '2. Vorlagen-Symbol in der AppBar tippen\n'
                    '3. Vorlage aus der Liste auswählen\n'
                    '4. Inhalt wird eingefügt, Tags werden automatisch gesetzt\n'
                    '5. Platzhalter [In Eckigen Klammern] ausfüllen\n'
                    '6. Speichern\n\n'
                    'Vorlagen können exportiert und mit Kollegen geteilt werden (Datenaustausch → Notiz-Vorlagen).',
              ),
              _Entry(
                title: 'Notiz-Vorlagen importieren (5 IT-Support Muster)',
                body:
                    '5 fertige Vorlagen für den IT-Alltag als JSON-Datei importieren:\n'
                    '1. Einstellungen → Datenaustausch → Datei importieren\n'
                    '2. Datei assets/note_templates_it_support.json auswählen\n\n'
                    'Enthaltene Vorlagen:\n'
                    '• Fernwartungs-Bericht – Datum, Techniker, Problem, Ursache, Maßnahmen, Ergebnis, Dauer\n'
                    '• Kundengespräch Protokoll – Teilnehmer, Themen, Beschlüsse, offene To-Dos\n'
                    '• Incident / Störungsbericht – Priorität, Betroffene Systeme, Rootcause, Eskalation\n'
                    '• Geräteübergabe Protokoll – Gerät, Seriennummer, Zubehör, Empfänger, Unterschrift\n'
                    '• Wartungsprotokoll – Checkliste mit Checkboxen, Befund, Nächster Termin\n\n'
                    'Platzhalter wie [Problem] oder [Datum] werden beim Anwenden als ausfüllbare Bereiche hervorgehoben.',
              ),
              _Entry(
                title: 'OS-Referenz-Notizen importieren',
                body:
                    'Fertige Nachschlagewerke für Windows, Linux und macOS als Notizen importieren:\n'
                    '1. Einstellungen → Datenaustausch → Datei importieren\n'
                    '2. Datei assets/notes_os_reference.json auswählen\n\n'
                    'Enthaltene Notizen (9):\n'
                    '• Windows: Tastenkürzel\n'
                    '• Windows: Terminal-Befehle (CMD & PowerShell)\n'
                    '• Windows: Typische Fehler & Lösungen\n'
                    '• Linux: Tastenkürzel (Desktop & Terminal)\n'
                    '• Linux: Terminal-Befehle (bash/zsh)\n'
                    '• Linux: Typische Fehler & Lösungen\n'
                    '• macOS: Tastenkürzel\n'
                    '• macOS: Terminal-Befehle (zsh)\n'
                    '• macOS: Typische Fehler & Lösungen\n\n'
                    'Die Notizen sind mit Tags versehen (z.B. "windows,shortcuts") und über die Tag-Suche filterbar.',
              ),
              _Entry(
                title: 'Workflow-Vorlagen importieren',
                body:
                    'Fertige IT-Support-Workflows können als JSON-Datei importiert werden:\n'
                    '1. Einstellungen → Datenaustausch → Datei importieren\n'
                    '2. Datei assets/workflows_it_support.json auswählen\n\n'
                    'Enthaltene Vorlagen (15 Workflows):\n'
                    '• Windows Neuinstallation\n'
                    '• Netzwerk-Diagnose & Fehlerbehebung\n'
                    '• Drucker einrichten\n'
                    '• E-Mail Einrichtung (Outlook / Thunderbird)\n'
                    '• Malware- / Virenbereinigung\n'
                    '• Neuer Mitarbeiter-PC einrichten\n'
                    '• VPN Einrichtung\n'
                    '• Hardware-Defekt Diagnose\n'
                    '• Microsoft 365 Einrichtung\n'
                    '• Passwort & Konto zurücksetzen\n'
                    '• Router / Firewall Konfiguration\n'
                    '• Server-Wartung (monatlich)\n'
                    '• Datenmigration / PC-Tausch\n'
                    '• Fernwartungssitzung\n'
                    '• Vor-Ort-Einsatz Abschluss\n\n'
                    'Bereits vorhandene Workflows (gleiche ID) werden beim Import übersprungen.',
              ),
              _Entry(
                title: 'Task-Vorlagen',
                body:
                    'Vollständige Task-Vorlagen mit vorausgefüllten Todos, Hardware-Bundles und Workflow-Zuweisung. Aus dem Dashboard (+ → Aus Vorlage) anwendbar.',
              ),
              _Entry(
                title: 'Backup & Wiederherstellung',
                body:
                    'Erstellt eine vollständige JSON-Sicherung aller Daten (Tasks, Kunden, Workflows, Einstellungen). Backup vor App-Updates oder Gerätewechsel empfohlen.\n'
                    '"Backup erstellen" öffnet einen Dialog: ohne Passwort exportieren oder mit Passwort verschlüsseln.\n'
                    '"Backup laden" importiert eine JSON-Datei. Bei verschlüsselten Backups wird automatisch nach dem Passwort gefragt.\n'
                    'Verschlüsselung: AES-256-CBC mit PBKDF2-HMAC-SHA256 (10.000 Iterationen). Dateiname enthält "_enc" als Kennung.',
              ),
              _Entry(
                title: 'Automatisches Backup',
                body:
                    'Aktivierbar in Einstellungen → Automatisches Backup.\n'
                    '• Läuft täglich automatisch beim App-Start\n'
                    '• Zielordner frei wählbar (Desktop/Android); auf iOS immer App-Dokumente-Ordner\n'
                    '• Backups älter als 7 Tage werden automatisch gelöscht\n'
                    '• Datum des letzten Backups wird in den Einstellungen angezeigt\n'
                    '• Automatische Backups sind nicht verschlüsselt (lokal gespeichert)',
              ),
              _Entry(
                title: 'App-Sperre (PIN)',
                body:
                    'Optional in Einstellungen → Sicherheit aktivierbar.\n'
                    '• 4–6-stelliger PIN wird beim App-Start und nach Hintergrundwechsel abgefragt\n'
                    '• Biometrie (Fingerabdruck / Face ID) als Schnellzugriff\n'
                    '• PIN vergessen? Recovery-Code (8 Zeichen) der beim Einrichten angezeigt wird\n'
                    '• Recovery-Code entsperrt die App und deaktiviert die Sperre – danach neuen PIN setzen\n'
                    '• PIN-Daten werden ausschließlich im sicheren Gerätespeicher gespeichert (Keychain/Keystore), nicht in der Datenbank',
              ),
              _Entry(
                title: 'Logo (macOS / iOS)',
                body:
                    'Das Firmen-Logo für PDF-Berichte kann auf allen Plattformen ausgewählt werden. Die Datei wird in den App-Dokumenten-Ordner kopiert und bleibt auch nach App-Updates erhalten.',
              ),
            ],
          ),
          _Section(
            icon: Icons.build_circle_outlined,
            title: 'Datenpflege',
            children: [
              _Entry(
                title: 'Datenbankpflege öffnen',
                body:
                    'Einstellungen → Datenpflege → Datenbankpflege.\n\n'
                    'Zeigt eine Übersicht über Datenbank- und Foto-Speicherverbrauch sowie Task-Statistiken.',
              ),
              _Entry(
                title: 'Tasks archivieren',
                body:
                    'Abgeschlossene Tasks werden aus der Hauptliste entfernt, aber vollständig erhalten (alle Notizen, Fotos, Zeiteinträge bleiben).\n\n'
                    'Filter: Tasks älter als 14 Tage / 1 Monat / 2 Monate / 3 Monate / 6 Monate.\n\n'
                    'Archivierte Tasks erscheinen nicht mehr in der Task-Liste und werden auch nicht im Badge-Zähler gezählt. In Monatsberichten sind sie weiterhin enthalten.',
              ),
              _Entry(
                title: 'Archiv verwalten',
                body:
                    'Im Datenbankpflege-Screen werden alle archivierten Tasks angezeigt.\n\n'
                    '• "Reaktivieren" → Task wird als COMPLETED in die Hauptliste zurückgeholt\n'
                    '• "Archiv leeren" → löscht alle archivierten Tasks dauerhaft inkl. Fotos, Notizen und Zeiteinträge (nicht rückgängig machbar)',
              ),
              _Entry(
                title: 'Fotos komprimieren',
                body:
                    'Reduziert die Dateigröße aller Task-Fotos auf dem Gerät. Originale werden in-place ersetzt (kein Rückgängig).\n\n'
                    'Qualität: 30–90 % (Standard: 70 %). Bilder größer als 1920 px werden proportional verkleinert.\n\n'
                    'Fotos werden nur ersetzt wenn die komprimierte Version tatsächlich kleiner ist.',
              ),
              _Entry(
                title: 'Verwaiste Dateien löschen',
                body:
                    'Findet Foto-Dateien auf dem Gerät, die keinen Datenbankeintrag mehr haben (z.B. nach manueller Löschung oder abgebrochenem Import).\n\n'
                    '"Löschen" entfernt diese Dateien und gibt Speicher frei.',
              ),
              _Entry(
                title: 'Datenbank VACUUM',
                body:
                    'SQLite-Befehl, der ungenutzte Seiten in der Datenbankdatei freigibt. Sinnvoll nach dem Archiv-Leeren oder vielen Löschvorgängen.\n\n'
                    'Zeigt Vorher-/Nachher-Größe an. Dauert bei großen Datenbanken einige Sekunden.',
              ),
            ],
          ),
          _Section(
            icon: Icons.widgets_outlined,
            title: 'Homescreen-Widget & Badge',
            children: [
              _Entry(
                title: 'App-Icon Badge (iOS / Android)',
                body:
                    'Das App-Icon zeigt automatisch die Anzahl offener Tasks als Badge-Zähler an.\n'
                    '• iOS: Zahl auf dem App-Icon (Springboard)\n'
                    '• Android: Zahl auf dem App-Icon (Launcher-abhängig)\n'
                    '• Läuft automatisch – keine Einrichtung nötig',
              ),
              _Entry(
                title: 'Homescreen-Widget (Android)',
                body:
                    'Widget zeigt: Aktiver Timer (läuft automatisch mit), Task-Name, Anzahl offener Tasks, Status (Läuft / Pausiert / Kein Timer).\n\n'
                    'Einrichten: Homescreen lang drücken → Widgets → PomTechFlow → Timer-Widget platzieren (Größe: 4×2 empfohlen).\n\n'
                    '"Öffnen"-Button im Widget → App öffnet sich auf dem Dashboard.',
              ),
              _Entry(
                title: 'Homescreen-Widget (iOS) – Einrichtung',
                body:
                    'Die Swift-Dateien liegen unter ios/PomTechFlowWidget/. Einmalig in Xcode nötig:\n'
                    '1. Xcode → ios/Runner.xcworkspace öffnen\n'
                    '2. File → New → Target → "Widget Extension" → Name: PomTechFlowWidget\n'
                    '3. Code aus ios/PomTechFlowWidget/PomTechFlowWidget.swift einfügen\n'
                    '4. App Groups Capability für Runner + Widget aktivieren: group.dev.fenron.pomtechflowMobile\n'
                    '5. flutter build ios\n\n'
                    'Details: ios/PomTechFlowWidget/SETUP.md\n\n'
                    'Tippen auf das Widget → App öffnet Dashboard. '
                    'Das Widget aktualisiert sich bei jedem Timer-Start/-Stopp automatisch.',
              ),
              _Entry(
                title: 'Widget-Einschränkungen',
                body:
                    '• "Timer ohne App öffnen starten" ist auf iOS platform-technisch nicht möglich (Apple-Einschränkung)\n'
                    '• Auf iOS aktualisiert sich das Widget sofort wenn die App im Vordergrund ist; im Hintergrund alle 30 Minuten\n'
                    '• macOS Dock-Badge: wird über app_badge_plus unterstützt, sofern Benachrichtigungs-Berechtigung erteilt',
              ),
            ],
          ),
          _Section(
            icon: Icons.keyboard_outlined,
            title: 'Tastenkürzel (Desktop)',
            children: [
              _Entry(
                title: 'Globale Shortcuts',
                body:
                    'Ctrl = Control auf Windows/Linux · ⌘ = Command auf macOS\n\n'
                    'Ctrl+N / ⌘N         → Neuer Task\n'
                    'Ctrl+T / ⌘T         → Task-Timer starten/pausieren\n'
                    'Ctrl+F / ⌘F         → Suche öffnen\n'
                    'Ctrl+, / ⌘,         → Einstellungen\n'
                    'Ctrl+1              → Dashboard\n'
                    'Ctrl+2              → Tasks\n'
                    'Ctrl+3              → Notizen',
              ),
              _Entry(
                title: 'Schnell-Stoppuhr Shortcuts',
                body:
                    'Ctrl+Shift+Space    → Start · Pause · Resume (Toggle)\n'
                    'Ctrl+Shift+Enter    → Stopp + Speicher-Dialog\n\n'
                    'Diese Shortcuts funktionieren von jedem Screen aus.',
              ),
              _Entry(
                title: 'Timer-Toggle (Ctrl+T)',
                body:
                    '• Läuft ein Timer → pausieren\n'
                    '• Timer pausiert → fortsetzen\n'
                    '• Kein Timer aktiv → Timer des ersten AKTIVEN Tasks starten',
              ),
              _Entry(
                title: 'Desktop-Menüleiste',
                body:
                    'Die Menüleiste (Datei / Ansicht) zeigt alle Shortcuts zur Referenz an. Sie ist nur auf Windows, Linux und macOS sichtbar.',
              ),
            ],
          ),
          _Section(
            icon: Icons.info_outline,
            title: 'Tipps',
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
                    'Auf Desktop-Plattformen wird eine Seitenleiste (NavigationRail) angezeigt. Bei breiten Fenstern (≥ 1200 px) erscheinen die Labels.\n'
                    'macOS: Datei-Picker und Ordner-Auswahl funktionieren dank Sandbox-Entitlements vollständig.',
              ),
              _Entry(
                title: 'iOS – Dateizugriff',
                body:
                    'Auf iOS können keine beliebigen Ordnerpfade gesetzt werden (Sandbox). Dateien werden im App-Dokumente-Ordner gespeichert, der über die iOS Dateien-App zugänglich ist.\n'
                    'Backups: täglich automatisch im Dokumente-Ordner/backups.',
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
