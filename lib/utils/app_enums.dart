// ── Task Status ─────────────────────────────────────────────────────────────

abstract final class TaskStatus {
  static const planned   = 'PLANNED';
  static const active    = 'ACTIVE';
  static const paused    = 'PAUSED';
  static const completed = 'COMPLETED';

  /// Alle gültigen Werte (für Validierung).
  static const all = {planned, active, paused, completed};
}

// ── Task Priority ────────────────────────────────────────────────────────────

abstract final class TaskPriority {
  static const low      = 'LOW';
  static const normal   = 'NORMAL';
  static const high     = 'HIGH';
  static const critical = 'CRITICAL';

  static const all = {low, normal, high, critical};

  /// Numerischer Rang für Sortierung (höher = wichtiger).
  static int rank(String priority) => switch (priority) {
        critical => 3,
        high     => 2,
        normal   => 1,
        _        => 0,
      };
}

// ── Session Type ─────────────────────────────────────────────────────────────

abstract final class SessionType {
  static const work       = 'WORK';
  static const shortBreak = 'SHORT_BREAK';
  static const longBreak  = 'LONG_BREAK';

  static const all = {work, shortBreak, longBreak};
}

// ── Recurrence Type ──────────────────────────────────────────────────────────

abstract final class RecurrenceType {
  static const daily     = 'DAILY';
  static const weekly    = 'WEEKLY';
  static const monthly   = 'MONTHLY';
  static const quarterly = 'QUARTERLY';

  static const all = {daily, weekly, monthly, quarterly};
}

// ── Time Unit (Erinnerungs-Dialog) ───────────────────────────────────────────

abstract final class TimeUnit {
  static const minutes = 'MIN';
  static const hours   = 'HOUR';
  static const days    = 'DAY';
  static const weeks   = 'WEEK';

  /// Konvertiert einen Wert in der gegebenen Einheit nach Minuten.
  static int toMinutes(int value, String unit) => switch (unit) {
        hours => value * 60,
        days  => value * 1440,
        weeks => value * 10080,
        _     => value,
      };

  /// Menschenlesbare Bezeichnung für die Einheit (singular/plural).
  static String label(int value, String unit) => switch (unit) {
        hours => value == 1 ? 'Stunde'  : 'Stunden',
        days  => value == 1 ? 'Tag'     : 'Tage',
        weeks => value == 1 ? 'Woche'   : 'Wochen',
        _     => value == 1 ? 'Minute'  : 'Minuten',
      };
}

// ── Hardware Type ─────────────────────────────────────────────────────────────

abstract final class HardwareType {
  static const pc       = 'PC';
  static const laptop   = 'LAPTOP';
  static const mac      = 'MAC';
  static const macbook  = 'MACBOOK';
  static const monitor  = 'MONITOR';
  static const printer  = 'PRINTER';
  static const router   = 'ROUTER';
  static const switch_  = 'SWITCH';
  static const server   = 'SERVER';
  static const phone    = 'PHONE';
  static const tablet   = 'TABLET';
  static const other    = 'OTHER';

  static const all = [
    pc, laptop, mac, macbook, monitor, printer,
    router, switch_, server, phone, tablet, other,
  ];
}
