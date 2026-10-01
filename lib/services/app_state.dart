import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../data/local_db.dart';
import '../data/models.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'prefs.dart';

enum Stage { loading, onboarding, login, pickRole, patientSetup, ownerSetup, patient, owner }

class AppState extends ChangeNotifier {
  Stage stage = Stage.loading;
  UserRole? role;
  bool offline = false; // patient-only mode when Supabase isn't configured
  List<Member> members = [];
  Member? current;

  final _auth = AuthService.instance;

  Future<void> start() async {
    if (Config.hasSupabase) {
      Supabase.instance.client.auth.onAuthStateChange.listen((e) {
        if (e.event == AuthChangeEvent.signedOut) {
          role = null;
          _resolve();
        }
      });
    }
    await _resolve();
  }

  Future<void> _resolve() async {
    if (!Prefs.onboarded) return _go(Stage.onboarding);
    if (offline) {
      role = UserRole.patient;
    } else {
      if (!Config.hasSupabase || _auth.user == null) return _go(Stage.login);
      try {
        role ??= await _auth.loadRole();
      } catch (_) {
        // Offline with a cached session: fall back to the last known role.
        role ??= Prefs.cachedRole;
      }
      if (role == null) return _go(Stage.pickRole);
      Prefs.cachedRole = role;
    }
    if (role == UserRole.owner) {
      final has = await _hasPharmacy();
      return _go(has ? Stage.owner : Stage.ownerSetup);
    }
    await reloadMembers();
    if (members.isEmpty) return _go(Stage.patientSetup);
    NotificationService.instance.rescheduleAll();
    _go(Stage.patient);
  }

  Future<bool> _hasPharmacy() async {
    final r = await _auth.client.from('pharmacies').select('id').eq('owner_id', _auth.user!.id).maybeSingle();
    return r != null;
  }

  void _go(Stage s) {
    stage = s;
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    Prefs.onboarded = true;
    await _resolve();
  }

  Future<void> continueOffline() async {
    offline = true;
    await _resolve();
  }

  Future<void> signedIn() => _resolve();

  Future<void> chooseRole(UserRole r) async {
    await _auth.saveRole(r);
    role = r;
    await _resolve();
  }

  Future<void> setupDone() => _resolve();

  /// Lets a signed-in user change their mind about the role (only before any data exists).
  Future<void> resetRole() async {
    role = null;
    Prefs.cachedRole = null;
    _go(Stage.pickRole);
  }

  Future<void> reloadMembers() async {
    members = await LocalDb.instance.members();
    final saved = Prefs.currentMember;
    current = members.where((m) => m.id == saved).firstOrNull ?? members.firstOrNull;
  }

  Future<void> refresh() async {
    await reloadMembers();
    notifyListeners();
    NotificationService.instance.rescheduleAll();
  }

  void selectMember(Member m) {
    current = m;
    Prefs.currentMember = m.id;
    notifyListeners();
  }

  /// Notifies listeners so list screens re-query after a write.
  void touch() {
    notifyListeners();
    NotificationService.instance.rescheduleAll();
  }

  Future<void> signOut() async {
    if (!offline) await _auth.signOut();
    offline = false;
    role = null;
    Prefs.cachedRole = null;
    await _resolve();
  }
}
