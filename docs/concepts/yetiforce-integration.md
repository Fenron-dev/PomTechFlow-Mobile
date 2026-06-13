# Konzepterweiterung: YetiForce-CRM-Integration

> Status: **Entwurf / Planung** – noch nicht implementiert.
> Tracking-Issue: siehe „YetiForce-CRM-Integration" in den GitHub-Issues.

## 1. Ziel & Scope

Bidirektionaler Austausch zwischen **YetiForce CRM** (HelpDesk/Tickets) und
PomTechFlow:

- **Import:** Tickets, die dem aktuellen Benutzer zugewiesen sind, werden als
  **Tasks** in PomTechFlow übernommen. Task-Titel = Ticket-Betreff (**identisch**).
- **Export:** In PomTechFlow erfasste **Sessions** (Arbeitszeiten) werden als
  **Kommentar** in das zugehörige YetiForce-Ticket geschrieben.
- **Benutzer-Filter:** „Nur meine Tickets" – baut auf dem vorhandenen
  `assignedTo`-Feld + `ownTasksOnlyProvider`/`filterByTechnician`
  (`lib/providers/tasks_provider.dart`) auf.

Nicht im Scope (vorerst): Anlegen neuer Tickets aus PomTechFlow, Rechnungen,
sonstige YetiForce-Module.

## 2. Erreichbarkeit & Architektur

- YetiForce ist **öffentlich per HTTPS** erreichbar → das Mobilgerät spricht die
  REST-API **direkt** an (kein LAN-Bridge nötig, anders als der lokale Geräte-Sync).
- Neues Modul **`lib/integrations/yetiforce/`**, gespiegelt am bestehenden
  `lib/sync/`-Aufbau:
  - `yetiforce_api_client.dart` (HTTP, analog `lib/sync/client/sync_api_client.dart`)
  - `yetiforce_mapper.dart` (Ticket ↔ Task Feld-Mapping)
  - `yetiforce_service.dart` (Pull/Push-Ablauf)
  - `yetiforce_scheduler.dart` (Intervall/Trigger, analog `lib/sync/client/sync_scheduler.dart`)
  - `yetiforce_provider.dart` (Status/Config-Provider)

## 3. YetiForce-API (Voraussetzungen)

- Benötigt das **Web-Services-/REST-API-Modul** mit einem **API-Benutzer** + Schlüssel.
- **OFFEN / zu klären (Kollege fragen):** Ist das Modul aktiviert? Welche
  YetiForce-Version? Davon hängen Endpunkt-Pfade, Auth-Flow und Feld-IDs ab.
- Erwartete Endpunkte (zu verifizieren je Version):
  - Token-/Login-Handshake (App-Key + API-User).
  - Records je Modul abrufen / VQL-Query (`HelpDesk`/Tickets).
  - `ModComments` anlegen (Kommentar an Ticket).
  - Benutzerliste (für User-Mapping).
- Alle Aufrufe ausschließlich über HTTPS; Token-Lebensdauer beachten (Re-Auth).

## 4. Datenmodell-Mapping

| YetiForce (HelpDesk) | PomTechFlow (`Tasks`) |
|---|---|
| Ticket-ID (intern)   | `crmTicketId` (neu) |
| Ticket-Nr (sichtbar) | `crmTicketNo` (neu) |
| subject              | `title` (identisch halten) |
| status               | `status` (Status-Mapping-Tabelle) |
| assigned_user_id     | `assignedTo` (über User-Mapping) |
| account/organization | `Customer` (Match/Anlage) |
| description          | `description` |
| modifiedtime         | `crmModifiedAt` (neu, für Konflikt/Dedupe) |

**Schema-Erweiterungen (neue Migration vXX):**
- `Tasks`: `crmSource` (z. B. `'yetiforce'`), `crmTicketId`, `crmTicketNo`,
  `crmModifiedAt`.
