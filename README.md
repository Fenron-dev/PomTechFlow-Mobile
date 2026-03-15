# PomTechFlow Mobile

**IT-Support Pomodoro Zeiterfassung – Offline-First Mobile App für iOS & Android**

> Verwalte Tasks, tracke Arbeitszeit in Arbeitseinheiten (AE), erstelle Berichte und dokumentiere deinen IT-Support-Alltag – komplett lokal, ohne Internet, ohne Server.

---

## Inhaltsverzeichnis

- [Installation](#installation)
- [Erster Start](#erster-start)
- [Navigation](#navigation)
- [Dashboard](#dashboard)
- [Tasks](#tasks)
- [Timer](#timer)
- [Checkliste](#checkliste)
- [Hardware](#hardware)
- [Notizen](#notizen)
- [Fotos](#fotos)
- [PDF-Berichte](#pdf-berichte)
- [Suche](#suche)
- [Statistiken](#statistiken)
- [Einstellungen](#einstellungen)
- [Backup & Wiederherstellung](#backup--wiederherstellung)
- [FAQ](#faq)
- [Entwicklung & Build](#entwicklung--build)

---

## Installation

### Android (APK)

1. Den neuesten APK-Build von **GitHub Actions** herunterladen:
   - Repository → **Actions** → letzter erfolgreicher Workflow → **Artifacts** → `android-apk`
2. APK auf das Android-Gerät übertragen (USB, E-Mail, Cloud)
3. Auf dem Gerät unter **Einstellungen → Sicherheit → Unbekannte Quellen** aktivieren
4. APK antippen und installieren

> Mindestanforderung: Android 5.0 (API 21)

### iOS (TestFlight)

1. **Apple Developer Account** erforderlich ($99/Jahr)
2. `.ipa` aus GitHub Actions Artifacts in **App Store Connect** hochladen
3. Via **TestFlight** auf dem iPhone installieren

### iOS (direkt via Xcode, eigene Geräte kostenlos)

```bash
git clone https://github.com/Fenron-dev/PomTechFlow-Mobile.git
cd PomTechFlow-Mobile/pomtechflow_mobile
flutter pub get
open ios/Runner.xcworkspace
```
In Xcode: eigene Apple ID als Team → iPhone per USB verbinden → **Run**

---

## Erster Start

Beim ersten Start erscheint das **Dashboard** mit einem Willkommensbildschirm.

**Empfohlene Ersteinrichtung:**

1. **Einstellungen** öffnen (unterstes Icon in der NavBar)
2. **Firmenname** und **Techniker Name** eintragen
3. **Arbeitseinheiten (AE)** konfigurieren (Standard: 10 Min = 1 AE)
4. Optional: **Kunden** anlegen unter Einstellungen → Kunden
5. Optional: **Workflows** (Checklisten-Vorlagen) anlegen
6. Ersten Task erstellen über **Tasks → + (Plus-Button)**

---

## Navigation

Die App hat eine **4-Punkte Navigation** am unteren Rand:

| Icon | Bereich | Funktion |
|------|---------|----------|
| Dashboard | Startseite | Übersicht, Timer-Banner, heutige Tasks |
| Tasks | Aufgaben | Liste aller Tasks, Suche, neu erstellen |
| Einstellungen | Konfiguration | Firma, AE, Kunden, Workflows, Backup |
| Suche | Globale Suche | Tasks und Kunden durchsuchen |

---

## Dashboard

Das Dashboard zeigt auf einen Blick:

- **Timer-Banner** (oben) – wenn ein Timer läuft, mit aktuellem Countdown. Antippen öffnet den Task.
- **Statistik-Kacheln** – Gesamt-AE, aktive Tasks, abgeschlossene Tasks, AE-Konfiguration
- **Heute geplant** – Tasks mit einem Datum von heute, sortiert nach Uhrzeit
- **Aktive Tasks** – Tasks im Status "Aktiv" (max. 3, "Alle" zeigt komplette Liste)
- **Geplante Tasks** – Tasks im Status "Geplant" (max. 3)

**Aktionen im Dashboard:**
- **+ Icon** (AppBar rechts) – Neuen Task erstellen
- **Balken-Chart Icon** (AppBar rechts) – Statistiken öffnen
- **Pull-to-Refresh** – Daten aktualisieren

---

## Tasks

### Task-Liste

Alle Tasks sortiert nach letzter Änderung. Jede Karte zeigt:
- Titel und Kunde
- Fortschritt der Checkliste (x/y erledigt)
- Zeitaufwand in Minuten und AE
- Status-Badge (Geplant / Aktiv / Pausiert / Erledigt)
- **Play-Button** zum direkten Timer-Start
- **3-Punkte-Menü** für Bearbeiten und Löschen

**Suche:** Lupe-Icon in der AppBar aktiviert die Inline-Suche nach Titel oder Kunde.

### Neuen Task erstellen

Über das **+ FAB** (unten rechts) oder das + in der AppBar:

| Feld | Pflicht | Beschreibung |
|------|---------|--------------|
| Titel | Ja | Kurze Beschreibung des Auftrags |
| Beschreibung | Nein | Detaillierte Informationen |
| Kunde | Nein | Auswahl aus angelegten Kunden |
| Geplantes Datum | Nein | Datum + Uhrzeit, wird auf Dashboard angezeigt |

> Bei gesetztem Datum wird automatisch eine **Erinnerung** (lokale Notification) geplant.

### Task-Status

| Status | Bedeutung |
|--------|-----------|
| Geplant | Neu erstellt, noch nicht begonnen |
| Aktiv | Timer wurde mindestens einmal gestartet |
| Pausiert | Timer pausiert |
| Erledigt | Manuell als abgeschlossen markiert |

---

## Timer

Der Timer ist direkt in den **Task-Details (Übersicht-Tab)** integriert.

### Timer starten

1. Task öffnen → Übersicht-Tab
2. **"Timer starten"** antippen
3. **Start-Dialog** erscheint:
   - Offene Todos der Checkliste werden angezeigt
   - Erste 3 sind vorausgewählt (was wird in dieser Session erledigt?)
   - Bestätigen mit **"Starten"**

### Timer stoppen

1. **"Stoppen & speichern"** antippen
2. **Stop-Dialog** erscheint:
   - Erledigte Zeit wird angezeigt (z.B. "15 Minuten")
   - Todos zum Abhaken auswählen
   - Optional: **Schnellnotiz** hinterlassen
   - **"Speichern"** – Zeit wird zum Task addiert, Todos werden abgehakt

### Timer-Steuerung

| Button | Funktion |
|--------|----------|
| Play | Timer starten |
| Pause | Timer anhalten (Zeit läuft nicht) |
| Resume | Fortsetzen nach Pause |
| Stopp | Session beenden und speichern |
| Erledigt | Task als abgeschlossen markieren |

### AE-Berechnung

- **1 AE = konfigurierbare Minutenanzahl** (Standard: 10 Min)
- Berechnung: `ceil(Gesamtminuten / AE-Minuten)` → aufgerundet
- Beispiel bei 10 Min/AE: 3 Min = 1 AE, 11 Min = 2 AE, 30 Min = 3 AE

---

## Checkliste

Im **Checkliste-Tab** des Tasks:

- **Workflow-Gruppen** erscheinen als separate aufklappbare Karten mit Fortschrittsbalken
- Abgeschlossene Gruppen klappen automatisch zu
- **Ungruppiete Todos** erscheinen unter "Allgemein"
- Todos per **Tippen** abhaken/aufheben
- **+ Button** (FAB) fügt einzelne Todos hinzu
- **Workflow anwenden** (kleines FAB) öffnet Auswahl gespeicherter Workflows

### Workflows (Checklisten-Vorlagen)

Unter **Einstellungen → Workflows** können Vorlagen erstellt werden:
- Name + Beschreibung
- Beliebig viele Checklistenpunkte
- Optional: Zuweisung zu bestimmten Kunden
- Beim Anwenden auf einen Task werden alle Punkte als Gruppe hinzugefügt

---

## Hardware

Im **Hardware-Tab** des Tasks:

- Liste aller erfassten Geräte (Typ, Bezeichnung, Seriennummer, Notizen)
- **+ FAB** – Einzelnes Gerät hinzufügen
- **Bundle-FAB** (kleines Icon) – Geräte-Vorlage anwenden

### Gerätetypen

PC · Laptop · Monitor · Drucker · Router · Switch · Server · Telefon · Tablet · Sonstiges

### Hardware Bundles

Vordefinierte Gerätepakete unter **Einstellungen → Hardware Bundles**:
- Name + Beschreibung
- Mehrere Geräte mit Typ, Bezeichnung und Seriennummer
- Einmal erstellt, auf jeden Task anwendbar (z.B. "Standard-Arbeitsplatz")

---

## Notizen

Im **Notizen-Tab** des Tasks:

- Chronologische Liste aller Notizen mit Zeitstempel
- **+ FAB** – Neue Notiz schreiben
- **Long-Press** auf eine Notiz – Löschen

> Notizen aus dem Timer-Stop-Dialog werden hier ebenfalls gespeichert.

---

## Fotos

Im **Fotos-Tab** des Tasks:

- **3-Spalten Raster-Ansicht** aller Fotos
- **Kamera-FAB** – Foto direkt aufnehmen
- **Galerie-FAB** – Foto aus der Galerie wählen
- **Antippen** – Vollbild-Ansicht mit zoom (InteractiveViewer)
- **Long-Press** – Foto löschen (mit Bestätigungsdialog)

Fotos werden lokal im App-Datenordner gespeichert und sind nicht in der Galerie sichtbar.

---

## PDF-Berichte

Im **Übersicht-Tab** eines Tasks:

### Bericht erstellen

**"Bericht erstellen"** erzeugt ein professionelles PDF mit:
- Kopfzeile: Firmenname, Techniker, Datum
- Task-Details: Titel, Kunde, Status, Beschreibung
- Zeitübersicht: Minuten und AE
- Checkliste: Erledigte und offene Punkte (zweispaltig)
- Hardware-Tabelle: Typ, Bezeichnung, Seriennummer
- Notizen: Alle Notizen mit Zeitstempel
- Unterschriftsfelder: Techniker + Kunde
- Fußzeile: Firmenname + Seitenzahl

Nach der Generierung öffnet sich das **Teilen-Menü** (AirDrop, E-Mail, WhatsApp, etc.)

### Bericht-Verlauf

Bereits generierte Berichte erscheinen unterhalb des Buttons als Liste:
- Datum und Uhrzeit der Erstellung
- **Teilen-Button** zum erneuten Versenden

---

## Suche

Das **Suche-Icon** (4. Punkt in der NavBar) öffnet die globale Suche:

- Suche über **Task-Titel, Beschreibung und Kunde**
- Suche über **Kundennamen und E-Mail**
- Ergebnisse erscheinen sofort beim Tippen
- Antippen eines Tasks → direkt zum Task-Detail
- Antippen eines Kunden → zur Kunden-Verwaltung

---

## Statistiken

Erreichbar über das **Balken-Chart-Icon** im Dashboard (AppBar oben rechts):

- **Diese Woche**: AE, Minuten, abgeschlossene Tasks
- **Dieser Monat**: AE, Minuten, abgeschlossene Tasks
- **Alle Tasks**: Gesamtübersicht mit Statusbalken (Aktiv / Geplant / Erledigt)
- **Top Kunden**: Rangliste nach Zeitaufwand (AE und Minuten)

---

## Einstellungen

### Firma

| Feld | Beschreibung |
|------|--------------|
| Firmenname | Erscheint im Dashboard-Titel und im PDF-Header |
| Techniker Name | Erscheint im PDF-Bericht |

### Arbeitseinheiten (AE)

- **Minuten pro AE**: Wie viele Minuten eine Arbeitseinheit dauert (Standard: 10)
- Beeinflusst alle AE-Anzeigen in der App und im PDF

### Timer

| Einstellung | Standard | Bereich |
|-------------|---------|---------|
| Fokuszeit | 25 Min | 1–120 |
| Kurze Pause | 5 Min | 1–30 |
| Lange Pause | 15 Min | 1–60 |

### Darstellung

Drei Modi wählbar via Segmented Button:
- **System** – folgt der Geräte-Einstellung
- **Hell** – immer helles Theme
- **Dunkel** – immer dunkles Theme

### Stammdaten

- **Kunden** – Kunden anlegen, bearbeiten, löschen
- **Workflows** – Checklisten-Vorlagen verwalten
- **Hardware Bundles** – Geräte-Vorlagen verwalten

---

## Backup & Wiederherstellung

Unter **Einstellungen → Backup & Wiederherstellung**:

### Backup erstellen

**"Backup erstellen"** exportiert alle Daten als **JSON-Datei** über das Teilen-Menü:
- Kunden, Tasks, Sessions, Todos, Hardware, Notizen, Workflows, Einstellungen
- Fotos sind **nicht** im Backup enthalten (nur Metadaten)
- Dateiname: `pomtechflow_backup_<timestamp>.json`

### Backup laden

**"Backup laden"** importiert eine zuvor gespeicherte JSON-Datei:
1. Bestätigung erforderlich (alle aktuellen Daten werden überschrieben)
2. Datei auswählen
3. Alle Tabellen werden atomar wiederhergestellt

> **Wichtig:** Vor einem App-Update oder Neuinstallation immer ein Backup erstellen!

---

## Erinnerungen (Notifications)

- Wird beim Speichern eines Tasks mit **geplantem Datum** automatisch eine Erinnerung gesetzt
- Die Notification erscheint zum geplanten Zeitpunkt mit Titel des Tasks
- Beim Entfernen des Datums wird die Erinnerung automatisch abgebrochen
- Android 13+: Berechtigung wird beim ersten Start angefragt
- iOS: Berechtigung wird beim ersten Start angefragt

---

## FAQ

**Wo werden die Daten gespeichert?**
Ausschließlich lokal auf dem Gerät. Keine Cloud, kein Server, kein Internet benötigt.

**Was passiert bei einem App-Update?**
Die Datenbank bleibt erhalten. Vorsorglich trotzdem ein Backup erstellen.

**Kann ich die App auf mehreren Geräten nutzen?**
Ja, aber die Daten sind nicht synchronisiert. Ein Backup auf Gerät A kann auf Gerät B importiert werden.

**Wie viele AE hat ein 8-Stunden-Tag?**
Bei 10 Min/AE: 480 Min / 10 = 48 AE. Bei 6 Min/AE: 80 AE.

**Warum wird der Timer nicht exakt auf die Sekunde gestoppt?**
Der Timer ist ein Pomodoro-Timer – er zählt die konfigurierte Fokuszeit herunter. Die tatsächlich gearbeiteten Minuten werden beim Stoppen berechnet und gerundet.

**Kann ich Fotos aus dem Backup wiederherstellen?**
Nein – Fotos werden als Dateipfade gespeichert. Bei einer Neuinstallation sind die Dateipfade ungültig. Fotos vor dem Deinstallieren manuell sichern.

---

## Entwicklung & Build

### Voraussetzungen

- Flutter 3.41.4+
- Dart 3.11.1+
- Android SDK (für Android-Build)
- Xcode 15+ (für iOS-Build, nur macOS)

### Lokal ausführen

```bash
git clone https://github.com/Fenron-dev/PomTechFlow-Mobile.git
cd PomTechFlow-Mobile/pomtechflow_mobile

flutter pub get
flutter run
```

### Build

```bash
# Android APK
flutter build apk --release

# iOS (nur macOS)
flutter build ios --release
```

### Automatischer Build (GitHub Actions)

Bei jedem Push auf `master` wird automatisch gebaut:
- **Android APK** → downloadbar unter Actions → Artifacts → `android-apk`
- **iOS IPA** → downloadbar unter Actions → Artifacts → `ios-ipa`

### Datenbankschema erweitern

Die Datenbank wird mit **Drift** (SQLite ORM) verwaltet:

```bash
# Nach Schema-Änderungen in lib/db/database.dart
dart run build_runner build
```

Schema-Version in `database.dart` erhöhen und Migration in `MigrationStrategy.onUpgrade` ergänzen.

### Tech-Stack

| Technologie | Zweck |
|-------------|-------|
| Flutter 3.41.4 | UI Framework |
| Dart 3.11.1 | Programmiersprache |
| Drift 2.20 | SQLite ORM |
| flutter_riverpod | State Management |
| go_router | Navigation |
| pdf + printing | PDF-Generierung |
| flutter_local_notifications | Erinnerungen |
| image_picker | Kamera / Galerie |
| share_plus | Teilen / Export |
| file_picker | Backup Import |

---

## Lizenz

Privates Projekt – alle Rechte vorbehalten.

---

*PomTechFlow Mobile – entwickelt mit Flutter & Claude Code*
