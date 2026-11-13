import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ticketbox/common/model/asset_job_status.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_entity.dart';
import 'package:ticketbox/database/sql_store/cache/cache.dart';
import 'package:ticketbox/database/sql_store/converter/asset_job_status_converter.dart';
import 'package:ticketbox/database/sql_store/converter/history_action_converter.dart';
import 'package:ticketbox/database/sql_store/converter/item_type.converter.dart';
import 'package:ticketbox/database/sql_store/converter/show_watch_status_converter.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/genres/genres.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code_converter.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_converter.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_entity.dart';
import 'package:ticketbox/database/sql_store/migration/legacy_ddl.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/pending_deletion/pending_deletion_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_entity.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_entity.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation_converter.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';

part 'database_connection_manager.g.dart';

@DriftDatabase(
  tables: [
    // Catalogue (TMDB snapshots of the library)
    Shows,
    Seasons,
    Episodes,
    Movies,
    SnapshotDocuments,
    Genres,

    // Caches (other providers, browse lists)
    Caches,

    // User data (device-local)
    HistoryItems,
    UserRatings,
    Watchlists,
    ShowStates,
    FavoriteItems,

    // Application related
    JobStates,
    TmdbSyncOutbox,
    PendingDeletions,
    AssetJobs,
  ],
)
class DatabaseConnectionManager extends _$DatabaseConnectionManager {
  static final _log = Logger('DatabaseConnectionManager');

  /// The schema version the app ships with. Exposed statically so startup code (e.g. the
  /// preference version guard) can compare against it without opening the database.
  ///
  /// v3: Genres primary key became {name, type}.
  /// v4: the v3 sync backend removed — every table is keyed by TMDB id. Migrated from v3 with [_migrateV3ToV4].
  /// v5: Seasons are no longer rated directly — their score is the average of the episode ratings.
  ///     Migrated from v4 with [_migrateV4ToV5]; no table changes shape.
  /// v6: Recommended movies and shows (`recommended_items`, the favorites list under its first name).
  ///     Migrated from v5 with [_migrateV5ToV6]: one new table, nothing else changes.
  /// v7: `episode_summaries` folded into `episodes`. Migrated from v6 with [_migrateV6ToV7].
  /// v8: The TMDB sync outbox (`tmdb_sync_outbox`). Migrated from v7 with [_migrateV7ToV8]: one new
  ///     table, nothing else changes.
  /// v9: `recommended_items` renamed to `favorite_items` (`recommended_at` to `favorited_at`), TMDB's
  ///     word for the list. Migrated from v8 with [_migrateV8ToV9]: a rename, no rows change.
  /// v10: the offline-first library. Summaries folded into `movies` / `shows`, dates as `YYYY-MM-DD`
  ///     text, artwork paths instead of URLs, `snapshot_documents`, `show_states` (from
  ///     `dropped_items`), `pending_deletions`, `asset_jobs`; the poster, image, cast and stored
  ///     progress tables dropped; browse-only catalogue rows dropped. Migrated from v9 with
  ///     [_migrateV9ToV10]; the user tables are untouched.
  ///
  /// Any version change that cannot be walked through [nonDestructiveMigrations] still recreates
  /// the database from scratch.
  static const int currentSchemaVersion = 10;

  /// The single `(from, from + 1)` steps [migration] can run without losing user data. An upgrade
  /// whose every step is listed here walks them in order (3 → 10 runs 3 → 4, 4 → 5, 5 → 6, 6 → 7, 7 → 8,
  /// 8 → 9, then 9 → 10); anything else is a destructive reset. [PreferenceVersionGuard] walks the same
  /// steps.
  static const Set<(int, int)> nonDestructiveMigrations = {(3, 4), (4, 5), (5, 6), (6, 7), (7, 8), (8, 9), (9, 10)};

  /// Whether going from [from] to [to] can be done in place: an upgrade made only of listed steps.
  static bool canMigrateInPlace(int from, int to) {
    if (from >= to) {
      return false;
    }
    for (var version = from; version < to; version++) {
      if (!nonDestructiveMigrations.contains((version, version + 1))) {
        return false;
      }
    }
    return true;
  }

  DatabaseConnectionManager() : super(_openConnection());

  /// Opens the schema on a caller-supplied executor, so tests can run the real queries against an
  /// in-memory database instead of the on-device file. Not for production use.
  DatabaseConnectionManager.forTesting(super.executor);

