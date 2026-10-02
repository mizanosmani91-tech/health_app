import 'package:flutter/foundation.dart';
import 'api.dart';
import '../core/config.dart';
import '../data/local_db.dart';
import '../data/models.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'prefs.dart';

enum Stage { loading, onboarding, login, patientSetup, ownerSetup, patient, owner }

class AppState extends ChangeNotifier {
  Stage stage = Stage.loading;
  UserRole? role;
  bool offline = false; // patient-only mode when Supabase isn't configured
  /// True only for accounts that actually have a pharmacy: they alone see the switch back to it.
  bool ownsPharmacy = false;
  List<Member> members = [];
  Member? current;

  final _auth = AuthService.instance;

  Future<void> start() async {
    await _resolve();
  }

  Future<void> _resolve() async {
    if (!Prefs.onboarded) return _go(Stage.onboarding);
    if (offline) {
      role = UserRole.patient;
    } else {
      if (!Config.hasBackend || _auth.user == null) return _go(Stage.login);
      try {
        role ??= await _auth.loadRole();
      } on ApiException catch (e) {
        if (e.unauthorized) {
          // Session expired or revoked: sign in again.
          await _auth.signOut();
          return _go(Stage.login);
        }
        role ??= Prefs.cachedRole;
      } catch (_) {
        // Offline with a cached session: fall back to the last known role.
        role ??= Prefs.cachedRole;
      }
      // Everyone starts as a normal (personal/family) user. The pharmacy side is only entered through the
      // small "pharmacy owner" link on the login screen, so nobody is asked "who are you?".
      final wantsOwner = Prefs.ownerIntent;
      Prefs.ownerIntent = false;
      if (role == null || (wantsOwner && role != UserRole.owner)) {
        role = wantsOwner ? UserRole.owner : UserRole.patient;
        try {
          await _auth.saveRole(role!);
        } catch (_) {/* preference only; re-sent next time */}
      }
      Prefs.cachedRole = role;
    }
    if (role == UserRole.owner) {
      final has = await _hasPharmacy();
      return _go(has ? Stage.owner : Stage.ownerSetup);
    }
    await reloadMembers();
    if (!offline) _refreshOwns(); // not awaited: only decides whether a quiet switch row is shown
    if (members.isEmpty) return _go(Stage.patientSetup);
    NotificationService.instance.rescheduleAll();
    _go(Stage.patient);
  }

  Future<void> _refreshOwns() async {
    var owns = false;
    try {
      await Api.instance.get('/pharmacy');
      owns = true;
    } catch (_) {
      owns = false;
    }
    if (owns != ownsPharmacy) {
      ownsPharmacy = owns;
      notifyListeners();
    }
  }

  Future<bool> _hasPharmacy() async {
    try {
      await Api.instance.get('/pharmacy');
      return true;
    } on ApiException catch (e) {
      return e.status != 404; // offline etc.: let the owner shell show a retry screen
    }
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

  Future<void> setupDone() => _resolve();

  /// One account can be both a patient and a pharmacy owner. The server only stores the mode the
  /// app opens in; what you can access is decided by ownership, so switching needs no approval.
  Future<void> switchRole(UserRole r) async {
    if (offline) return;
    try {
      await _auth.saveRole(r);
    } catch (_) {
      // Offline: still switch locally, the preference is re-sent next time.
    }
    role = r;
    await _resolve();
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
    ownsPharmacy = false;
    role = null;
    Prefs.cachedRole = null;
    await _resolve();
  }
}
