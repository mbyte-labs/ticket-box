import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/discover_properties_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/general_properties_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/legacy_preference_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/migration_settings_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/tmdb_account_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/up_next_to_watch_properties_key.dart';
import 'package:ticketbox/database/key_value_store/keys/watch_history_properties_key.dart';
import 'package:ticketbox/service/configuration/preference_version_guard.dart';

/// The guard mirrors the database migration on the preferences side: a destructive schema change
/// removes every user-created key, a non-destructive step removes only what it made obsolete.
void main() {
  late KeyValueStore store;

  Future<void> seedUserPreferences() async {
    await store.setString(LegacyPreferenceKeys.v3AuthToken, 'token');
    await store.setBool(GeneralPropertiesKeys.showPerformanceOverlay, true);
    await store.setInt(GeneralPropertiesKeys.appInfoStartCount, 7);
    await store.setString(GeneralPropertiesKeys.watchProviderRegion, 'RO');
    await store.setString(LegacyPreferenceKeys.v3UserSettings, '{}');
    await store.setString(UpNextToWatchPropertiesKeys.filters, '{}');
    await store.setInt(LegacyPreferenceKeys.countryBannerDismissedSyncMs, 1700000000000);
    await store.setBool(UpNextToWatchPropertiesKeys.countryBannerDismissed, true);
    await store.setString(WatchHistoryPropertiesKeys.filters, '{}');
    await store.setString(LegacyPreferenceKeys.discoverMoviesFilters, '{}');
    await store.setString(LegacyPreferenceKeys.discoverShowsFilters, '{}');
    await store.setString(DiscoverPropertiesKeys.filters, '{}');
    await store.setString(TmdbAccountKeys.sessionId, 'session');
    await store.setBool(TmdbAccountKeys.syncRatings, true);
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    store = KeyValueStore.instance();
  });

  tearDown(() async {
    // KeyValueStore.instance() registers itself in GetIt.
    await GetIt.I.reset();
  });

  test('first run stores the current version without removing anything', () async {
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 1).ensureCurrentVersion();

    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 1);
    expect(await store.getString(LegacyPreferenceKeys.v3AuthToken), 'token');
    expect(await store.getString(UpNextToWatchPropertiesKeys.filters), '{}');
  });

  test('matching version is a no-op', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 1);
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 1).ensureCurrentVersion();

    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 1);
    expect(await store.getString(LegacyPreferenceKeys.v3AuthToken), 'token');
  });

  test('a destructive version change removes all user preferences and stores the new version', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 1);
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 2).ensureCurrentVersion();

    expect(await store.containsKey(LegacyPreferenceKeys.v3AuthToken), isFalse);
    expect(await store.containsKey(GeneralPropertiesKeys.showPerformanceOverlay), isFalse);
    expect(await store.containsKey(GeneralPropertiesKeys.appInfoStartCount), isFalse);
    expect(await store.containsKey(GeneralPropertiesKeys.watchProviderRegion), isFalse);
    expect(await store.containsKey(LegacyPreferenceKeys.v3UserSettings), isFalse);
    expect(await store.containsKey(UpNextToWatchPropertiesKeys.filters), isFalse);
    expect(await store.containsKey(LegacyPreferenceKeys.countryBannerDismissedSyncMs), isFalse);
    expect(await store.containsKey(UpNextToWatchPropertiesKeys.countryBannerDismissed), isFalse);
    expect(await store.containsKey(WatchHistoryPropertiesKeys.filters), isFalse);
    expect(await store.containsKey(LegacyPreferenceKeys.discoverMoviesFilters), isFalse);
    expect(await store.containsKey(LegacyPreferenceKeys.discoverShowsFilters), isFalse);
    expect(await store.containsKey(DiscoverPropertiesKeys.filters), isFalse);
    expect(await store.containsKey(TmdbAccountKeys.sessionId), isFalse);
    expect(await store.containsKey(TmdbAccountKeys.syncRatings), isFalse);
    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 2);
  });

  test('a downgrade is destructive too', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 4);
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 3).ensureCurrentVersion();

    expect(await store.containsKey(UpNextToWatchPropertiesKeys.filters), isFalse);
    expect(await store.containsKey(GeneralPropertiesKeys.watchProviderRegion), isFalse);
    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 3);
  });

  test('3 -> 4 removes only the v3-era keys and the per-page discover filters', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 3);
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 4).ensureCurrentVersion();

    // Gone: the v3 session and caches, the sync-tied banner marker, the discover filters.
    expect(await store.containsKey(LegacyPreferenceKeys.v3AuthToken), isFalse);
    expect(await store.containsKey(LegacyPreferenceKeys.v3UserSettings), isFalse);
    expect(await store.containsKey(LegacyPreferenceKeys.countryBannerDismissedSyncMs), isFalse);
    expect(await store.containsKey(LegacyPreferenceKeys.discoverMoviesFilters), isFalse);
    expect(await store.containsKey(LegacyPreferenceKeys.discoverShowsFilters), isFalse);
    // Kept: everything the user chose, including the merged discover page's filters.
    expect(await store.getString(DiscoverPropertiesKeys.filters), '{}');
    expect(await store.getBool(GeneralPropertiesKeys.showPerformanceOverlay), isTrue);
    expect(await store.getInt(GeneralPropertiesKeys.appInfoStartCount), 7);
    expect(await store.getString(GeneralPropertiesKeys.watchProviderRegion), 'RO');
    expect(await store.getString(UpNextToWatchPropertiesKeys.filters), '{}');
    expect(await store.getString(WatchHistoryPropertiesKeys.filters), '{}');
    expect(await store.getBool(UpNextToWatchPropertiesKeys.countryBannerDismissed), isTrue);
    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 4);
  });

  test('4 -> 5 removes no preference', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 4);
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 5).ensureCurrentVersion();

    expect(await store.containsKey(LegacyPreferenceKeys.v3AuthToken), isTrue);
    expect(await store.getString(DiscoverPropertiesKeys.filters), '{}');
    expect(await store.getString(GeneralPropertiesKeys.watchProviderRegion), 'RO');
    expect(await store.getString(UpNextToWatchPropertiesKeys.filters), '{}');
    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 5);
  });

  test('5 -> 6 removes no preference', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 5);
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 6).ensureCurrentVersion();

    expect(await store.containsKey(LegacyPreferenceKeys.v3AuthToken), isTrue);
    expect(await store.getString(DiscoverPropertiesKeys.filters), '{}');
    expect(await store.getString(GeneralPropertiesKeys.watchProviderRegion), 'RO');
    expect(await store.getString(UpNextToWatchPropertiesKeys.filters), '{}');
    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 6);
  });

  test('6 -> 7 removes no preference', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 6);
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 7).ensureCurrentVersion();

    expect(await store.containsKey(LegacyPreferenceKeys.v3AuthToken), isTrue);
    expect(await store.getString(DiscoverPropertiesKeys.filters), '{}');
    expect(await store.getString(GeneralPropertiesKeys.watchProviderRegion), 'RO');
    expect(await store.getString(UpNextToWatchPropertiesKeys.filters), '{}');
    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 7);
  });

  test('3 -> 7 walks every step: only the v3-era keys go', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 3);
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 7).ensureCurrentVersion();

    expect(await store.containsKey(LegacyPreferenceKeys.v3AuthToken), isFalse);
    expect(await store.containsKey(LegacyPreferenceKeys.discoverShowsFilters), isFalse);
    expect(await store.getString(DiscoverPropertiesKeys.filters), '{}');
    expect(await store.getString(GeneralPropertiesKeys.watchProviderRegion), 'RO');
    expect(await store.getString(UpNextToWatchPropertiesKeys.filters), '{}');
    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 7);
  });

  test('a second run after the wipe is a no-op', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 1);
    await PreferenceVersionGuard(currentVersion: 2).ensureCurrentVersion();

    // Simulates another isolate running the guard again, or the next app launch.
    await store.setString(UpNextToWatchPropertiesKeys.filters, '{"fresh": true}');
    await PreferenceVersionGuard(currentVersion: 2).ensureCurrentVersion();

    expect(await store.getString(UpNextToWatchPropertiesKeys.filters), '{"fresh": true}');
    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 2);
  });

  test('7 -> 8 removes no preference', () async {
    await store.setInt(RepositoryKeys.appDatabaseVersion, 7);
    await seedUserPreferences();

    await PreferenceVersionGuard(currentVersion: 8).ensureCurrentVersion();

    expect(await store.getString(TmdbAccountKeys.sessionId), 'session');
    expect(await store.getBool(TmdbAccountKeys.syncRatings), isTrue);
    expect(await store.getString(GeneralPropertiesKeys.watchProviderRegion), 'RO');
    expect(await store.getString(UpNextToWatchPropertiesKeys.filters), '{}');
    expect(await store.getInt(RepositoryKeys.appDatabaseVersion), 8);
  });
}
