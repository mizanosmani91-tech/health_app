import 'package:google_sign_in/google_sign_in.dart';
import '../core/config.dart';
import 'api.dart';
import 'prefs.dart';

enum UserRole { patient, owner }

class SessionUser {
  final String id;
  final String? email, name;
  const SessionUser(this.id, this.email, this.name);
}

/// Native Google sign-in -> our API (which verifies the Google ID token and
/// returns its own session token). The role (patient | owner) is write-once.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _api = Api.instance;
  SessionUser? _user;
  SessionUser? get user => Prefs.apiToken == null ? null : (_user ??= SessionUser('', Prefs.userEmail, null));

  static Future<void> init() async {
    await GoogleSignIn.instance.initialize(
      serverClientId: Config.googleServerClientId.isEmpty ? null : Config.googleServerClientId,
    );
  }

  Future<void> signInWithGoogle() async {
    if (!Config.hasBackend) throw StateError('API_BASE_URL দেওয়া হয়নি');
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google থেকে ID token পাওয়া যায়নি');
    final r = await _api.post('/auth/google', {'idToken': idToken}) as Map<String, dynamic>;
    Prefs.apiToken = r['token'] as String;
    final u = r['user'] as Map<String, dynamic>;
    Prefs.userEmail = u['email'] as String?;
    _user = SessionUser(u['id'] as String, u['email'] as String?, u['name'] as String?);
  }

  /// Returns null when the user hasn't picked a role yet.
  Future<UserRole?> loadRole() async {
    final u = await _api.get('/me') as Map<String, dynamic>;
    _user = SessionUser(u['id'] as String, u['email'] as String?, u['name'] as String?);
    final r = u['role'];
    return r == null ? null : (r == 'owner' ? UserRole.owner : UserRole.patient);
  }

  Future<void> saveRole(UserRole role) =>
      _api.post('/me/role', {'role': role == UserRole.owner ? 'owner' : 'patient'});

  Future<void> signOut() async {
    Prefs.apiToken = null;
    Prefs.userEmail = null;
    _user = null;
    try { await GoogleSignIn.instance.signOut(); } catch (_) {}
  }
}
