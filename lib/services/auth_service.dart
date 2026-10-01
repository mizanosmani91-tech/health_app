import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/config.dart';

enum UserRole { patient, owner }

/// Google sign-in -> Firebase Auth. The role (patient | owner) lives in
/// users/{uid}; security rules make it write-once.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  FirebaseAuth get auth => FirebaseAuth.instance;
  FirebaseFirestore get db => FirebaseFirestore.instance;
  User? get user => Config.hasBackend ? auth.currentUser : null;

  static Future<void> init() async {
    if (Config.hasBackend) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: Config.fbApiKey, appId: Config.fbAppId,
          projectId: Config.fbProjectId, messagingSenderId: Config.fbSenderId,
        ),
      );
    }
    await GoogleSignIn.instance.initialize(
      serverClientId: Config.googleServerClientId.isEmpty ? null : Config.googleServerClientId,
    );
  }

  Future<void> signInWithGoogle() async {
    if (!Config.hasBackend) throw StateError('FIREBASE_* কনফিগ দেওয়া হয়নি');
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google থেকে ID token পাওয়া যায়নি');
    await auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
  }

  /// Returns null when the user hasn't picked a role yet.
  Future<UserRole?> loadRole() async {
    final u = user;
    if (u == null) return null;
    final snap = await db.collection('users').doc(u.uid).get();
    final r = snap.data()?['role'];
    return r == null ? null : (r == 'owner' ? UserRole.owner : UserRole.patient);
  }

  Future<void> saveRole(UserRole role) async {
    final u = user!;
    await db.collection('users').doc(u.uid).set({
      'role': role == UserRole.owner ? 'owner' : 'patient',
      'name': u.displayName ?? u.email,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> signOut() async {
    await auth.signOut();
    await GoogleSignIn.instance.signOut();
  }
}
