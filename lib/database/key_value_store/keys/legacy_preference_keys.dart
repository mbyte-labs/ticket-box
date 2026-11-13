/// Preference keys the app no longer writes or reads, kept only so a schema migration can remove
/// what older builds left behind. Never read these.
class LegacyPreferenceKeys {
  /// OAuth access token of the v3 sync backend (schema ≤ 3).
  static const String v3AuthToken = 'authentication_trakt_auth_token';

  /// Cached v3 sync backend `/users/settings` payload (schema ≤ 3).
  static const String v3UserSettings = 'repo_trakt_user_settings';

  /// Cached v3 sync backend `/users/{slug}/stats` payload and its fetch instant (schema ≤ 3).
  static const String v3UserStats = 'repo_trakt_user_stats';
  static const String v3UserStatsFetchedAt = 'repo_trakt_user_stats_fetched_at';

  /// The full-sync instant at which the "set your country" banner was dismissed (schema ≤ 3).
  /// Replaced by [UpNextToWatchPropertiesKeys.countryBannerDismissed].
  static const String countryBannerDismissedSyncMs = 'option_up_next_to_watch_country_banner_dismissed_sync_ms';

  /// The filters of the separate discover movies / discover shows pages (schema ≤ 3), whose genre
  /// selection was stored as v3 genre slugs. Replaced by the single [DiscoverPropertiesKeys.filters].
  static const String discoverMoviesFilters = 'option_discover_movies_page_filters';
  static const String discoverShowsFilters = 'option_discover_shows_page_filters';

  /// Every key in this class, for the guard's full wipe.
  static const List<String> all = [
    v3AuthToken,
    v3UserSettings,
    v3UserStats,
    v3UserStatsFetchedAt,
    countryBannerDismissedSyncMs,
    discoverMoviesFilters,
    discoverShowsFilters,
  ];
}
