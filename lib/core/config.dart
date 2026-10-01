/// Build-time configuration, passed with --dart-define (see README).
class Config {
  /// e.g. https://vps-2976817d.vps.ovh.ca (no trailing slash)
  static const apiBase = String.fromEnvironment('API_BASE_URL');

  /// Google *web* OAuth client id; the server verifies ID tokens against it.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get hasBackend => apiBase.isNotEmpty;
}
