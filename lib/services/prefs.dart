import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class Prefs {
  Prefs._();
  static late SharedPreferences _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static bool get onboarded => _p.getBool('onboarded') ?? false;
  static set onboarded(bool v) => _p.setBool('onboarded', v);

  static bool get appLock => _p.getBool('app_lock') ?? false;
  static set appLock(bool v) => _p.setBool('app_lock', v);

  /// Minutes since midnight for each dose slot.
  static int slotMinutes(String slot) => _p.getInt('slot_$slot') ?? switch (slot) {
        'morning' => 8 * 60,
        'noon' => 14 * 60,
        _ => 21 * 60,
      };
  static void setSlotMinutes(String slot, int v) => _p.setInt('slot_$slot', v);

  static bool get remindersOn => _p.getBool('reminders') ?? true;
  static set remindersOn(bool v) => _p.setBool('reminders', v);

  static int? get lastBackupMs => _p.getInt('last_backup');
  static set lastBackupMs(int? v) => v == null ? _p.remove('last_backup') : _p.setInt('last_backup', v);

  static bool get driveLinked => _p.getBool('drive_linked') ?? false;
  static set driveLinked(bool v) => _p.setBool('drive_linked', v);

  static int? get currentMember => _p.getInt('current_member');
  static set currentMember(int? v) => v == null ? _p.remove('current_member') : _p.setInt('current_member', v);

  static UserRole? get cachedRole => switch (_p.getString('role')) {
        'owner' => UserRole.owner,
        'patient' => UserRole.patient,
        _ => null,
      };
  static set cachedRole(UserRole? v) =>
      v == null ? _p.remove('role') : _p.setString('role', v.name);

  static String? get apiToken => _p.getString('api_token');
  static set apiToken(String? v) => v == null ? _p.remove('api_token') : _p.setString('api_token', v);

  static String? get userEmail => _p.getString('user_email');
  static set userEmail(String? v) => v == null ? _p.remove('user_email') : _p.setString('user_email', v);
}
