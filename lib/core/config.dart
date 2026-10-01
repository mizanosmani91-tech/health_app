/// Build-time configuration, passed with --dart-define (see README).
class Config {
  /// Production API (override with --dart-define=API_BASE_URL=... for local testing; no trailing slash)
  static const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://health-api.jagotech.com.bd');

  /// Google *web* OAuth client id (public identifier, not a secret); the server verifies ID tokens against it.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '1081899229737-dec0hfuu04kgs6o9f74b9774hqnblaj8.apps.googleusercontent.com',
  );

  static bool get hasBackend => apiBase.isNotEmpty;
}
