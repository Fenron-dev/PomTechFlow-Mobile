# PomTechFlow Mobile

**IT-Support Pomodoro Zeiterfassung – Offline-First App für Android, iOS, Windows, macOS & Linux**

> Verwalte Tasks, tracke Arbeitszeit in Arbeitseinheiten (AE), erstelle Berichte und dokumentiere deinen IT-Support-Alltag – komplett lokal, ohne Internet, ohne Server.

---

## Inhaltsverzeichnis

- [Installation](#installation)
- [Erster Start](#erster-start)
- [Navigation](#navigation)
- [Dashboard](#dashboard)
- [Tasks](#tasks)
- [Prioritäten](#prioritäten)
- [Zeitbudget & Abrechnung](#zeitbudget--abrechnung)
- [Timer & Sessions](#timer--sessions)
- [Checkliste](#checkliste)
- [Hardware](#hardware)
- [Notizen](#notizen)
- [Fotos](#fotos)
- [Task-Verknüpfungen](#task-verknüpfungen)
- [PDF-Berichte & Vorschau](#pdf-berichte--vorschau)
- [Monats-Abschluss-Report](#monats-abschluss-report)
- [Task-Übergabe (.ptf)](#task-übergabe-ptf)
- [Übergabepaket (ZIP)](#übergabepaket-zip)
- [Wiederkehrende Tasks](#wiederkehrende-tasks)
- [Task-Vorlagen](#task-vorlagen)
- [Geräte-Bibliothek](#geräte-bibliothek)
- [Kunden & Kontakt](#kunden--kontakt)
- [Suche](#suche)
- [Statistiken & CSV-Export](#statistiken--csv-export)
- [Einstellungen](#einstellungen)
- [Backup & Wiederherstellung](#backup--wiederherstellung)
- [Desktop-Besonderheiten](#desktop-besonderheiten)
- [FAQ](#faq)
- [Entwicklung & Build](#entwicklung--build)

---

## Installation

### Android (APK)

1. Neuesten APK-Build von **GitHub Actions** herunterladen:
   - Repository → **Actions** → letzter erfolgreicher Workflow → **Artifacts** → `PomTechFlow-Android`
2. APK auf das Android-Gerät übertragen (USB, E-Mail, Cloud)
3. Unter **Einstellungen → Sicherheit → Unbekannte Quellen** aktivieren
4. APK antippen und installieren

> Mindestanforderung: Android 5.0 (API 21)

### iOS

```bash
git clone https://github.com/Fenron-dev/PomTechFlow-Mobile.git
cd PomTechFlow-Mobile/pomtechflow_mobile
flutter pub get
open ios/Runner.xcworkspace
```
In Xcode: eigene Apple ID als Team setzen → iPhone per USB verbinden → **Run**

### Windows / Linux / macOS

Builds sind als Artifacts in GitHub Actions verfügbar:
- **Windows**: `PomTechFlow-Windows.zip` → entpacken → `pomtechflow_mobile.exe` starten
- **Linux**: `PomTechFlow-Linux.tar.gz` → entpacken → `pomtechflow_mobile` starten
- **macOS**: `PomTechFlow-macOS.zip` → entpacken → App ins Programme-Ordner ziehen

---

## Erster Start

**Empfohlene Ersteinrichtung:**

1. **Einstellungen** öffnen
2. **Firmenname** und **Techniker Name** eintragen
3. **Firmen-Logo** hochladen (PNG/JPG, erscheint oben links im PDF-Bericht)
4. **Arbeitseinheiten (AE)** konfigurieren (Standard: 10 Min = 1 AE)
5. Optional: **Abrechnungs-E-Mail (intern)** eintragen (für interne Abrechnungsentwürfe)
6. Optional: **Kunden** anlegen → Einstellungen → Kunden
7. Optional: **Workflows** (Checklisten-Vorlagen) anlegen
8. Ersten Task erstellen über **Tasks → + (Plus-Button)**

---

## Navigation

| Icon | Bereich | Funktion |
|------|---------|----------|
| Dashboard | Startseite | Übersicht, Timer-Banner, heutige Tasks |
| Tasks | Aufgaben | Liste aller Tasks, Suche, Filter, Sortierung |
| Einstellungen | Konfiguration | Firma, Logo, AE, Kunden, Workflows, Backup |
| Suche | Globale Suche | Tasks und Kunden durchsuchen |

**Desktop (ab 840px Breite):** NavigationRail links statt Bottom Navigation. Ab 1200px mit beschrifteten Menüpunkten. Zusätzlich: Menüleiste oben (Datei / Ansicht).

**Tablet (ab 700px):** Task-Liste und Task-Detail nebeneinander (Master-Detail Layout).

---

## Dashboard

- **Schnellnotiz (Scratchpad)** – aufklappbare Notizfläche ganz oben; Text wird per Debounce (500 ms) automatisch gespeichert und bleibt nach App-Neustart erhalten. Klappt automatisch auf, wenn Text vorhanden ist.
- **Timer-Banner** – läuft ein Timer, erscheint er hier mit Countdown. Antippen öffnet den Task.
- **Statistik-Kacheln** – Gesamt-AE, aktive Tasks, abgeschlossene Tasks, AE-Konfiguration
  *(auf Desktop: 4 Spalten nebeneinander)*
- **Heute geplant** – Tasks mit heutigem Datum, sortiert nach Uhrzeit
- **Aktive Tasks** – max. 3 aktive Tasks (mit "Alle"-Link)
- **Geplante Tasks** – max. 3 geplante Tasks

**AppBar-Aktionen:**
- **PDF-Icon** → Alle gespeicherten Berichte anzeigen (mit In-App-Vorschau)
- **Balken-Chart** → Statistiken
- **+** → Neuer Task

---

## Tasks

### Task-Liste

Jede Karte zeigt:
- **Farbiger linker Balken** – Prioritäts-Indikator (rot = Kritisch, orange = Hoch, grau = Niedrig, kein = Normal)
- Titel, Kunde, Checklisten-Fortschritt
- Zeit in Minuten und AE, Status-Badge
- **Wiederholungs-Icon** bei wiederkehrenden Tasks
- **Warn-Icon** (orange) wenn die Zeit das eingestellte Zeitbudget überschreitet

**Suchen:** Lupe-Icon in der AppBar
**Sortieren & Filtern:** Sortier-Icon in der AppBar öffnet Popup:

| Option | Beschreibung |
|--------|-------------|
| Priorität (hoch→niedrig) | Kritisch zuerst |
| Datum (neu→alt) | Zuletzt geändert zuerst (Standard) |
| Datum (alt→neu) | Älteste zuerst |
| Titel (A–Z) | Alphabetisch |
| — Priorität filtern — | Nur Tasks einer bestimmten Priorität anzeigen |

**Task importieren:** Download-Icon in der AppBar → `.ptf`-Datei auswählen
**Aus Vorlage:** Beim leeren Zustand über den "Aus Vorlage"-Button

### Task erstellen / bearbeiten

| Feld | Beschreibung |
|------|-------------|
| Titel | Kurze Beschreibung (Pflichtfeld) |
| Beschreibung | Detaillierte Informationen |
| Kunde | Auswahl aus angelegten Kunden |
| **Priorität** | Niedrig / Normal / Hoch / Kritisch |
| Geplantes Datum | Datum + Uhrzeit, löst Erinnerung aus |
| **Zeitbudget (Min)** | Optionales Zeitbudget in Minuten; löst Warnsymbol aus wenn überschritten |
| Wiederkehrend | Täglich / Wöchentlich / Monatlich / Vierteljährlich |

---

## Prioritäten

Vier Stufen:

| Stufe | Farbe | Wann nutzen |
|-------|-------|-------------|
| **Niedrig** | Grau | Kann warten |
| **Normal** | (kein Balken) | Standardaufgabe |
| **Hoch** | Orange | Zeitkritisch |
| **Kritisch** | Rot | Sofort erledigen |

Priorität wird im Task-Formular gesetzt und ist in der Task-Karte als farbiger Balken sichtbar. Sortierung nach Priorität bringt Kritisch/Hoch zuerst.

---

## Zeitbudget & Abrechnung

### Zeitbudget

Im Task-Formular kann optional ein **Zeitbudget in Minuten** hinterlegt werden:

- **Warn-Icon** (orange) in der Task-Karte wenn `Gesamtzeit > Budget`
- Im **Übersicht-Tab** zeigt ein `LinearProgressIndicator` den Budgetverbrauch (orange/rot bei Überschreitung)
- Beim E-Mail-Entwurf und im Monats-Report wird eine Budgetwarnung (`⚠ überschritten`) angezeigt

### AE kopieren

Im **Übersicht-Tab** → **"AE kopieren"**-Button:
- Kopiert `Task: [Titel] | Zeit: X Min | AE: Y` in die Zwischenablage
- Inkl. Budgetwarnung wenn Budget gesetzt und überschritten
- SnackBar-Bestätigung erscheint kurz

### Abrechnungsstatus

Im **Übersicht-Tab** → **"Als abgerechnet"**-Toggle:
- Setzt den Abrechnungszeitstempel (`billedAt`) auf den aktuellen Zeitpunkt
- Erneutes Antippen setzt den Status zurück (auf "Noch nicht abgerechnet")
- Datum der Abrechnung wird im E-Mail-Entwurf und im Monats-Report angezeigt
- Abgerechnete Tasks erscheinen im Monats-Report mit Quittungs-Icon

### Interner Abrechnungsentwurf (E-Mail)

Im **Übersicht-Tab** → **Mail-Icon**-Button (neben PDF):
- Öffnet den nativen E-Mail-Client mit vorausgefülltem Entwurf
- **Empfänger:** Abrechnungs-E-Mail aus den Einstellungen (kein Kunden-Versand)
- **Betreff:** `Abrechnung: [Task] – [Kunde]`
- **Body:** Auftrag, Kunde, Zeitaufwand, AE, Budget-Status, Techniker, Firma, Abrechnungsstatus
- Kein eigenes E-Mail-Package – nutzt `mailto:` URI via `url_launcher`

> Die Abrechnungs-E-Mail wird unter **Einstellungen → Firma → "Abrechnungs-E-Mail (intern)"** eingetragen.

---

## Timer & Sessions

### Timer starten

Task öffnen → Übersicht-Tab → **"Timer starten"**
Ein Dialog zeigt offene Todos – Auswahl, was in dieser Session erledigt wird.

### Timer stoppen

**"Stoppen & speichern"** → Dialog mit genauen Minuten, Todos abhaken, optionale Schnellnotiz.

### Sessions manuell bearbeiten

Im **Übersicht-Tab** unterhalb der Statistiken → **Sessions-Bereich**:

- Alle Sessions mit **Datum, Startzeit, Endzeit, Dauer, Typ und Notiz**
- **Stift-Icon** zum Bearbeiten (Datum/Uhrzeit per Picker, Notiz, Typ)
- **Löschen** mit Bestätigungsdialog
- **"+ Hinzufügen"** zum manuellen Erfassen vergessener Zeiten
- Änderungen aktualisieren automatisch die Gesamtminuten des Tasks

### AE-Berechnung

`ceil(Gesamtminuten / AE-Minuten)` → aufgerundet
Beispiel bei 10 Min/AE: 3 Min = 1 AE · 11 Min = 2 AE · 30 Min = 3 AE

---

## Checkliste

- **Ungrupierte Todos** – unter "Allgemein" mit **Drag & Drop** Sortierung (☰ Handle)
- **Workflow-Gruppen** – aufklappbare Karten mit Fortschrittsbalken; schließen automatisch wenn fertig
- **+ Button** – einzelnen Checklistenpunkt hinzufügen
- **Workflow anwenden** – gespeicherte Workflow-Vorlage auf Task anwenden

### Workflows (Checklisten-Vorlagen)

Einstellungen → Workflows:
- Name + Beschreibung
- Beliebig viele Checklistenpunkte mit definierter Reihenfolge
- Beim Anwenden werden alle Punkte als benannte Gruppe eingefügt

---

## Hardware

- Liste aller erfassten Geräte (Typ, Bezeichnung, Seriennummer, Notizen)
- **+ FAB** – Einzelnes Gerät hinzufügen
- **Bundle-FAB** – Geräte-Bundle (Vorlage) anwenden
- **Bibliothek-FAB** – Gerät aus der Geräte-Bibliothek wählen

### Gerätetypen

PC · Laptop · Monitor · Drucker · Router · Switch · Server · Telefon · Tablet · Sonstiges

### Hardware Bundles

Einstellungen → Hardware Bundles: Vordefinierte Gerätepakete (z.B. "Standard-Arbeitsplatz")

### Geräte-Bibliothek

Einstellungen → Geräte-Bibliothek: Individuelle Einzelgeräte mit Seriennummer vorhalten und schnell zuweisen.

---

## Notizen

- Chronologische Liste mit Zeitstempel
- **+ FAB** – Neue Notiz
- **Long-Press** – Löschen
- Notizen aus Timer-Stop-Dialog werden hier ebenfalls gespeichert

### Fernwartungs-Vorlage

Computer-Icon neben dem Senden-Button:
- Öffnet einen Eingabe-Bogen mit 4 Feldern: **Problem / Ursache / Lösung / Ergebnis**
- "Einfügen"-Button speichert die Eingaben als formatierte Notiz:
  ```
  [Fernwartung]
  Problem: ...
  Ursache: ...
  Lösung: ...
  Ergebnis: ...
  ```
- Ideal für schnelle strukturierte Dokumentation nach Remote-Support-Einsätzen

---

## Fotos

- 3-Spalten Raster-Ansicht
- **Kamera-FAB** – direkt aufnehmen
- **Galerie-FAB** – aus Galerie wählen
- **Antippen** – Vollbild mit Zoom (pinch-to-zoom, zoombares Bild)
- **Long-Press** – Kontextmenü mit zwei Optionen:
  - **Beschriftung bearbeiten** – Dialog mit TextField; Text erscheint als halbtransparentes Overlay am unteren Rand des Kachel-Bilds
  - **Foto löschen** – löscht Datenbankeinträg und Bilddatei
- Im **Vollbild-Viewer**: Stift-Icon in der AppBar zum Bearbeiten der Beschriftung; Caption erscheint als Textblock unterhalb des Bilds

---

## Task-Verknüpfungen

Im **Übersicht-Tab** ganz unten → **"Verknüpfte Tasks"**-Sektion:

- Zeigt alle verknüpften Tasks gruppiert nach Beziehungstyp
- **"Verknüpfung hinzufügen"**-Button öffnet ein Bottom Sheet:
  - **Suche** – Tasks nach Titel filtern
  - **Beziehungstyp** (SegmentedButton):
    | Typ | Bedeutung |
    |-----|-----------|
    | **Verwandt** | Inhaltlich zusammenhängende Tasks |
    | **Blockiert** | Dieser Task blockiert den verknüpften Task |
    | **Folge-Task** | Der verknüpfte Task ist Nachfolgeaufgabe |
- Antippen eines verknüpften Tasks → direkt zum Task-Detail
- Verknüpfungen können einzeln entfernt werden (Löschen-Icon)

---

## PDF-Berichte & Vorschau

### Bericht erstellen

Task → Übersicht-Tab → **"PDF"**:
- Kopfzeile: **Firmen-Logo** (oben links), Firmenname, Techniker, Datum
- Task-Details: Titel, Kunde, Status, Beschreibung, Priorität
- Zeitübersicht: Minuten + AE
- Checkliste (zweispaltig)
- Hardware-Tabelle
- Notizen mit Zeitstempel
- Unterschriftsfelder

Logo einrichten: **Einstellungen → Firma → "Firmen-Logo (PDF-Berichte)" → "Auswählen"**

### Alle Berichte anzeigen

**Dashboard → PDF-Icon** (AppBar oben rechts) → Liste aller generierten PDFs mit:
- Datum/Uhrzeit der Erstellung
- **Antippen** → **In-App-Vorschau** (scrollbar, zoombar, druckbar)
- **Teilen-Button** zum erneuten Versenden

---

## Monats-Abschluss-Report

**Alle Berichte → Kalender-Icon** (AppBar oben rechts) → `/reports/monthly`:

### Bedienung

1. **Monat auswählen** – Pfeiltasten (← MMMM yyyy →)
2. **Kunde auswählen** – Dropdown (inkl. "Alle Kunden")
3. Vorschau zeigt sofort:
   - Zusammenfassungs-Chips: Anzahl Tasks / Gesamt-Minuten / Gesamt-AE
   - Task-Liste mit Titel, Minuten, AE, Status
   - Abgerechnete Tasks mit Quittungs-Icon und dezenter Hintergrundfarbe

### PDF erstellen

- **"PDF erstellen"**-Button generiert die Übersichtstabelle:
  - Kopfzeile: Firmen-Logo, Firma, Techniker, Monat, Kundenfilter
  - Tabelle: Titel · Kunde · Status · Minuten · AE
  - Gesamt-Zeile am Ende
  - Unterschriftsfelder
- **Teilen-Dialog** öffnet sich automatisch
- **Dateiname:** `YYYY-MM_monatsabschluss_<kundenName>.pdf`

### Als abgerechnet markieren

- Checkbox **"Alle als abgerechnet markieren"** setzt `billedAt` auf alle gefilterten Tasks beim PDF-Erstellen
- Bereits abgerechnete Tasks werden im Report deutlich gekennzeichnet

> **Hinweis:** Die Filterung basiert auf `Geplantes Datum` des Tasks, Fallback auf `Erstellt am`.

---

## Task-Übergabe (.ptf)

Einen kompletten Task inklusive aller Daten an einen Kollegen übergeben:

### Exportieren

Task → Übersicht-Tab → **AppBar → Teilen-Icon (↑)**:
- Erstellt eine `.ptf`-Datei (PomTechFlow Task)
- Versenden per Mail, WhatsApp, AirDrop, etc.

**Enthaltene Daten:**

| Bereich | Inhalt |
|---------|--------|
| Task | Titel, Beschreibung, Status, Priorität, Datum |
| Kunde | Name, Telefon, E-Mail, Adresse |
| Checkliste | Alle Todos mit Erledigungsstatus |
| Hardware | Typ, Bezeichnung, Seriennummer, Notizen |
| Notizen | Alle Notizen mit Zeitstempel |
| Sessions | Alle Zeiteinträge mit Notizen |
| Fotos | Alle Fotos als Base64 eingebettet |

### Importieren

Task-Liste → **Download-Icon** (AppBar) → `.ptf`-Datei auswählen:
- Neuer Task wird angelegt (`[Übergabe]` Prefix)
- Kunde wird gesucht oder neu angelegt
- Alle Daten werden wiederhergestellt

---

## Übergabepaket (ZIP)

Task → Übersicht-Tab → **"ZIP Paket"**:
- Generiert zuerst den PDF-Bericht
- Packt PDF + alle Fotos in eine ZIP-Datei
- Teilen-Dialog öffnet sich automatisch

Ideal für vollständige Dokumentation an Endkunden.

---

## Wiederkehrende Tasks

Beim Erstellen/Bearbeiten eines Tasks:
- **"Wiederkehrender Task"** aktivieren
- Intervall: Täglich / Wöchentlich / Monatlich / Vierteljährlich
- Häufigkeit: Alle N Einheiten

Wenn der Task als **"Erledigt"** markiert wird, erstellt die App automatisch einen neuen Task mit dem nächsten Fälligkeitsdatum.

---

## Task-Vorlagen

Unter **Einstellungen → Task-Vorlagen**:
- Komplette Task-Vorlage speichern: Titel, Beschreibung, Kunde, Workflow, Hardware-Bundle
- Bei der Task-Erstellung über **"Aus Vorlage"**: Vorlage auswählen → Task mit vorbefüllter Checkliste und Hardware wird angelegt

---

## Geräte-Bibliothek

Unter **Einstellungen → Geräte-Bibliothek**:
- Individuelle Geräte mit Seriennummer, Typ und Notizen vorhalten
- Suchbar und nach Typ filterbar
- Im Hardware-Tab eines Tasks über den Bibliotheks-Button direkt zuweisen

---

## Kunden & Kontakt

Unter **Einstellungen → Kunden**:
- Name, E-Mail, Telefon, Adresse, Notizen
- **Aktions-Chips** in der Kunden-Karte:
  - 📞 Telefon antippen → Direktanruf
  - ✉️ E-Mail antippen → Mail-App öffnen
  - 🗺 Navigation antippen → Google Maps öffnen

Im **Übersicht-Tab** eines Tasks werden dieselben Aktions-Chips unter dem Kunden-Namen angezeigt.

---

## Suche

Globale Suche (4. NavBar-Punkt):
- Task-Titel, Beschreibung und Kundenname
- Kundennamen und E-Mail
- Tippen → Sofortergebnisse
- Antippen → direkt zum Detail

---

## Statistiken & CSV-Export

**Dashboard → Balken-Chart-Icon:**

- **Diese Woche** / **Dieser Monat** / **Gesamt**: AE, Minuten, Tasks
- **Top Kunden**: Rangliste nach AE und Minuten
- **Statusbalken**: Verteilung Aktiv / Geplant / Erledigt

**CSV-Export:** AppBar → Tabellen-Icon → Monatsbericht als CSV-Datei:
- Datum, Kunde, Titel, Status, Minuten, AE, Sessions, Erstellt, Abgeschlossen
- Semikolon-getrennt, UTF-8 BOM für Excel-Kompatibilität

---

## Einstellungen

### Firma

| Feld | Beschreibung |
|------|-------------|
| Firmenname | Erscheint im Dashboard-Titel und im PDF-Header |
| Techniker Name | Erscheint im PDF-Bericht |
| **Firmen-Logo** | PNG/JPG, erscheint oben links im PDF-Bericht |
| **Abrechnungs-E-Mail (intern)** | Empfänger für interne Abrechnungsentwürfe; kein Kunden-Versand |

### Arbeitseinheiten (AE)

Minuten pro AE konfigurierbar (Standard: 10). Beeinflusst alle AE-Anzeigen und den PDF-Bericht.

### Timer

| Einstellung | Standard |
|-------------|---------|
| Fokuszeit | 25 Min |
| Kurze Pause | 5 Min |
| Lange Pause | 15 Min |

### Darstellung

System / Hell / Dunkel

### Stammdaten

- **Kunden** – Kunden mit Kontaktdaten verwalten
- **Workflows** – Checklisten-Vorlagen
- **Task-Vorlagen** – Komplette Tasks als Vorlage
- **Geräte-Bibliothek** – Individuelle Einzelgeräte
- **Hardware Bundles** – Geräte-Pakete als Vorlage
- **Datenaustausch** – Kunden/Workflows/Bundles exportieren & importieren

---

## Backup & Wiederherstellung

**Backup erstellen:** Einstellungen → Backup & Wiederherstellung → alle Daten als JSON exportieren
**Backup laden:** JSON-Datei importieren (bestehende Daten werden überschrieben)

> Fotos sind nicht im Backup enthalten. Vor App-Deinstallation manuell sichern.

---

## Desktop-Besonderheiten

### Menüleiste (Windows / Linux / macOS)

Am oberen Rand erscheint eine Menüleiste:

| Menü | Einträge |
|------|---------|
| **Datei** | Neuer Task, Task importieren, Statistiken, Alle Berichte |
| **Ansicht** | Dashboard, Tasks, Suche, Einstellungen |

### Master-Detail Layout (Tablet / Desktop)

Ab 700px Breite: Task-Liste links (360px) + Task-Detail rechts nebeneinander.
Beim Antippen eines Tasks wird das Detail direkt rechts angezeigt, kein Navigationssprung.

### App-Icon Badge

Die Anzahl offener Tasks (Status: Geplant oder Aktiv) wird als Badge auf dem App-Icon angezeigt.

> iOS/macOS: Badge-Berechtigung wird beim ersten Start beantragt.
> Android: Funktioniert je nach Launcher.

---

## FAQ

**Wo werden die Daten gespeichert?**
Ausschließlich lokal auf dem Gerät. Keine Cloud, kein Server, kein Internet benötigt.

**Kann ich Zeiten nachträglich korrigieren?**
Ja: Task → Übersicht-Tab → Sessions → Stift-Icon. Datum, Uhrzeit und Dauer können per Picker bearbeitet werden.

**Wie übergebe ich einen Task an einen Kollegen?**
Task öffnen → AppBar → Teilen-Icon → `.ptf`-Datei per Mail/Chat senden. Kollege importiert über Task-Liste → Download-Icon.

**Was ist der Unterschied zwischen Task-Übergabe (.ptf) und ZIP-Paket?**
- `.ptf` ist für Kollegen: komplette Daten inkl. Fotos, importierbar in PomTechFlow
- ZIP-Paket ist für Kunden/Dokumentation: PDF-Bericht + Fotos als Archiv

**Was passiert bei einem App-Update?**
Die Datenbank wird automatisch migriert. Trotzdem vorher ein Backup erstellen.

**Wie viele AE hat ein 8-Stunden-Tag?**
Bei 10 Min/AE: 480 ÷ 10 = 48 AE.

---

## Entwicklung & Build

### Voraussetzungen

- Flutter 3.41.4+
- Dart 3.11.1+

### Lokal ausführen

```bash
git clone https://github.com/Fenron-dev/PomTechFlow-Mobile.git
cd PomTechFlow-Mobile/pomtechflow_mobile

flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

### Datenbankschema erweitern

Nach Änderungen in `lib/db/database.dart`:
1. Schema-Version erhöhen (`schemaVersion`)
2. Migration in `MigrationStrategy.onUpgrade` ergänzen
3. `dart run build_runner build --delete-conflicting-outputs`

Aktuelle Version: **v9**

### Automatischer Build (GitHub Actions)

Bei jedem Push auf `master` werden alle Plattformen gebaut:

| Artifact | Plattform |
|----------|-----------|
| `PomTechFlow-Android` | Android APK |
| `PomTechFlow-iOS` | iOS IPA |
| `PomTechFlow-Windows` | Windows ZIP |
| `PomTechFlow-macOS` | macOS ZIP |
| `PomTechFlow-Linux` | Linux TAR.GZ |

### Tech-Stack

| Technologie | Zweck |
|-------------|-------|
| Flutter 3.41.4 | UI Framework (alle Plattformen) |
| Dart 3.11.1 | Programmiersprache |
| Drift 2.20 | SQLite ORM, Schema-Migration |
| flutter_riverpod | State Management |
| go_router | Navigation / Routing |
| pdf + printing | PDF-Generierung + In-App-Vorschau |
| flutter_local_notifications | Erinnerungen |
| image_picker | Kamera / Galerie |
| share_plus | Teilen / Export |
| file_picker | Dateiauswahl (Import) |
| url_launcher | Direktanruf, E-Mail, Maps |
| archive | ZIP-Übergabepaket |
| app_badge_plus | App-Icon Badge |

---

## Lizenz

Privates Projekt – alle Rechte vorbehalten.

---

*PomTechFlow Mobile – entwickelt mit Flutter & Claude Code*
