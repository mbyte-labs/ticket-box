import 'package:logging/logging.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/discover_properties_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/general_properties_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/legacy_preference_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/migration_settings_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/show_progress_properties_key.dart';
import 'package:ticketbox/database/key_value_store/keys/tmdb_account_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/up_next_to_watch_properties_key.dart';
import 'package:ticketbox/database/key_value_store/keys/watch_history_properties_key.dart';
import 'package:ticketbox/database/key_value_store/keys/watchlist_properties_key.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';

/// Companion to the database migration in [DatabaseConnectionManager], on the preferences side.
///
/// For a destructive migration (any version change [DatabaseConnectionManager.canMigrateInPlace]
/// rejects) every known user-created preference is removed so the app starts from a fresh-install
/// state on both stores. For an in-place upgrade only the preferences its steps made obsolete go —
/// the user's filters, poster size, landing page and country survive, exactly like their library
/// does.
///
/// Runs at startup before [DefaultAppSettingsBuilder] so removed defaults are reseeded right away.
/// Idempotent, and safe to race across isolates.
class PreferenceVersionGuard {
  static final _log = Logger('PreferenceVersionGuard');

  /// Preferences written as a result of user actions (filters, user-picked options) plus the
  /// legacy keys older builds may have left. Deliberately an explicit list — a blanket `clear()`
  /// would also remove plugin-owned entries and the version marker itself.
  static const List<String> _userPreferenceKeys = [
    GeneralPropertiesKeys.rememberFiltersOption,
    GeneralPropertiesKeys.posterSize,
    GeneralPropertiesKeys.posterQuality,
    GeneralPropertiesKeys.defaultLandingPage,
    GeneralPropertiesKeys.showPerformanceOverlay,
    GeneralPropertiesKeys.appInfoStartCount,
    GeneralPropertiesKeys.preferedWatchProvider,
    GeneralPropertiesKeys.watchProviderRegion,
    UpNextToWatchPropertiesKeys.posterSize,
    UpNextToWatchPropertiesKeys.displayRating,
    UpNextToWatchPropertiesKeys.displayUserRating,
    UpNextToWatchPropertiesKeys.switchTapWithLongPress,
    UpNextToWatchPropertiesKeys.filters,
    UpNextToWatchPropertiesKeys.nextEpisodeBasedOnLastActivity,
    UpNextToWatchPropertiesKeys.countryBannerDismissed,
    ShowProgressPropertiesKeys.filters,
    WatchHistoryPropertiesKeys.filters,
    WatchlistPropertiesKeys.filters,
    DiscoverPropertiesKeys.filters,
    ...TmdbAccountKeys.all,
    ...LegacyPreferenceKeys.all,
  ];

  /// The keys the 3 → 4 step (v3 sync backend removed, TMDB keyed) makes obsolete: the v3 session and
  /// account caches, the banner marker tied to the full sync, and the per-page discover filters —
  /// their genre selection is stored as v3 genre slugs, which TMDB's numeric genre ids cannot decode.
  /// All of them live in [LegacyPreferenceKeys].
  static const List<String> _v3ToV4ObsoleteKeys = [...LegacyPreferenceKeys.all];

  /// Per in-place step, the keys it makes obsolete. One entry per
  /// [DatabaseConnectionManager.nonDestructiveMigrations] step; 4 → 5 (seasons no longer rated),
  /// 5 → 6 (the favorites list), 6 → 7 (episode summaries), 7 → 8 (the TMDB sync outbox), 8 → 9
  /// (the favorites table renamed; its sync toggle keeps the key it shipped with) and 9 → 10 (the
  /// offline-first library: the poster quality now sizes the stored artwork, the watch-provider
  /// region prunes the snapshots, the up-next mode steers the derived query) touch no preference.
  static const Map<(int, int), List<String>> _selectiveRemovals = {
    (3, 4): _v3ToV4ObsoleteKeys,
    (4, 5): [],
    (5, 6): [],
    (6, 7): [],
    (7, 8): [],
    (8, 9): [],
    (9, 10): [],
  };

  final int _currentVersion;

  PreferenceVersionGuard({int currentVersion = DatabaseConnectionManager.currentSchemaVersion}) : _currentVersion = currentVersion;

  /// Compares the stored schema version with the current one and removes the preferences the
  /// change made obsolete, then records the current version.
  Future<void> ensureCurrentVersion() async {
    final store = KeyValueStore.instance();
    final storedVersion = await store.getInt(RepositoryKeys.appDatabaseVersion);

    if (storedVersion == _currentVersion) {
      return;
    }

    if (storedVersion == null) {
      // Fresh install, or an install that predates this guard. Treating both as "nothing to
      // remove" is only correct while the shipped schema version is still the one this guard was
      // introduced with — this guard must ship before or together with any schemaVersion bump,
      // never after.
      await store.setInt(RepositoryKeys.appDatabaseVersion, _currentVersion);
      return;
    }

    final selective = DatabaseConnectionManager.canMigrateInPlace(storedVersion, _currentVersion)
        ? [for (var version = storedVersion; version < _currentVersion; version++) ...?_selectiveRemovals[(version, version + 1)]]
        : null;
    final keys = selective ?? _userPreferenceKeys;
    _log.warning(
      'Database schema version changed ($storedVersion -> $_currentVersion) — removing '
      '${selective == null ? 'all user preferences' : 'the preferences these steps made obsolete'}',
    );
    for (final key in keys) {
      await store.remove(key);
    }
    await store.setInt(RepositoryKeys.appDatabaseVersion, _currentVersion);
  }
}
