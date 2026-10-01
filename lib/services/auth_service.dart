import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';

enum UserRole { patient, owner }

/// Google sign-in -> Supabase session. The role (patient | owner) lives in
/// public.profiles so one account can't be silently both.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  SupabaseClient get client => Supabase.instance.client;
  User? get user => client.auth.currentUser;

  static Future<void> init() async {
    if (Config.hasSupabase) {
      await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
    }
    await GoogleSignIn.instance.initialize(
      serverClientId: Config.googleServerClientId.isEmpty ? null : Config.googleServerClientId,
    );
  }

  Future<void> signInWithGoogle() async {
    if (!Config.hasSupabase) {
      throw StateError('SUPABASE_URL / SUPABASE_ANON_KEY দেওয়া হয়নি');
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google থেকে ID token পাওয়া যায়নি');
    await client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
  }

  /// Returns null when the user hasn't picked a role yet.
  Future<UserRole?> loadRole() async {
    final u = user;
    if (u == null) return null;
    final row = await client.from('profiles').select('role').eq('id', u.id).maybeSingle();
    if (row == null) return null;
    return row['role'] == 'owner' ? UserRole.owner : UserRole.patient;
  }

  Future<void> saveRole(UserRole role) async {
    final u = user!;
    await client.from('profiles').insert({
      'id': u.id,
      'role': role == UserRole.owner ? 'owner' : 'patient',
      'full_name': u.userMetadata?['full_name'] ?? u.email,
    });
  }

  Future<void> signOut() async {
    await client.auth.signOut();
    await GoogleSignIn.instance.signOut();
  }
}
