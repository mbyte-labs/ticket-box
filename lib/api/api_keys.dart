/// API keys holder.
///
/// The values are not in source control. They are compiled in from `secrets.json` (gitignored) with
/// `--dart-define-from-file=secrets.json`; see `secrets.example.json` and `docs/RELEASE.md`.
/// Without that flag every key is the empty string and the TMDB / OMDb calls are rejected.
class ApiKeysProvider {
  static const String _tmdbV3Key = String.fromEnvironment('TMDB_V3_KEY');
  static const String _tmdbV4Key = String.fromEnvironment('TMDB_V4_TOKEN');

  /// OMDb free-tier key.
  static const String omdbKey = String.fromEnvironment('OMDB_API_KEY');

  static String getTmDb3Key() {
    return _tmdbV3Key;
  }

  static String getTmDb4Key() {
    return _tmdbV4Key;
  }
}
