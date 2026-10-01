/// Build-time configuration, passed with --dart-define (see README).
class Config {
  static const fbApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const fbAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const fbProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const fbSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');

  /// Web OAuth client id (Firebase console > Authentication > Google). Needed
  /// so Google returns an ID token that Firebase can verify.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get hasBackend =>
      fbApiKey.isNotEmpty && fbAppId.isNotEmpty && fbProjectId.isNotEmpty && fbSenderId.isNotEmpty;
}
