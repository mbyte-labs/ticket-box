/// The user's TMDB account session and sync choices. All of it is user-created, so every key is
/// listed in `PreferenceVersionGuard._userPreferenceKeys` and removed on a destructive migration.
class TmdbAccountKeys {
  /// The v3 session id — TMDB's equivalent of a password. Absent while logged out, and removed
  /// (while [username] and [accountId] stay) when TMDB stops accepting it, see [sessionInvalid].
  static const String sessionId = 'tmdb_account_session_id';

  static const String accountId = 'tmdb_account_id';

  static const String username = 'tmdb_account_username';

  static const String name = 'tmdb_account_name';

  /// True when a call with the stored session answered 401: the user has to log in again. The
  /// toggles and the outbox are kept so a new login resumes where things stopped.
  static const String sessionInvalid = 'tmdb_account_session_invalid';

  /// The request token the user is approving in the browser, until the deep link returns it.
  static const String pendingRequestToken = 'tmdb_account_pending_request_token';

  /// ISO-8601 instant after which [pendingRequestToken] is no good (TMDB gives it 60 minutes).
  static const String pendingRequestTokenExpiresAt = 'tmdb_account_pending_request_token_expires_at';

  /// True from a successful login until the Settings page has shown the pull / push / skip dialog.
  static const String initialSyncPromptPending = 'tmdb_account_initial_sync_prompt_pending';

  static const String syncRatings = 'tmdb_account_sync_ratings';

  static const String syncWatchlist = 'tmdb_account_sync_watchlist';

  /// The favorites list was called "recommended" when this key shipped; the stored name stays so
  /// the toggle survives the rename.
  static const String syncFavorites = 'tmdb_account_sync_recommended';

  static const List<String> all = [
    sessionId,
    accountId,
    username,
    name,
    sessionInvalid,
    pendingRequestToken,
    pendingRequestTokenExpiresAt,
    initialSyncPromptPending,
    syncRatings,
    syncWatchlist,
    syncFavorites,
  ];
}
