import 'package:app_badge_plus/app_badge_plus.dart';

class BadgeService {
  static Future<void> update(int openTaskCount) async {
    try {
      if (!await AppBadgePlus.isSupported()) return;
      await AppBadgePlus.updateBadge(openTaskCount);
    } catch (_) {
      // Badge nicht unterstützt oder Berechtigung fehlt — still ignorieren
    }
  }
}
