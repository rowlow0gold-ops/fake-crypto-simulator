import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _google = GoogleSignIn();

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStream => _auth.authStateChanges();
  static bool get isSignedIn => _auth.currentUser != null;

  static Future<User?> signInWithGoogle() async {
    final gUser = await _google.signIn();
    if (gUser == null) return null; // user cancelled

    final gAuth = await gUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    return result.user;
  }

  static Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }

  static String? get uid => _auth.currentUser?.uid;
  static String? get displayName => _auth.currentUser?.displayName;
  static String? get email => _auth.currentUser?.email;
  static String? get photoUrl => _auth.currentUser?.photoURL;
}
