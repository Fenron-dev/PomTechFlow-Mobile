# iOS Widget Extension – Einmalige Xcode-Einrichtung

Die Swift-Dateien sind fertig. Diese **5 Schritte** in Xcode sind einmalig nötig
(Apple verlangt ein separates Extension-Target – das geht nicht per Flutter-CLI).

## Schritt 1 – Widget Extension hinzufügen

1. Xcode öffnen → `ios/Runner.xcworkspace`
2. **File → New → Target** → "Widget Extension" wählen
3. Name: **`PomTechFlowWidget`** (exakt so)
4. Bundle Identifier: `dev.fenron.pomtechflowMobile.PomTechFlowWidget`
5. "Include Configuration Intent" → **NEIN** (deaktivieren)
6. **Finish** → "Activate Scheme" mit **No** bestätigen

## Schritt 2 – Generierte Dateien ersetzen

Xcode hat Platzhalter-Dateien erstellt. Ersetze den Inhalt:
- `PomTechFlowWidget.swift` → Inhalt aus `ios/PomTechFlowWidget/PomTechFlowWidget.swift`
- `PomTechFlowWidgetBundle.swift` → Inhalt aus `ios/PomTechFlowWidget/PomTechFlowWidgetBundle.swift`

## Schritt 3 – App Group aktivieren

### Runner-Target:
1. Runner-Target → **Signing & Capabilities** → **+ Capability** → "App Groups"
2. Gruppe hinzufügen: **`group.dev.fenron.pomtechflowMobile`**

### PomTechFlowWidget-Target:
1. PomTechFlowWidget-Target → **Signing & Capabilities** → **+ Capability** → "App Groups"
2. Dieselbe Gruppe wählen: **`group.dev.fenron.pomtechflowMobile`**

## Schritt 4 – Minimum Deployment Target

PomTechFlowWidget-Target → General → Minimum Deployments → **iOS 16.0**

## Schritt 5 – Build testen

```
flutter build ios
```

Wenn der Build erfolgreich ist, erscheint das Widget in den Widget-Einstellungen
des iPhones unter "PomTechFlow Timer" (Small + Medium Größe verfügbar).

---

## Wie das Widget aktualisiert wird

- Die Flutter-App speichert Timer-Daten via `home_widget` in den geteilten App-Group-UserDefaults
- WidgetKit liest diese Daten beim nächsten Timeline-Update (max. alle 30 Min. automatisch,
  sofort wenn die Flutter-App `WidgetService.update()` aufruft)
- Beim Tippen auf das Widget öffnet die App das Dashboard

## Hinweis: Simulation im iOS Simulator

Homescreen-Widgets werden im Simulator manchmal nicht sofort angezeigt.
Nach dem ersten Start des Widgets in der App (Timer starten) sollte es erscheinen.