- `Sessions`: `pushedToCrm` (bool) + `crmCommentId` – kennzeichnet, welche
  Sessions bereits als Kommentar geschrieben wurden (ermöglicht „erst prüfen").

Dedupe/Identität über `crmSource` + `crmTicketId`.

## 5. Sync-Strategie & Konflikte

- Pull per **Intervall + manuellem Trigger** (Muster aus `sync_scheduler.dart`).
- **Konfliktpolitik:** CRM ist **Quelle der Wahrheit** für Ticket-Metadaten
  (Betreff/Status/Zuweisung/Kunde). PomTechFlow besitzt die **Zeiten/Sessions**.
  Lokale Titeländerungen an CRM-Tasks werden beim nächsten Pull überschrieben
  (oder: Bearbeiten gesperrt – im Detail festzulegen).
- Offline: Pull/Push werden bei fehlender Verbindung übersprungen und beim
  nächsten erfolgreichen Lauf nachgeholt.

## 6. Sessions → Ticket-Kommentar

- **Einstellung:** „Sessions automatisch ins Ticket schreiben" **vs.**
  „erst prüfen/bestätigen". Grund: Eine Session kann zu spät gestartet/beendet
  worden sein und muss **vor** dem finalen Schreiben **korrigierbar** sein.
- Bei „erst prüfen": Liste offener (noch nicht gepushter) Sessions mit
  Bestätigen-Aktion; Sessions bleiben bis dahin editierbar.
- Kommentar-Format (Vorschlag): Datum, Dauer (Min/AE), Techniker, Vor-Ort/
  Fernwartung, Notiz.

## 7. Benutzer-Filter „meine Tickets"

- Mapping YetiForce-User → lokaler Techniker (eigene YetiForce-User-ID in den
  Settings hinterlegen).
- Import setzt `assignedTo` entsprechend; die bestehende Filterlogik
  (`ownTasksOnlyProvider`) zeigt dann standardmäßig nur eigene Tickets.

## 8. Benachrichtigungen

- Bei **neu zugewiesenen/erstellten** Tickets nach dem Pull eine **lokale
  Benachrichtigung** über den vorhandenen `NotificationService`
  (`flutter_local_notifications`).
- Echtes **Remote-Push** (FCM/APNs) als spätere Option – würde eine
  Server-/Webhook-Komponente erfordern und ist hier (Client-Pull-Architektur)
  zunächst nicht vorgesehen.

## 9. Konfiguration & Secrets

- Eigener Settings-Screen „YetiForce".
- Felder: Basis-URL, API-User/Key (in `flutter_secure_storage`, bereits genutzt),
  eigene YetiForce-User-ID, Auto-Push-Toggle, Sync-Intervall, Notify-Toggle.

## 10. Sicherheit/Datenschutz

- Nur HTTPS; Token/Key sicher im Keystore/Keychain; Zugriff auf eigene Tickets
  beschränken; keine Klartext-Credentials in der lokalen DB.

## 11. Phasen-Roadmap

- **Phase 1 – Import:** API-Client + Auth, Ticket-Pull (meine), Feld-Mapping,
  Schema-Erweiterung, „meine Tickets"-Filter, Settings-Screen.
- **Phase 2 – Export:** Sessions → Kommentar mit Auto/Manuell-Schalter und
  Editierbarkeit vor dem Push (`pushedToCrm`/`crmCommentId`).
- **Phase 3 – Ausbau:** Status-Rückschreibung, robuste Benachrichtigungen,
  Konfliktbehandlung verfeinern.

## 12. Offene Fragen / Risiken

- API-Modul aktiviert? Version? (→ Kollege)
- Konkrete Feld-IDs/Status-Werte im YetiForce-Setup.
- Rate-Limits / Token-Lebensdauer.
- Mehrmandanten / mehrere YetiForce-User pro Gerät?
- Verhalten bei lokal geänderten Titeln von CRM-Tasks (überschreiben vs. sperren).