  @override
  int get schemaVersion => currentSchemaVersion;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'ticketbox_database',
      native: const DriftNativeOptions(
        // By default, `driftDatabase` from `package:drift_flutter` stores the
        // database files in `getApplicationDocumentsDirectory()`.
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        // Only pure SQL runs inside the migration transaction. Drift bumps the database
        // `user_version` (its "initialised" marker) only after this callback completes WITHOUT
        // throwing, so a platform-channel call that throws here would re-run onCreate — and wipe
        // the data — on every launch. Default settings are seeded separately at startup via
        // DefaultAppSettingsBuilder in StartUpConfiguration.
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migration callbacks run in autocommit, so this pragma takes effect here; it would be a
        // no-op inside the transactions below.
        await customStatement('PRAGMA foreign_keys = OFF');

        if (canMigrateInPlace(from, to)) {
          _log.warning('Migration onUpgrade fired — from: $from, to: $to. Migrating in place');
          // One transaction for every step: a crash mid-way rolls everything back (including the
          // renames) and leaves `user_version` unbumped, so the migration simply re-runs on the next
          // launch.
          await transaction(() async {
            for (var version = from; version < to; version++) {
              await _migrateStep(m, version, version + 1);
            }
          });
        } else {
          _log.warning('Migration onUpgrade fired — from: $from, to: $to. Recreating the database from scratch');
          await transaction(() => _recreateFromScratch(m));
        }

        await customStatement('PRAGMA foreign_keys = ON');
      },
      beforeOpen: (OpeningDetails details) async {
        _log.info('Database opening — wasCreated: ${details.wasCreated}, hadUpgrade: ${details.hadUpgrade}');
        if (details.hadUpgrade || details.wasCreated) {
          await customStatement('PRAGMA foreign_keys = ON;');
        }
      },
    );
  }

  Future<void> _migrateStep(Migrator m, int from, int to) {
    return switch ((from, to)) {
      (3, 4) => _migrateV3ToV4(m),
      (4, 5) => _migrateV4ToV5(),
      (5, 6) => _migrateV5ToV6(),
      (6, 7) => _migrateV6ToV7(m),
      (7, 8) => _migrateV7ToV8(m),
      (8, 9) => _migrateV8ToV9(),
      (9, 10) => _migrateV9ToV10(m),
      _ => throw StateError('No in-place migration step from $from to $to'),
    };
  }

  /// Destructive migration: recreates the database from scratch, exactly like a first install.
  Future<void> _recreateFromScratch(Migrator m) async {
    await _dropAllObjects(except: const {});
    await m.createAll();
  }

  /// Drops every user-defined object in the file — including tables that no longer exist in the
  /// Dart schema, which `m.database.allTables` would miss — except the table names in [except].
  ///
  /// `ESCAPE` is needed because LIKE has no default escape character; `sql IS NOT NULL` skips
  /// auto-created constraint indexes, which cannot be dropped. Dropping a table also drops its
  /// indexes and triggers, hence IF EXISTS to keep the loop order-independent.
  Future<void> _dropAllObjects({required Set<String> except}) async {
    final objects = await customSelect(
      'SELECT name, type FROM sqlite_master '
      "WHERE type IN ('table', 'view', 'trigger', 'index') AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\' AND sql IS NOT NULL",
    ).get();

    for (final row in objects) {
      final name = row.read<String>('name');
      if (except.contains(name)) {
        continue;
      }
      final type = row.read<String>('type').toUpperCase();
      await customStatement('DROP $type IF EXISTS "${name.replaceAll('"', '""')}"');
    }
  }

  /// The v3 (`id_trakt`-keyed) tables whose rows are carried into v4, with the `v3_` name they are
  /// parked under while the v4 tables are created.
  static const Map<String, String> _v3TablesToMigrate = {
    'shows': 'v3_shows',
    'show_summaries': 'v3_show_summaries',
    'movies': 'v3_movies',
    'seasons': 'v3_seasons',
    'episodes': 'v3_episodes',
    'episode_summaries': 'v3_episode_summaries',
    'trakt_history_items': 'v3_history',
    'user_ratings': 'v3_user_ratings',
    'watchlists': 'v3_watchlists',
    'trakt_show_progress_items': 'v3_show_progress',
    'trakt_season_progress_items': 'v3_season_progress',
    'trakt_episode_progress_items': 'v3_episode_progress',
    'up_next_episode_items': 'v3_up_next',
    'dropped_items': 'v3_dropped',
    'posters': 'v3_posters',
    'show_images': 'v3_show_images',
    'movie_images': 'v3_movie_images',
    'season_images': 'v3_season_images',
    'episode_images': 'v3_episode_images',
  };

  /// Re-keys the library from v3 `id_trakt` ids to TMDB ids.
  ///
  /// Every v3 catalogue row (`shows`, `movies`) carried a NOT NULL `id_tmdb`, and every user-data row
  /// referenced its movie or show by `id_trakt`, so the mapping is a join. Seasons and episodes are
  /// addressed by number under their show, as TMDB does, so their own v3 ids are simply not
  /// selected. History ids are preserved: they stay unique and the AUTOINCREMENT sequence continues
  /// after the largest one.
  ///
  /// Rows whose show or movie is not cached cannot be mapped and are dropped (counted and logged).
  /// History rows always have their show/movie row (they were written atomically), so this is
  /// expected to be zero. v3-only tables (auth, last activities, sync states, watched aggregates,
  /// check-ins) and caches that embed v3 ids in free text (`caches`, `genres`, `item_people`) are
  /// dropped and refetched.
  ///
  /// `createAll()` creates the *current* schema, not v4's. Right after it, every table a later step
  /// reads or reshapes is put back in its v4 shape from [LegacyDdl.v4Shapes] and the objects v10
  /// added are dropped, so this step still ends on the v4 shape and the later steps run as on any
  /// file.
  ///
  /// Pure SQL + logging only: no platform channels may run inside a migration.
  Future<void> _migrateV3ToV4(Migrator m) async {
    // 1. Park the tables we read from under v3_ names, so createAll() can create the v4 tables with
    //    their real names and the migrated file ends up byte-identical to a fresh install.
    final existing = (await customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get())
        .map((row) => row.read<String>('name'))
        .toSet();
    for (final entry in _v3TablesToMigrate.entries) {
      if (existing.contains(entry.key)) {
        await customStatement('ALTER TABLE "${entry.key}" RENAME TO "${entry.value}"');
      }
    }

    // 2. Everything else from v3 goes.
    await _dropAllObjects(except: _v3TablesToMigrate.values.toSet());

    // 3. The v4 schema: the current one, then every table the later steps touch in its v4 shape —
    //    the episode tables as the 6 → 7 step merges them, the favorites under the name the 8 → 9
    //    step renames from (a v4 file had no favorites table at all; creating it here is what 5 → 6
    //    would do anyway), the summaries, posters, images, cast and progress tables the 9 → 10 step
    //    rebuilds or drops — and without the objects v10 added, which 9 → 10 creates.
    await m.createAll();
    await customStatement('DROP TABLE favorite_items');
    for (final index in LegacyDdl.v10OnlyIndexes) {
      await customStatement('DROP INDEX IF EXISTS "$index"');
    }
    for (final table in LegacyDdl.v10OnlyTables) {
      await customStatement('DROP TABLE IF EXISTS "$table"');
    }
    for (final entry in LegacyDdl.v4Shapes.entries) {
      await customStatement('DROP TABLE IF EXISTS "${entry.key}"');
      await customStatement(entry.value);
    }

    // 4. Copy. INSERT OR IGNORE + ORDER BY synchronized_at DESC: when two v3 rows collapse onto one
    //    TMDB id, the freshest one wins deterministically.
    await _logOrphans();

    await _copyIfPresent(existing, 'shows', '''
      INSERT OR IGNORE INTO shows (tmdb_id, imdb_id, title, year, synchronized_at)
      SELECT id_tmdb, id_imdb, title, year, synchronized_at FROM v3_shows ORDER BY synchronized_at DESC''');
    await _copyIfPresent(existing, 'movies', '''
      INSERT OR IGNORE INTO movies (tmdb_id, imdb_id, title, year, synchronized_at)
      SELECT id_tmdb, id_imdb, title, year, synchronized_at FROM v3_movies ORDER BY synchronized_at DESC''');
    // Summaries: the v3 rating/votes map onto the same 0–10 / count scale as TMDB's. synchronized_at
    // is zeroed so the row is refreshed from TMDB on first use; status and genres have no TMDB
    // meaning in their v3 form and are blanked.
    await _copyIfPresent(existing, 'show_summaries', '''
      INSERT OR IGNORE INTO show_summaries (tmdb_id, title, year, overview, tagline, first_aired, last_air_date, runtime,
        certification, network, country, language, trailer, homepage, vote_average, vote_count, popularity, aired_episodes,
        number_of_seasons, next_episode_air_date, next_episode_season, next_episode_number, genres, status, synchronized_at)
      SELECT sh.id_tmdb, su.title, su.year, su.overview, NULL, su.first_aired, NULL, su.runtime,
        su.certification, su.network, su.country, su.language, su.trailer, su.homepage, su.rating, su.votes, 0, su.aired_episodes,
        0, NULL, NULL, NULL, '', NULL, 0
      FROM v3_show_summaries su JOIN v3_shows sh ON sh.id_trakt = su.id_trakt ORDER BY sh.synchronized_at DESC''');
    await _copyIfPresent(existing, 'seasons', '''
      INSERT OR IGNORE INTO seasons (show_tmdb_id, season, tmdb_id, title, episode_count, air_date, synchronized_at)
      SELECT sh.id_tmdb, se.season, se.id_tmdb, se.title, NULL, NULL, 0
      FROM v3_seasons se JOIN v3_shows sh ON sh.id_trakt = se.show_trakt_id ORDER BY se.synchronized_at DESC''');
    await _copyIfPresent(existing, 'episodes', '''
      INSERT OR IGNORE INTO episodes (show_tmdb_id, season, episode, tmdb_id, imdb_id, title, synchronized_at, synchronized_summary_at)
      SELECT sh.id_tmdb, ep.season, ep.episode, ep.id_tmdb, ep.id_imdb, ep.title, 0, 0
      FROM v3_episodes ep JOIN v3_shows sh ON sh.id_trakt = ep.show_trakt_id ORDER BY ep.synchronized_at DESC''');
    // Episode summaries carry the air dates the Up Next page filters and orders on, so they are kept.
    await _copyIfPresent(existing, 'episode_summaries', '''
      INSERT OR IGNORE INTO episode_summaries (show_tmdb_id, season, episode, overview, vote_average, vote_count, runtime,
        first_aired, episode_type, synchronized_at)
      SELECT sh.id_tmdb, ep.season, ep.episode, es.overview, es.rating, es.votes, es.runtime, es.first_aired, es.episode_type, 0
      FROM v3_episode_summaries es
      JOIN v3_episodes ep ON ep.id_trakt = es.id_trakt
      JOIN v3_shows sh ON sh.id_trakt = ep.show_trakt_id ORDER BY ep.synchronized_at DESC''');

    await _copyIfPresent(existing, 'trakt_history_items', '''
      INSERT OR IGNORE INTO history_items (history_id, type, tmdb_id, season, episode, action, watched_at)
      SELECT h.history_id, h.type, m.id_tmdb, 0, 0, h.action, h.watched_at
      FROM v3_history h JOIN v3_movies m ON m.id_trakt = h.id_trakt WHERE h.type = 'movie'
      UNION ALL
      SELECT h.history_id, h.type, s.id_tmdb, h.season, h.episode, h.action, h.watched_at
      FROM v3_history h JOIN v3_shows s ON s.id_trakt = h.id_trakt WHERE h.type = 'episode\'''');

    await _copyIfPresent(existing, 'user_ratings', '''
      INSERT OR IGNORE INTO user_ratings (type, tmdb_id, season, episode, rating, rated_at)
      SELECT r.type, m.id_tmdb, 0, 0, r.rating, r.rated_at
      FROM v3_user_ratings r JOIN v3_movies m ON m.id_trakt = r.id_trakt WHERE r.type = 'movie'
      UNION ALL
      SELECT r.type, s.id_tmdb, r.season, r.episode, r.rating, r.rated_at
      FROM v3_user_ratings r JOIN v3_shows s ON s.id_trakt = r.id_trakt WHERE r.type IN ('show', 'season', 'episode')''');

    await _copyIfPresent(existing, 'watchlists', '''
      INSERT OR IGNORE INTO watchlists (type, tmdb_id, season, episode, listed_at)
      SELECT w.type, m.id_tmdb, 0, 0, w.listed_at
      FROM v3_watchlists w JOIN v3_movies m ON m.id_trakt = w.id_trakt WHERE w.type = 'movie'
      UNION ALL
      SELECT w.type, s.id_tmdb, w.season, w.episode, w.listed_at
      FROM v3_watchlists w JOIN v3_shows s ON s.id_trakt = w.id_trakt WHERE w.type IN ('show', 'season', 'episode')''');

    // Progress rows are carried as a starting point; computed_at NULL tells the refresh job to
    // recompute them from TMDB's episode lists first.
    await _copyIfPresent(existing, 'trakt_show_progress_items', '''
      INSERT OR IGNORE INTO show_progress_items (show_tmdb_id, aired, completed, last_watched_at, computed_at)
      SELECT s.id_tmdb, p.aired, p.completed, p.last_watched_at, NULL
      FROM v3_show_progress p JOIN v3_shows s ON s.id_trakt = p.id_trakt''');
    await _copyIfPresent(existing, 'trakt_season_progress_items', '''
      INSERT OR IGNORE INTO season_progress_items (show_tmdb_id, season, aired, completed)
      SELECT s.id_tmdb, p.season, p.aired, p.completed
      FROM v3_season_progress p JOIN v3_shows s ON s.id_trakt = p.trakt_show_id''');
    await _copyIfPresent(existing, 'trakt_episode_progress_items', '''
      INSERT OR IGNORE INTO episode_progress_items (show_tmdb_id, season, episode, completed)
      SELECT s.id_tmdb, p.season, p.episode, p.completed
      FROM v3_episode_progress p JOIN v3_shows s ON s.id_trakt = p.trakt_show_id''');
    await _copyIfPresent(existing, 'up_next_episode_items', '''
      INSERT OR IGNORE INTO up_next_episode_items (show_tmdb_id, season, episode)
      SELECT s.id_tmdb, u.season, u.episode
      FROM v3_up_next u JOIN v3_shows s ON s.id_trakt = u.trakt_show_id''');
    await _copyIfPresent(existing, 'dropped_items', '''
      INSERT OR IGNORE INTO dropped_items (tmdb_id, imdb_id, dropped_at)
      SELECT id_tmdb, id_imdb, synchronized_at FROM v3_dropped''');

    // Posters and images are caches, but re-keying them is one statement each and spares the user a
    // grid full of loading tiles after the update. Season/episode poster rows carry the SHOW's id.
    // The poster id is recomputed with the arithmetic key (see PosterEntity.buildId).
    await _copyIfPresent(existing, 'posters', '''
      INSERT OR IGNORE INTO posters (id, tmdb_id, season, episode, type, title, watched, watch_listed, dropped, season_premiere,
        season_finale, series_finale, mid_season_finale, rating, user_rating, poster_url, no_poster_text, loading, loading_count,
        poster_url_last_updated_at, poster_data_updated_at)
      SELECT (CASE p.type WHEN 'movie' THEN 9 WHEN 'show' THEN 1 WHEN 'season' THEN 2 ELSE 3 END) * 10000000000000000
          + x.id_tmdb * 100000000 + p.season * 10000 + p.episode,
        x.id_tmdb, p.season, p.episode, p.type, p.title, p.watched, p.watch_listed, p.dropped, p.season_premiere,
        p.season_finale, p.series_finale, p.mid_season_finale, p.rating, p.user_rating, p.poster_url, p.no_poster_text, 0, 0,
        p.poster_url_last_updated_at, 0
      FROM v3_posters p
      JOIN (SELECT 'movie' AS kind, id_trakt, id_tmdb FROM v3_movies
            UNION ALL SELECT 'show' AS kind, id_trakt, id_tmdb FROM v3_shows) x
        ON x.id_trakt = p.trakt_id AND x.kind = (CASE p.type WHEN 'movie' THEN 'movie' ELSE 'show' END)
      WHERE p.season < 10000 AND p.episode < 10000''');
    await _copyIfPresent(existing, 'show_images', '''
      INSERT OR IGNORE INTO show_images (show_tmdb_id, posterUrl, bannerUrl, synchronized_at)
      SELECT s.id_tmdb, i.posterUrl, i.bannerUrl, i.synchronized_at FROM v3_show_images i JOIN v3_shows s ON s.id_trakt = i.show_trakt_id''');
    await _copyIfPresent(existing, 'movie_images', '''
      INSERT OR IGNORE INTO movie_images (movie_tmdb_id, posterUrl, bannerUrl, synchronized_at)
      SELECT m.id_tmdb, i.posterUrl, i.bannerUrl, i.synchronized_at FROM v3_movie_images i JOIN v3_movies m ON m.id_trakt = i.movie_trakt_id''');
    await _copyIfPresent(existing, 'season_images', '''
      INSERT OR IGNORE INTO season_images (show_tmdb_id, season, posterUrl, synchronized_at)
      SELECT s.id_tmdb, i.season, i.posterUrl, i.synchronized_at FROM v3_season_images i JOIN v3_shows s ON s.id_trakt = i.show_trakt_id''');
    await _copyIfPresent(existing, 'episode_images', '''
      INSERT OR IGNORE INTO episode_images (show_tmdb_id, season, episode, stillUrl, synchronized_at)
      SELECT s.id_tmdb, i.season, i.episode, i.stillUrl, i.synchronized_at
      FROM v3_episode_images i JOIN v3_shows s ON s.id_trakt = i.show_trakt_id''');

    // 5. Done with the parked tables.
    for (final parked in _v3TablesToMigrate.values) {
      await customStatement('DROP TABLE IF EXISTS "$parked"');
    }

    final historyCount = await customSelect('SELECT COUNT(*) AS n FROM history_items').getSingle();
    _log.info('v3→v4: migrated ${historyCount.read<int>('n')} history rows');
  }

  /// Runs [sql] only when the v3 table [source] (and the tables it joins) existed. A v3 file is
  /// normally complete, but a table that never got created must not abort the whole migration.
  Future<void> _copyIfPresent(Set<String> existing, String source, String sql) async {
    if (!existing.contains(source)) {
      _log.warning('v3→v4: table $source was missing, nothing to migrate from it');
      return;
    }
    if (sql.contains('v3_shows') && !existing.contains('shows')) {
      return;
    }
    if (sql.contains('v3_movies') && !existing.contains('movies')) {
      return;
    }
    if (sql.contains('v3_episodes ') && !existing.contains('episodes')) {
      return;
    }
    await customStatement(sql);
  }

  /// Seasons stop being rated directly. Their own rating rows are deleted, and each season poster's
  /// `user_rating` is recomputed as the average of the user's ratings of that season's episodes —
  /// formatted with one decimal like `RatingService.formatAverage`, NULL while none is rated — so
  /// the pills are right before the poster's next fresh pass.
  ///
  /// Pure SQL + logging only: no platform channels may run inside a migration.
  Future<void> _migrateV4ToV5() async {
    final removed = await customUpdate("DELETE FROM user_ratings WHERE type = 'season'");
    _log.warning('v4 -> v5: removed $removed season rating(s)');
    await customStatement('''
      UPDATE posters SET user_rating = (
        SELECT CASE WHEN COUNT(*) = 0 THEN NULL ELSE printf('%.1f', AVG(r.rating)) END FROM user_ratings r
        WHERE r.type = 'episode' AND r.tmdb_id = posters.tmdb_id AND r.season = posters.season
      ) WHERE type = 'season'
    ''');
  }

  /// Adds the recommended list — the favorites list under its first name, which [_migrateV8ToV9]
  /// renames. The table is created from [LegacyDdl.v6RecommendedItems] (`IF NOT EXISTS`, so this is a no-op
  /// on a file that walked through [_migrateV3ToV4], which already put it there) rather than from the
  /// Dart schema, which only knows the renamed table.
  ///
  /// Pure SQL + logging only: no platform channels may run inside a migration.
  Future<void> _migrateV5ToV6() async {
    _log.info('v5 -> v6: creating recommended_items');
    await customStatement(LegacyDdl.v6RecommendedItems);
  }

  /// Folds `episode_summaries` into `episodes`: the two were 1:1 and always written together.
  ///
  /// The summary's freshness (`synchronized_summary_at`) becomes the row's `synchronized_at`. An
  /// episode without a summary keeps zero votes and no air date, and is marked never synchronized
  /// so it is refetched. A summary without an episode row cannot be placed and is dropped (logged;
  /// expected to be zero).
  ///
  /// The merged table is created from [LegacyDdl.v7Episodes], never from the Dart schema: `episodes`
  /// was rebuilt again by the 9 → 10 step, so `createTable(episodes)` would build that shape here.
  ///
  /// Pure SQL + logging only: no platform channels may run inside a migration.
  Future<void> _migrateV6ToV7(Migrator m) async {
    await customStatement('ALTER TABLE episodes RENAME TO v6_episodes');
    await customStatement(LegacyDdl.v7Episodes);
    await customStatement('''
      INSERT INTO episodes (show_tmdb_id, season, episode, tmdb_id, imdb_id, title, overview, vote_average, vote_count, runtime,
        first_aired, episode_type, synchronized_at)
      SELECT e.show_tmdb_id, e.season, e.episode, e.tmdb_id, e.imdb_id, e.title, s.overview, COALESCE(s.vote_average, 0),
        COALESCE(s.vote_count, 0), s.runtime, s.first_aired, s.episode_type,
        CASE WHEN s.show_tmdb_id IS NULL THEN 0 ELSE e.synchronized_summary_at END
      FROM v6_episodes e LEFT JOIN episode_summaries s USING (show_tmdb_id, season, episode)''');

    final merged = await customSelect('SELECT COUNT(*) AS n FROM episodes').getSingle();
    final orphans = await customSelect(
      '''
      SELECT COUNT(*) AS n FROM episode_summaries s
      WHERE NOT EXISTS (SELECT 1 FROM v6_episodes e WHERE e.show_tmdb_id = s.show_tmdb_id AND e.season = s.season AND e.episode = s.episode)''',
    ).getSingle();
    _log.info('v6 -> v7: merged ${merged.read<int>('n')} episodes, dropped ${orphans.read<int>('n')} orphan summaries');

    await customStatement('DROP TABLE v6_episodes');
    await customStatement('DROP TABLE episode_summaries');
  }

  /// Adds the TMDB sync outbox. `Migrator.createTable` emits `CREATE TABLE IF NOT EXISTS`, so this
  /// is a no-op on a file that walked through [_migrateV3ToV4], whose `createAll()` already built it.
  ///
  /// Pure SQL + logging only: no platform channels may run inside a migration.
  Future<void> _migrateV7ToV8(Migrator m) async {
    _log.info('v7 -> v8: creating tmdb_sync_outbox');
    await m.createTable(tmdbSyncOutbox);
  }

  /// Renames `recommended_items` to `favorite_items` and `recommended_at` to `favorited_at`: the
  /// list took TMDB's name, the rows are untouched. SQLite rewrites the stored `CREATE TABLE` on
  /// both renames, so the file ends up as a fresh install would.
  ///
  /// Pure SQL + logging only: no platform channels may run inside a migration.
  Future<void> _migrateV8ToV9() async {
    _log.info('v8 -> v9: renaming recommended_items to favorite_items');
    await customStatement('ALTER TABLE recommended_items RENAME TO favorite_items');
    await customStatement('ALTER TABLE favorite_items RENAME COLUMN recommended_at TO favorited_at');
  }

  /// The offline-first library: snapshots, derived progress, show states, the artwork queue.
  ///
  /// Every catalogue table is rebuilt: `movie_summaries` / `show_summaries` fold into `movies` /
  /// `shows`, dates become `YYYY-MM-DD` text (converted from the local-midnight seconds the previous
  /// schema stored, in this device's zone), artwork paths are harvested out of the stored image URLs
  /// so the grids keep their posters, and only *referenced* rows — a play, a rating, a watchlist,
  /// favorite or dropped row names them — are kept: search and discover residue goes. Referenced
  /// ids with no catalogue row (a backup restore, a TMDB account pull) get a stub row so the backfill
  /// knows to fetch them. `dropped_items` becomes `show_states` (sticky `dropped`), and every show
  /// with an episode play gets its `watching` / `watched` state from the same per-episode predicate
  /// the app derives progress with. The poster, image, cast and stored progress tables are dropped:
  /// all of it is derived at query time or rides the snapshot. No snapshot exists yet (`fetched_at`
  /// NULL everywhere); the catalogue refresh backfills them on its next tick.
  ///
  /// The user tables are untouched; history keeps its ids and its AUTOINCREMENT sequence.
  /// Pure SQL + logging only: no platform channels may run inside a migration.
  Future<void> _migrateV9ToV10(Migrator m) async {
    final now = DateTime.now();
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final today = _isoDate(now);

    // 1. Park the catalogue tables; the user tables stay where they are.
    for (final name in LegacyDdl.v9CatalogueTables) {
      await customStatement('ALTER TABLE "$name" RENAME TO "v9_$name"');
    }

    // 2. The v10 tables. On a walk from v3 the 3 → 4 step dropped the four new ones right after
    //    its createAll(), so every path creates them here.
    for (final table in <TableInfo>[movies, shows, seasons, episodes, snapshotDocuments, showStates, pendingDeletions, assetJobs]) {
      await m.createTable(table);
    }

    // 3. Movies: referenced ones, summary folded in, artwork path harvested from the URLs.
    await customStatement('''
      INSERT INTO movies (tmdb_id, imdb_id, title, year, overview, tagline, release_date, runtime, certification, country,
        language, trailer, homepage, vote_average, vote_count, popularity, genres, status, poster_path, backdrop_path,
        fetched_at, tracked_at, watch_providers_region)
      SELECT m.tmdb_id, m.imdb_id, COALESCE(s.title, m.title), COALESCE(s.year, m.year), s.overview, s.tagline,
        ${_isoDateSql('s.released')}, s.runtime, s.certification, s.country, s.language, s.trailer, s.homepage,
        COALESCE(s.vote_average, 0), COALESCE(s.vote_count, 0), COALESCE(s.popularity, 0), COALESCE(s.genres, ''), s.status,
        COALESCE(${_tmdbPathSql('mi.posterUrl')}, ${_tmdbPathSql('p.poster_url')}), ${_tmdbPathSql('mi.bannerUrl')},
        NULL, ?, NULL
      FROM v9_movies m
      LEFT JOIN v9_movie_summaries s ON s.tmdb_id = m.tmdb_id
      LEFT JOIN movie_images mi ON mi.movie_tmdb_id = m.tmdb_id
      LEFT JOIN posters p ON p.type = 'movie' AND p.tmdb_id = m.tmdb_id
      WHERE $_movieReferencedSql''', [nowSeconds]);
    await customStatement('''
      INSERT OR IGNORE INTO movies (tmdb_id, tracked_at)
      SELECT DISTINCT tmdb_id, ? FROM (
        SELECT tmdb_id FROM history_items WHERE type = 'movie'
        UNION SELECT tmdb_id FROM user_ratings WHERE type = 'movie'
        UNION SELECT tmdb_id FROM watchlists WHERE type = 'movie'
        UNION SELECT tmdb_id FROM favorite_items WHERE type = 'movie')''', [nowSeconds]);

    // 4. Shows, the same way.
    await customStatement('''
      INSERT INTO shows (tmdb_id, imdb_id, title, year, overview, tagline, first_air_date, last_air_date, runtime,
        certification, network, country, language, trailer, homepage, vote_average, vote_count, popularity,
        number_of_seasons, next_episode_air_date, next_episode_season, next_episode_number, genres, status, poster_path,
        backdrop_path, fetched_at, tracked_at, watch_providers_region)
      SELECT sh.tmdb_id, sh.imdb_id, COALESCE(s.title, sh.title), COALESCE(s.year, sh.year), s.overview, s.tagline,
        ${_isoDateSql('s.first_aired')}, ${_isoDateSql('s.last_air_date')}, s.runtime, s.certification, s.network, s.country,
        s.language, s.trailer, s.homepage, COALESCE(s.vote_average, 0), COALESCE(s.vote_count, 0), COALESCE(s.popularity, 0),
        COALESCE(s.number_of_seasons, 0), ${_isoDateSql('s.next_episode_air_date')}, s.next_episode_season,
        s.next_episode_number, COALESCE(s.genres, ''), s.status,
        COALESCE(${_tmdbPathSql('si.posterUrl')}, ${_tmdbPathSql('p.poster_url')}), ${_tmdbPathSql('si.bannerUrl')},
        NULL, ?, NULL
      FROM v9_shows sh
      LEFT JOIN v9_show_summaries s ON s.tmdb_id = sh.tmdb_id
      LEFT JOIN show_images si ON si.show_tmdb_id = sh.tmdb_id
      LEFT JOIN posters p ON p.type = 'show' AND p.tmdb_id = sh.tmdb_id
      WHERE $_showReferencedSql''', [nowSeconds]);
    await customStatement('''
      INSERT OR IGNORE INTO shows (tmdb_id, tracked_at)
      SELECT DISTINCT tmdb_id, ? FROM (
        SELECT tmdb_id FROM history_items WHERE type = 'episode'
        UNION SELECT tmdb_id FROM user_ratings WHERE type IN ('show', 'season', 'episode')
        UNION SELECT tmdb_id FROM watchlists WHERE type IN ('show', 'season', 'episode')
        UNION SELECT tmdb_id FROM favorite_items WHERE type = 'show'
        UNION SELECT tmdb_id FROM dropped_items)''', [nowSeconds]);

    // 5. Seasons and episodes exist iff their show does (the join), never fetched yet; a season
    //    some episode rows name but no season row does (v3-era files) gets a stub.
    await customStatement('''
      INSERT INTO seasons (show_tmdb_id, season, tmdb_id, title, episode_count, air_date, poster_path, fetched_at)
      SELECT se.show_tmdb_id, se.season, NULLIF(se.tmdb_id, 0), se.title, se.episode_count, ${_isoDateSql('se.air_date')},
        COALESCE(${_tmdbPathSql('si.posterUrl')}, ${_tmdbPathSql('p.poster_url')}), NULL
      FROM v9_seasons se
      JOIN shows sh ON sh.tmdb_id = se.show_tmdb_id
      LEFT JOIN season_images si ON si.show_tmdb_id = se.show_tmdb_id AND si.season = se.season
      LEFT JOIN posters p ON p.type = 'season' AND p.tmdb_id = se.show_tmdb_id AND p.season = se.season''');
    await customStatement('''
      INSERT INTO episodes (show_tmdb_id, season, episode, tmdb_id, imdb_id, title, overview, vote_average, vote_count, runtime,
        air_date, episode_type, still_path)
      SELECT e.show_tmdb_id, e.season, e.episode, e.tmdb_id, e.imdb_id, e.title, e.overview, e.vote_average, e.vote_count,
        e.runtime, ${_isoDateSql('e.first_aired')}, e.episode_type, ${_tmdbPathSql('ei.stillUrl')}
      FROM v9_episodes e
      JOIN shows sh ON sh.tmdb_id = e.show_tmdb_id
      LEFT JOIN episode_images ei ON ei.show_tmdb_id = e.show_tmdb_id AND ei.season = e.season AND ei.episode = e.episode''');
    await customStatement('INSERT OR IGNORE INTO seasons (show_tmdb_id, season) SELECT DISTINCT show_tmdb_id, season FROM episodes');

    // 6. Show states: dropped first (sticky), then watching / watched for every other show with an
    //    episode play — the same aired-and-played predicate the app derives progress with.
    await customStatement('''
      INSERT INTO show_states (show_tmdb_id, status, updated_at)
      SELECT d.tmdb_id, 'dropped', d.dropped_at FROM dropped_items d JOIN shows s ON s.tmdb_id = d.tmdb_id''');
    await customStatement('''
      INSERT INTO show_states (show_tmdb_id, status, updated_at)
      SELECT s.tmdb_id,
        CASE WHEN COALESCE(aired.n, 0) > 0 AND COALESCE(done.n, 0) >= aired.n THEN 'watched' ELSE 'watching' END,
        COALESCE((SELECT MAX(h.watched_at) FROM history_items h WHERE h.type = 'episode' AND h.tmdb_id = s.tmdb_id), ?)
      FROM shows s
      LEFT JOIN (SELECT e.show_tmdb_id, COUNT(*) AS n FROM episodes e
                 WHERE e.season > 0 AND e.air_date IS NOT NULL AND e.air_date <= ?
                 GROUP BY e.show_tmdb_id) aired ON aired.show_tmdb_id = s.tmdb_id
      LEFT JOIN (SELECT e.show_tmdb_id, COUNT(*) AS n FROM episodes e
                 WHERE e.season > 0 AND e.air_date IS NOT NULL AND e.air_date <= ?
                   AND EXISTS (SELECT 1 FROM history_items h WHERE h.type = 'episode' AND h.tmdb_id = e.show_tmdb_id
                               AND h.season = e.season AND h.episode = e.episode)
                 GROUP BY e.show_tmdb_id) done ON done.show_tmdb_id = s.tmdb_id
      WHERE EXISTS (SELECT 1 FROM history_items h WHERE h.type = 'episode' AND h.tmdb_id = s.tmdb_id)
        AND NOT EXISTS (SELECT 1 FROM show_states st WHERE st.show_tmdb_id = s.tmdb_id)''', [nowSeconds, today, today]);

    // 7. Cached related ids and watch providers ride the snapshot now; the OMDB ratings, the
    //    discover pages and the region list stay.
    await customStatement(r"DELETE FROM caches WHERE key LIKE 'related\_%' ESCAPE '\' OR key LIKE 'watch\_providers\_%' ESCAPE '\'");

    // 8. Everything v10 no longer has. Browse-only rows were never copied: nothing the user owns.
    for (final name in [...LegacyDdl.v9CatalogueTables.map((n) => 'v9_$n'), ...LegacyDdl.v10DroppedTables]) {
      await customStatement('DROP TABLE IF EXISTS "$name"');
    }

    // 9. The indexes (IF NOT EXISTS, so a file whose createAll() built them already is fine).
    for (final index in [idxHistoryItemsKey, idxHistoryItemsWatchedAt, idxEpisodesAirDate, idxAssetJobsStatus, idxAssetJobsItem]) {
      await m.createIndex(index);
    }

    final counts = await customSelect('''
      SELECT (SELECT COUNT(*) FROM movies) AS movies, (SELECT COUNT(*) FROM shows) AS shows,
        (SELECT COUNT(*) FROM show_states) AS states''').getSingle();
    _log.info(
      'v9 -> v10: kept ${counts.read<int>('movies')} movie(s) and ${counts.read<int>('shows')} show(s), '
      'derived ${counts.read<int>('states')} show state(s)',
    );
  }

  /// A movie row is referenced when any user table names it. Both predicates carry the type:
  /// movies and shows share TMDB's id space.
  static const String _movieReferencedSql =
      "(EXISTS (SELECT 1 FROM history_items h WHERE h.type = 'movie' AND h.tmdb_id = m.tmdb_id)"
      " OR EXISTS (SELECT 1 FROM user_ratings r WHERE r.type = 'movie' AND r.tmdb_id = m.tmdb_id)"
      " OR EXISTS (SELECT 1 FROM watchlists w WHERE w.type = 'movie' AND w.tmdb_id = m.tmdb_id)"
      " OR EXISTS (SELECT 1 FROM favorite_items f WHERE f.type = 'movie' AND f.tmdb_id = m.tmdb_id))";

  /// A show row is referenced by an episode play, a show/season/episode rating or watchlist row, a
  /// favorite, or a dropped row (check-ins are history rows).
  static const String _showReferencedSql =
      "(EXISTS (SELECT 1 FROM history_items h WHERE h.type = 'episode' AND h.tmdb_id = sh.tmdb_id)"
      " OR EXISTS (SELECT 1 FROM user_ratings r WHERE r.type IN ('show', 'season', 'episode') AND r.tmdb_id = sh.tmdb_id)"
      " OR EXISTS (SELECT 1 FROM watchlists w WHERE w.type IN ('show', 'season', 'episode') AND w.tmdb_id = sh.tmdb_id)"
      " OR EXISTS (SELECT 1 FROM favorite_items f WHERE f.type = 'show' AND f.tmdb_id = sh.tmdb_id)"
      ' OR EXISTS (SELECT 1 FROM dropped_items d WHERE d.tmdb_id = sh.tmdb_id))';

  /// A TMDB relative path out of a stored `https://image.tmdb.org/t/p/<size>/<file>` URL: the
  /// prefix is 27 characters, the size segment ends at the next slash. NULL for anything else.
  static String _tmdbPathSql(String column) {
    return "CASE WHEN $column LIKE 'https://image.tmdb.org/t/p/%' THEN substr(substr($column, 28), instr(substr($column, 28), '/')) END";
  }

  /// A local-midnight unix-seconds date column as `YYYY-MM-DD` in this device's zone; NULL stays NULL.
  static String _isoDateSql(String column) => "strftime('%Y-%m-%d', $column, 'unixepoch', 'localtime')";

  /// [date] as `YYYY-MM-DD` — the completion predicate's "today", computed here and bound, never
  /// `date('now')` in SQL.
  static String _isoDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Counts and logs the user-data rows that cannot be mapped because their show or movie row is
  /// missing. Diagnostics only — the inserts above drop them via their inner joins.
  Future<void> _logOrphans() async {
    const checks = <String, String>{
      'history': '''SELECT COUNT(*) AS n FROM v3_history h
        LEFT JOIN v3_movies m ON h.type = 'movie' AND m.id_trakt = h.id_trakt
        LEFT JOIN v3_shows s ON h.type = 'episode' AND s.id_trakt = h.id_trakt
        WHERE m.id_trakt IS NULL AND s.id_trakt IS NULL''',
      'ratings': '''SELECT COUNT(*) AS n FROM v3_user_ratings r
        LEFT JOIN v3_movies m ON r.type = 'movie' AND m.id_trakt = r.id_trakt
        LEFT JOIN v3_shows s ON r.type != 'movie' AND s.id_trakt = r.id_trakt
        WHERE m.id_trakt IS NULL AND s.id_trakt IS NULL''',
      'watchlist': '''SELECT COUNT(*) AS n FROM v3_watchlists w
        LEFT JOIN v3_movies m ON w.type = 'movie' AND m.id_trakt = w.id_trakt
        LEFT JOIN v3_shows s ON w.type != 'movie' AND s.id_trakt = w.id_trakt
        WHERE m.id_trakt IS NULL AND s.id_trakt IS NULL''',
      'show progress': '''SELECT COUNT(*) AS n FROM v3_show_progress p
        LEFT JOIN v3_shows s ON s.id_trakt = p.id_trakt WHERE s.id_trakt IS NULL''',
      'up next': '''SELECT COUNT(*) AS n FROM v3_up_next u
        LEFT JOIN v3_shows s ON s.id_trakt = u.trakt_show_id WHERE s.id_trakt IS NULL''',
    };
    for (final entry in checks.entries) {
      try {
        final row = await customSelect(entry.value).getSingle();
        final count = row.read<int>('n');
        if (count > 0) {
          _log.warning('v3→v4: dropping $count orphan ${entry.key} row(s) with no cached show/movie');
        }
      } catch (e) {
        // A missing v3 table makes the count fail; the copy step skips it too.
        _log.fine('v3→v4: orphan check for ${entry.key} skipped: $e');
      }
    }
  }
}
