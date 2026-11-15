import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';

import 'generated/schema.dart';

/// Same schema, one version higher than the app ships with — reopening an existing file with this
/// class simulates an app update that bumped [DatabaseConnectionManager.schemaVersion].
///
/// The versions are expressed relative to [DatabaseConnectionManager.currentSchemaVersion] so that
/// bumping the shipped version (which the destructive migration expects to happen) does not turn
/// these tests into no-ops.
class _NextVersionDatabase extends DatabaseConnectionManager {
  _NextVersionDatabase(super.executor) : super.forTesting();

  static const int version = DatabaseConnectionManager.currentSchemaVersion + 1;

  @override
  int get schemaVersion => version;
}

/// Same schema, one version lower than the app ships with — stands in for the file left behind by
/// a newer build that the user then downgraded from.
class _PreviousVersionDatabase extends DatabaseConnectionManager {
  _PreviousVersionDatabase(super.executor) : super.forTesting();

  static const int version = DatabaseConnectionManager.currentSchemaVersion - 1;

  @override
  int get schemaVersion => version;
}

/// The schema pinned at v4, so the 3 → 4 step can be checked on its own: the shipped manager would
/// carry on to the current version and run every later step too.
class _V4Database extends DatabaseConnectionManager {
  _V4Database(super.executor) : super.forTesting();

  @override
  int get schemaVersion => 4;
}

/// The schema pinned at v5, so the 4 → 5 step can be checked on its own.
class _V5Database extends DatabaseConnectionManager {
  _V5Database(super.executor) : super.forTesting();

  @override
  int get schemaVersion => 5;
}

/// The schema pinned at v6, so the 5 → 6 step can be checked on its own.
class _V6Database extends DatabaseConnectionManager {
  _V6Database(super.executor) : super.forTesting();

  @override
  int get schemaVersion => 6;
}

/// The schema pinned at v7, so the 6 → 7 step can be checked on its own.
class _V7Database extends DatabaseConnectionManager {
  _V7Database(super.executor) : super.forTesting();

  @override
  int get schemaVersion => 7;
}

/// The schema pinned at v8, so the 7 → 8 step can be checked on its own.
class _V8Database extends DatabaseConnectionManager {
  _V8Database(super.executor) : super.forTesting();

  @override
  int get schemaVersion => 8;
}

/// The schema pinned at v9, so the 8 → 9 step can be checked on its own.
class _V9Database extends DatabaseConnectionManager {
  _V9Database(super.executor) : super.forTesting();

  @override
  int get schemaVersion => 9;
}

// The v3 (Trakt-keyed) fixture. Trakt ids are in the hundreds, TMDB ids in the thousands, so a
// value can never be mistaken for the other kind in an assertion.
const _showA = (trakt: 100, tmdb: 1000);
const _showB = (trakt: 101, tmdb: 1001);
// Two Trakt shows that resolve to one TMDB id; the second one was synchronized later.
const _dupStale = (trakt: 200, tmdb: 2000);
const _dupFresh = (trakt: 201, tmdb: 2000);
const _movieX = (trakt: 300, tmdb: 3000);
const _movieY = (trakt: 301, tmdb: 3001);
const _unknownTrakt = 999;
const _maxHistoryId = 42;

/// Seeds a v3 database the way the Trakt-era app left it, with raw SQL in the v3 column names.
/// DateTime columns are unix seconds, booleans 0/1, enums the converter's `name` strings.
void _seedV3(Database raw) {
  raw.execute('''
    INSERT INTO shows (id_trakt, id_tmdb, id_tvdb, id_imdb, id_slug, title, year, synchronized_at) VALUES
      (${_showA.trakt}, ${_showA.tmdb}, 81189, 'tt1000', 'show-a', 'Show A', 2010, 1700000000),
      (${_showB.trakt}, ${_showB.tmdb}, NULL, NULL, 'show-b', 'Show B', 2011, 1700000000),
      (${_dupStale.trakt}, ${_dupStale.tmdb}, NULL, NULL, 'dup-stale', 'Stale Title', 2000, 1000),
      (${_dupFresh.trakt}, ${_dupFresh.tmdb}, NULL, 'tt2000', 'dup-fresh', 'Fresh Title', 2001, 5000)''');
  raw.execute('''
    INSERT INTO movies (id_trakt, id_tmdb, id_imdb, id_slug, title, year, synchronized_at) VALUES
      (${_movieX.trakt}, ${_movieX.tmdb}, 'tt3000', 'movie-x', 'Movie X', 1999, 1700000000),
      (${_movieY.trakt}, ${_movieY.tmdb}, NULL, 'movie-y', 'Movie Y', 2005, 1700000000)''');
  raw.execute('''
    INSERT INTO show_summaries (id_trakt, title, year, overview, first_aired, updated_at, runtime, certification, network, country,
      language, trailer, homepage, rating, votes, comment_count, aired_episodes, airs_day, airs_time, airs_timezone, genres, status,
      synchronized_at) VALUES
      (${_showA.trakt}, 'Show A', 2010, 'Overview A', 1500000000, NULL, 42, 'TV-MA', 'HBO', 'us', 'en', NULL, NULL, 8.2, 50, 3, 10,
       'Sunday', '21:00', 'America/New_York', 'drama,comedy', 'returning series', 1700000000)''');
  raw.execute('''
    INSERT INTO seasons (id_trakt, id_tmdb, id_tvdb, title, season, show_trakt_id, synchronized_at) VALUES
      (1100, 51100, NULL, 'Season 1', 1, ${_showA.trakt}, 1700000000)''');
  raw.execute('''
    INSERT INTO episodes (id_trakt, id_tmdb, id_tvdb, id_imdb, title, season, episode, show_trakt_id, synchronized_at,
      synchronized_summary_at) VALUES
      (1110, 61110, NULL, 'tt1110', 'Pilot', 1, 1, ${_showA.trakt}, 1700000000, 1700000500),
      (1111, NULL, NULL, NULL, 'Second', 1, 2, ${_showA.trakt}, 1700000000, 0)''');
  raw.execute('''
    INSERT INTO episode_summaries (id_trakt, overview, rating, votes, comment_count, availableTranslations, runtime, first_aired,
      updated_at, episode_type) VALUES
      (1110, 'Pilot overview', 7.5, 12, 0, 'en,de', 45, 1600000000, NULL, 'season_premiere')''');

  raw.execute('''
    INSERT INTO trakt_history_items (history_id, id_trakt, id_item_trakt, season, episode, action, type, watched_at) VALUES
      (5, ${_movieX.trakt}, ${_movieX.trakt}, 0, 0, 'watch', 'movie', 1700000001),
      (7, ${_showA.trakt}, 1111, 1, 2, 'checkin', 'episode', 1700000002),
      (9, ${_dupStale.trakt}, NULL, 2, 3, 'scrobble', 'episode', 1700000003),
      (11, ${_dupFresh.trakt}, NULL, 1, 1, 'watch', 'episode', 1700000004),
      (13, $_unknownTrakt, NULL, 0, 0, 'watch', 'movie', 1700000005),
      ($_maxHistoryId, ${_movieY.trakt}, ${_movieY.trakt}, 0, 0, 'watch', 'movie', 1700000006)''');
  raw.execute('''
    INSERT INTO user_ratings (type, id_trakt, id_item_trakt, season, episode, rating, rated_at) VALUES
      ('season', ${_showA.trakt}, NULL, 2, 0, 7, 1700000010),
      ('movie', ${_movieX.trakt}, ${_movieX.trakt}, 0, 0, 8, 1700000011),
      ('show', ${_showB.trakt}, ${_showB.trakt}, 0, 0, 9, 1700000012),
      ('episode', $_unknownTrakt, NULL, 1, 1, 5, 1700000013)''');
  raw.execute('''
    INSERT INTO watchlists (type, id_trakt, id_item_trakt, season, episode, listed_at) VALUES
      ('episode', ${_showA.trakt}, NULL, 1, 2, 1700000020),
      ('movie', ${_movieX.trakt}, ${_movieX.trakt}, 0, 0, 1700000021)''');

  raw.execute('''
    INSERT INTO trakt_show_progress_items (id_trakt, aired, completed, last_watched_at, reset_at) VALUES
      (${_showA.trakt}, 10, 4, 1690000000, NULL),
      ($_unknownTrakt, 5, 5, NULL, NULL)''');
  raw.execute('INSERT INTO trakt_season_progress_items (trakt_show_id, season, aired, completed) VALUES (${_showA.trakt}, 1, 10, 4)');
  raw.execute('''
    INSERT INTO trakt_episode_progress_items (trakt_show_id, season, episode, completed) VALUES
      (${_showA.trakt}, 1, 1, 1),
      (${_showA.trakt}, 1, 2, 0)''');
  raw.execute('''
    INSERT INTO up_next_episode_items (trakt_show_id, trakt_episode_id, season, episode) VALUES
      (${_showA.trakt}, 1111, 1, 3),
      ($_unknownTrakt, 1, 1, 1)''');
  raw.execute('''
    INSERT INTO dropped_items (id_trakt, id_tmdb, id_tvdb, id_imdb, id_slug, synchronized_at) VALUES
      (${_showB.trakt}, ${_showB.tmdb}, NULL, 'tt1001', 'show-b', 1680000000)''');

  raw.execute('''
    INSERT INTO posters (id, trakt_id, season, episode, type, title, watched, watch_listed, dropped, season_premiere, season_finale,
      series_finale, mid_season_finale, rating, user_rating, poster_url, no_poster_text, loading, loading_count,
      poster_url_last_updated_at, poster_data_updated_at) VALUES
      (1, ${_movieX.trakt}, 0, 0, 'movie', 'Movie X', 1, 0, 0, 0, 0, 0, 0, '82%', NULL, 'http://p/m', 'Movie X', 1, 2, 1700000030, 1700000031),
      (2, ${_showA.trakt}, 0, 0, 'show', 'Show A', 0, 1, 0, 0, 0, 0, 0, NULL, '8', 'http://p/s', 'Show A', 0, 0, 1700000032, 1700000033),
      (3, ${_showA.trakt}, 1, 2, 'episode', '1x02 Second', 0, 0, 0, 1, 0, 0, 0, NULL, NULL, NULL, 'Show A', 1, 1, 1700000034, 1700000035),
      (4, $_unknownTrakt, 0, 0, 'show', 'Orphan', 0, 0, 0, 0, 0, 0, 0, NULL, NULL, NULL, 'Orphan', 0, 0, 1700000036, 1700000037)''');
  raw.execute(
    "INSERT INTO show_images (show_trakt_id, posterUrl, bannerUrl, synchronized_at) VALUES (${_showA.trakt}, 'http://p/s', 'http://b/s', 1670000000)",
  );
  raw.execute(
    "INSERT INTO movie_images (movie_trakt_id, posterUrl, bannerUrl, synchronized_at) VALUES (${_movieX.trakt}, 'http://p/m', NULL, 1670000001)",
  );
  raw.execute(
    "INSERT INTO season_images (show_trakt_id, season, posterUrl, synchronized_at) VALUES (${_showA.trakt}, 1, 'http://p/s1', 1670000002)",
  );
  raw.execute(
    "INSERT INTO episode_images (show_trakt_id, season, episode, stillUrl, synchronized_at) VALUES (${_showA.trakt}, 1, 2, 'http://still', 1670000003)",
  );

  // Trakt-only tables and the caches that embed Trakt ids in free text: all of it goes.
  raw.execute("INSERT INTO caches (key, customData, synchronized_at) VALUES ('k', '{\"traktId\": 100}', 1)");
  raw.execute("INSERT INTO genres (name, slug, type, synchronized_at) VALUES ('Action', 'action', 'show', 1)");
  raw.execute('''
    INSERT INTO item_people (type, show_trakt_id, season, episode, person_trakt_id, role, person_tmdb_id, name, characters, profilePath,
      cast_order, episode_count) VALUES ('show', ${_showA.trakt}, 0, 0, 555, 'regular', 777, 'Name', 'Char', NULL, 0, 0)''');
  raw.execute(
    "INSERT INTO item_people_syncs (type, show_trakt_id, season, episode, synchronized_at, images_synchronized_at) VALUES ('show', ${_showA.trakt}, 0, 0, 1, NULL)",
  );
  raw.execute("INSERT INTO authentications (provider, token, refresh_token, token_expire) VALUES ('trakt', 'tok', 'ref', 1)");
  raw.execute('''
    INSERT INTO sync_states (sync_type_id, state, error_code, history_synced, up_next_to_watch, userMessage, start_sync_date, last_sync_date)
      VALUES (1, 'idle', 'none', 0, 0, NULL, 0, 0)''');
  raw.execute(
    "INSERT INTO check_ins (history_id, id_trakt, id_item_trakt, season, episode, type, started_at, expires_at) VALUES (1, ${_movieX.trakt}, ${_movieX.trakt}, 0, 0, 'movie', 1, 2)",
  );
  raw.execute(
    "INSERT INTO trakt_watched_items (trakt_id, type, watched_at, last_updated_at, plays) VALUES (${_movieX.trakt}, 'movie', 1, 1, 2)",
  );
}

void main() {
  group('v3 → v4 (Trakt ids → TMDB ids), in place', () {
    late DatabaseConnectionManager db;

    /// Opens a v3 schema, seeds it, then opens the manager pinned at v4 over the same in-memory
    /// database so that its `onUpgrade` runs just the (3, 4) step. `migrateAndValidate` also asserts
    /// that the resulting schema is byte-for-byte what a fresh v4 install creates.
    setUp(() async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(3);
      _seedV3(schema.rawDatabase);
      db = _V4Database(schema.newConnection());
      await verifier.migrateAndValidate(db, 4);
    });

    tearDown(() async {
      await db.close();
    });

    Future<List<QueryRow>> rows(String sql) => db.customSelect(sql).get();

    Future<QueryRow> row(String sql) => db.customSelect(sql).getSingle();

    Future<int> count(String table, [String where = '1 = 1']) async {
      return (await row('SELECT COUNT(*) AS n FROM "$table" WHERE $where')).read<int>('n');
    }

    test('a movie history row is re-keyed to the movie\'s tmdb id, under the same history id', () async {
      final movie = await row('SELECT * FROM history_items WHERE history_id = 5');

      expect(movie.read<int>('tmdb_id'), _movieX.tmdb);
      expect(movie.read<int>('season'), 0);
      expect(movie.read<int>('episode'), 0);
      expect(movie.read<String>('type'), 'movie');
      expect(movie.read<String>('action'), 'watch');
      expect(movie.read<int>('watched_at'), 1700000001);
    });

    test('an episode history row is re-keyed to the show\'s tmdb id, numbers and action preserved', () async {
      final episode = await row('SELECT * FROM history_items WHERE history_id = 7');

      expect(episode.read<int>('tmdb_id'), _showA.tmdb);
      expect(episode.read<int>('season'), 1);
      expect(episode.read<int>('episode'), 2);
      expect(episode.read<String>('type'), 'episode');
      expect(episode.read<String>('action'), 'checkin');
      expect(episode.read<int>('watched_at'), 1700000002);
    });

    test('a history row whose show or movie was never cached is dropped, nothing else is', () async {
      expect(await count('history_items', 'history_id = 13'), 0);
      // 6 seeded, 1 orphan.
      expect(await count('history_items'), 5);
      final ids = (await rows('SELECT history_id FROM history_items ORDER BY history_id')).map((r) => r.read<int>('history_id'));
      expect(ids, [5, 7, 9, 11, _maxHistoryId]);
    });

    test('two Trakt shows with one tmdb id collapse onto one row, the fresher one, and share their history', () async {
      expect(await count('shows', 'tmdb_id = ${_dupFresh.tmdb}'), 1);
      final show = await row('SELECT * FROM shows WHERE tmdb_id = ${_dupFresh.tmdb}');
      expect(show.read<String>('title'), 'Fresh Title');
      expect(show.read<String?>('imdb_id'), 'tt2000');
      expect(show.read<int>('year'), 2001);
      expect(show.read<int>('synchronized_at'), 5000);

      final plays = await rows(
        'SELECT history_id, season, episode FROM history_items WHERE tmdb_id = ${_dupFresh.tmdb} ORDER BY history_id',
      );
      expect(plays.map((r) => r.read<int>('history_id')), [9, 11]);
      expect(plays.map((r) => (r.read<int>('season'), r.read<int>('episode'))), [(2, 3), (1, 1)]);

      // Every other catalogue row made it too.
      expect(await count('shows'), 3);
      expect(await count('movies'), 2);
    });

    test('ratings and watchlist rows are re-keyed with their numbers, even without season/episode rows', () async {
      // The season was never cached and the watchlist episode carried no Trakt episode id: both
      // are addressed by number under the show, which is all v4 needs.
      final seasonRating = await row("SELECT * FROM user_ratings WHERE type = 'season'");
      expect(seasonRating.read<int>('tmdb_id'), _showA.tmdb);
      expect(seasonRating.read<int>('season'), 2);
      expect(seasonRating.read<int>('episode'), 0);
      expect(seasonRating.read<int>('rating'), 7);
      expect(seasonRating.read<int>('rated_at'), 1700000010);

      final movieRating = await row("SELECT * FROM user_ratings WHERE type = 'movie'");
      expect(movieRating.read<int>('tmdb_id'), _movieX.tmdb);
      expect(movieRating.read<int>('rating'), 8);
      final showRating = await row("SELECT * FROM user_ratings WHERE type = 'show'");
      expect(showRating.read<int>('tmdb_id'), _showB.tmdb);
      // The orphan episode rating is gone.
      expect(await count('user_ratings'), 3);

      final episodeListing = await row("SELECT * FROM watchlists WHERE type = 'episode'");
      expect(episodeListing.read<int>('tmdb_id'), _showA.tmdb);
      expect(episodeListing.read<int>('season'), 1);
      expect(episodeListing.read<int>('episode'), 2);
      expect(episodeListing.read<int>('listed_at'), 1700000020);
      final movieListing = await row("SELECT * FROM watchlists WHERE type = 'movie'");
      expect(movieListing.read<int>('tmdb_id'), _movieX.tmdb);
      expect(movieListing.read<int>('season'), 0);
      expect(await count('watchlists'), 2);
    });

    test('show, season and episode progress and the up-next row are re-keyed; computed_at starts null', () async {
      final show = await row('SELECT * FROM show_progress_items');
      expect(show.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(show.read<int>('aired'), 10);
      expect(show.read<int>('completed'), 4);
      expect(show.read<int>('last_watched_at'), 1690000000);
      expect(show.read<int?>('computed_at'), isNull, reason: 'the refresh job must recompute migrated rows first');
      // The progress of the unknown show is dropped.
      expect(await count('show_progress_items'), 1);

      final season = await row('SELECT * FROM season_progress_items');
      expect(season.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(season.read<int>('season'), 1);
      expect(season.read<int>('aired'), 10);
      expect(season.read<int>('completed'), 4);

      final episodes = await rows('SELECT * FROM episode_progress_items ORDER BY episode');
      expect(episodes, hasLength(2));
      expect(episodes.map((r) => r.read<int>('show_tmdb_id')).toSet(), {_showA.tmdb});
      expect(episodes.map((r) => r.read<int>('completed')), [1, 0]);

      final upNext = await row('SELECT * FROM up_next_episode_items');
      expect(upNext.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(upNext.read<int>('season'), 1);
      expect(upNext.read<int>('episode'), 3);
      expect(await count('up_next_episode_items'), 1, reason: 'the up-next row of an unknown show is dropped');
    });

    test('dropped shows are re-keyed, with dropped_at taken from synchronized_at', () async {
      final dropped = await row('SELECT * FROM dropped_items');

      expect(dropped.read<int>('tmdb_id'), _showB.tmdb);
      expect(dropped.read<String?>('imdb_id'), 'tt1001');
      expect(dropped.read<int>('dropped_at'), 1680000000);
    });

    test('episodes are copied under their show\'s tmdb id and marked as never synchronized', () async {
      final episodes = await rows('SELECT * FROM episodes ORDER BY season, episode');

      expect(episodes, hasLength(2));
      final pilot = episodes.first;
      expect(pilot.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(pilot.read<int>('season'), 1);
      expect(pilot.read<int>('episode'), 1);
      expect(pilot.read<int?>('tmdb_id'), 61110);
      expect(pilot.read<String?>('imdb_id'), 'tt1110');
      expect(pilot.read<String?>('title'), 'Pilot');
      expect(pilot.read<int>('synchronized_at'), 0);
      expect(pilot.read<int>('synchronized_summary_at'), 0, reason: 'the summary has to be refetched from TMDB');
      final second = episodes.last;
      expect(second.read<int?>('tmdb_id'), isNull);
      expect(second.read<int>('episode'), 2);

      final season = await row('SELECT * FROM seasons');
      expect(season.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(season.read<int>('season'), 1);
      expect(season.read<int>('tmdb_id'), 51100);
      expect(season.read<String?>('title'), 'Season 1');
      expect(season.read<int>('synchronized_at'), 0);
    });

    test('episode summaries are carried over, keyed by (show, season, episode)', () async {
      final summary = await row('SELECT * FROM episode_summaries');

      expect(summary.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(summary.read<int>('season'), 1);
      expect(summary.read<int>('episode'), 1);
      expect(summary.read<int>('first_aired'), 1600000000);
      expect(summary.read<String?>('episode_type'), 'season_premiere');
      expect(summary.read<double>('vote_average'), 7.5);
      expect(summary.read<int>('vote_count'), 12);
      expect(summary.read<int?>('runtime'), 45);
      expect(summary.read<String?>('overview'), 'Pilot overview');
      expect(summary.read<int>('synchronized_at'), 0);
    });

    test('show summaries are carried over as stale, with the Trakt genres blanked', () async {
      final summary = await row('SELECT * FROM show_summaries');

      expect(summary.read<int>('tmdb_id'), _showA.tmdb);
      expect(summary.read<String?>('title'), 'Show A');
      expect(summary.read<int?>('runtime'), 42);
      expect(summary.read<double>('vote_average'), 8.2);
      expect(summary.read<int>('vote_count'), 50);
      expect(summary.read<int>('aired_episodes'), 10);
      expect(summary.read<int>('first_aired'), 1500000000);
      expect(summary.read<String?>('network'), 'HBO');
      expect(summary.read<String>('genres'), '', reason: 'Trakt slugs are not TMDB genre ids');
      expect(summary.read<String?>('status'), isNull, reason: 'Trakt status wording is not a ShowStatus name');
      expect(summary.read<int>('synchronized_at'), 0, reason: 'refreshed from TMDB on first use');
      expect(summary.read<double>('popularity'), 0);
      expect(summary.read<int>('number_of_seasons'), 0);
    });

    test('posters are re-keyed with the arithmetic id and no longer loading', () async {
      expect(await count('posters'), 3, reason: 'the poster of an unknown show is dropped');

      final movie = await row("SELECT * FROM posters WHERE type = 'movie'");
      expect(movie.read<int>('id'), 9 * 10000000000000000 + _movieX.tmdb * 100000000);
      expect(movie.read<int>('tmdb_id'), _movieX.tmdb);
      expect(movie.read<int>('loading'), 0);
      expect(movie.read<int>('loading_count'), 0);
      expect(movie.read<int>('watched'), 1);
      expect(movie.read<String?>('rating'), '82%');
      expect(movie.read<String?>('poster_url'), 'http://p/m');
      expect(movie.read<int>('poster_url_last_updated_at'), 1700000030);
      expect(movie.read<int>('poster_data_updated_at'), 0, reason: 'the pills are recomputed against the TMDB data');

      final show = await row("SELECT * FROM posters WHERE type = 'show'");
      expect(show.read<int>('id'), 1 * 10000000000000000 + _showA.tmdb * 100000000);
      expect(show.read<int>('tmdb_id'), _showA.tmdb);
      expect(show.read<int>('watch_listed'), 1);
      expect(show.read<String?>('user_rating'), '8');

      final episode = await row("SELECT * FROM posters WHERE type = 'episode'");
      expect(episode.read<int>('id'), 3 * 10000000000000000 + _showA.tmdb * 100000000 + 1 * 10000 + 2);
      expect(episode.read<int>('tmdb_id'), _showA.tmdb, reason: 'episode posters carry the show id');
      expect(episode.read<int>('season'), 1);
      expect(episode.read<int>('episode'), 2);
      expect(episode.read<int>('season_premiere'), 1);
      expect(episode.read<int>('loading'), 0);
    });

    test('cached images are re-keyed', () async {
      final show = await row('SELECT * FROM show_images');
      expect(show.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(show.read<String?>('posterUrl'), 'http://p/s');
      expect(show.read<String?>('bannerUrl'), 'http://b/s');
      expect(show.read<int>('synchronized_at'), 1670000000);

      final movie = await row('SELECT * FROM movie_images');
      expect(movie.read<int>('movie_tmdb_id'), _movieX.tmdb);
      expect(movie.read<String?>('posterUrl'), 'http://p/m');

      final season = await row('SELECT * FROM season_images');
      expect(season.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(season.read<int>('season'), 1);

      final episode = await row('SELECT * FROM episode_images');
      expect(episode.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(episode.read<int>('season'), 1);
      expect(episode.read<int>('episode'), 2);
      expect(episode.read<String?>('stillUrl'), 'http://still');
    });

    test('every Trakt-only table and every parked v3_ table is gone', () async {
      final tables = (await rows("SELECT name FROM sqlite_master WHERE type = 'table'")).map((r) => r.read<String>('name')).toSet();

      expect(tables.where((name) => name.contains('trakt')), isEmpty);
      expect(tables.where((name) => name.startsWith('v3_')), isEmpty);
      expect(tables, isNot(contains('authentications')));
      expect(tables, isNot(contains('sync_states')));
      expect(tables, isNot(contains('check_ins')));
      expect(tables, isNot(contains('trakt_last_activity_items')));
    });

    test('caches, genres and people are emptied for a refetch; job_states exists', () async {
      expect(await count('caches'), 0);
      expect(await count('genres'), 0);
      expect(await count('item_people'), 0);
      expect(await count('item_people_syncs'), 0);
      expect(await count('job_states'), 0);
      expect(await count('movie_summaries'), 0);
    });

    test('the history sequence continues after the largest migrated id', () async {
      final sequence = await row("SELECT seq FROM sqlite_sequence WHERE name = 'history_items'");
      expect(sequence.read<int>('seq'), _maxHistoryId);

      GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
      addTearDown(GetIt.I.reset);

      final id = await HistoryRepo().insertNew(
        NewHistoryEntry.movie(tmdbId: _movieX.tmdb, action: HistoryAction.watch, watchedAt: DateTime.utc(2026, 7, 1)),
      );

      expect(id, _maxHistoryId + 1);
    });

    test('the file is stamped with the v4 version', () async {
      final version = await row('PRAGMA user_version');
      expect(version.read<int>('user_version'), 4);
    });

    test('foreign keys are back on after the migration', () async {
      final pragma = await row('PRAGMA foreign_keys');
      expect(pragma.read<int>('foreign_keys'), 1);
    });
  });

  group('v4 → v5 (seasons no longer rated), in place', () {
    late DatabaseConnectionManager db;

    const show = 1000;
    const otherShow = 1001;

    /// Seeds a v4 file: season ratings to drop, episode ratings to average, and season posters
    /// still carrying the old season rating.
    setUp(() async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(4);
      final raw = schema.rawDatabase;
      raw.execute('''
        INSERT INTO user_ratings (type, tmdb_id, season, episode, rating, rated_at) VALUES
          ('season', $show, 1, 0, 3, 1700000000),
          ('season', $show, 2, 0, 9, 1700000001),
          ('episode', $show, 1, 1, 7, 1700000002),
          ('episode', $show, 1, 2, 8, 1700000003),
          ('episode', $show, 2, 1, 5, 1700000004),
          ('episode', $otherShow, 1, 1, 1, 1700000005),
          ('show', $show, 0, 0, 6, 1700000006),
          ('movie', $show, 0, 0, 4, 1700000007)''');
      raw.execute('''
        INSERT INTO posters (id, tmdb_id, season, episode, type, title, watched, watch_listed, dropped, season_premiere, season_finale,
          series_finale, mid_season_finale, rating, user_rating, poster_url, no_poster_text, loading, loading_count,
          poster_url_last_updated_at, poster_data_updated_at) VALUES
          (1, $show, 1, 0, 'season', 'Season 1', 0, 0, 0, 0, 0, 0, 0, NULL, '3', NULL, 'Show', 0, 0, 1, 1),
          (2, $show, 2, 0, 'season', 'Season 2', 0, 0, 0, 0, 0, 0, 0, NULL, '9', NULL, 'Show', 0, 0, 1, 1),
          (3, $show, 3, 0, 'season', 'Season 3', 0, 0, 0, 0, 0, 0, 0, NULL, '4', NULL, 'Show', 0, 0, 1, 1),
          (4, $show, 1, 1, 'episode', '1x01', 0, 0, 0, 0, 0, 0, 0, NULL, '7', NULL, 'Show', 0, 0, 1, 1),
          (5, $show, 0, 0, 'show', 'Show', 0, 0, 0, 0, 0, 0, 0, NULL, '6', NULL, 'Show', 0, 0, 1, 1)''');
      db = _V5Database(schema.newConnection());
      await verifier.migrateAndValidate(db, 5);
    });

    tearDown(() async {
      await db.close();
    });

    Future<QueryRow> row(String sql) => db.customSelect(sql).getSingle();

    Future<String?> posterUserRating(int id) async =>
        (await row('SELECT user_rating FROM posters WHERE id = $id')).read<String?>('user_rating');

    test('season ratings are deleted, every other rating is kept', () async {
      final ratings = await db.customSelect('SELECT type, COUNT(*) AS n FROM user_ratings GROUP BY type').get();

      expect({for (final r in ratings) r.read<String>('type'): r.read<int>('n')}, {'episode': 4, 'show': 1, 'movie': 1});
    });

    test('season posters show the average of their episode ratings, or nothing while none is rated', () async {
      expect(await posterUserRating(1), '7.5');
      expect(await posterUserRating(2), '5.0');
      expect(await posterUserRating(3), isNull);
    });

    test('show and episode posters keep their own rating', () async {
      expect(await posterUserRating(4), '7');
      expect(await posterUserRating(5), '6');
    });

    test('the file is stamped with the v5 version', () async {
      expect((await row('PRAGMA user_version')).read<int>('user_version'), 5);
    });
  });

  group('v5 → v6 (recommended items, the favorites under their first name), in place', () {
    late DatabaseConnectionManager db;

    const show = 1000;
    const movie = 3000;

    /// Seeds a v5 file with a little user data, which the step must leave alone.
    setUp(() async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(5);
      final raw = schema.rawDatabase;
      raw.execute('''
        INSERT INTO watchlists (type, tmdb_id, season, episode, listed_at) VALUES
          ('show', $show, 0, 0, 1700000000),
          ('movie', $movie, 0, 0, 1700000001)''');
      raw.execute('''
        INSERT INTO history_items (type, tmdb_id, season, episode, action, watched_at) VALUES
          ('movie', $movie, 0, 0, 'watch', 1700000002)''');
      db = _V6Database(schema.newConnection());
      await verifier.migrateAndValidate(db, 6);
    });

    tearDown(() async {
      await db.close();
    });

    Future<QueryRow> row(String sql) => db.customSelect(sql).getSingle();

    test('recommended_items exists, keyed by type and tmdb id, and starts empty', () async {
      final columns = await db.customSelect('PRAGMA table_info(recommended_items)').get();

      expect(columns.map((c) => c.read<String>('name')), ['type', 'tmdb_id', 'recommended_at']);
      expect({for (final c in columns) c.read<String>('name'): c.read<int>('pk')}, {'type': 1, 'tmdb_id': 2, 'recommended_at': 0});
      expect((await row('SELECT COUNT(*) AS n FROM recommended_items')).read<int>('n'), 0);
    });

    test('the seeded user data survives', () async {
      expect((await row('SELECT COUNT(*) AS n FROM watchlists')).read<int>('n'), 2);
      expect((await row('SELECT COUNT(*) AS n FROM history_items')).read<int>('n'), 1);
    });

    test('a movie and a show sharing a tmdb id are two distinct recommendations', () async {
      await db.customStatement("INSERT INTO recommended_items (type, tmdb_id, recommended_at) VALUES ('movie', $show, 1700000030)");
      await db.customStatement("INSERT INTO recommended_items (type, tmdb_id, recommended_at) VALUES ('show', $show, 1700000030)");

      expect((await row('SELECT COUNT(*) AS n FROM recommended_items')).read<int>('n'), 2);
    });

    test('the file is stamped with the v6 version', () async {
      expect((await row('PRAGMA user_version')).read<int>('user_version'), 6);
    });
  });

  group('v6 → v7 (episode summaries folded into episodes), in place', () {
    late DatabaseConnectionManager db;

    const show = 1000;
    const summarySyncedAt = 1700000500;

    /// Seeds a v6 file: an episode with its summary, one without, and a summary without an episode.
    setUp(() async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(6);
      final raw = schema.rawDatabase;
      raw.execute('''
        INSERT INTO episodes (show_tmdb_id, season, episode, tmdb_id, imdb_id, title, synchronized_at, synchronized_summary_at) VALUES
          ($show, 1, 1, 11, 'tt0011', 'Pilot', 1700000400, $summarySyncedAt),
          ($show, 1, 2, 12, NULL, 'Second', 1700000400, 1700000400)''');
      raw.execute('''
        INSERT INTO episode_summaries (show_tmdb_id, season, episode, overview, vote_average, vote_count, runtime, first_aired,
          episode_type, synchronized_at) VALUES
          ($show, 1, 1, 'Pilot overview', 7.5, 12, 45, 1600000000, 'season_premiere', 0),
          ($show, 1, 3, 'Orphan', 6.0, 3, 40, 1600600000, NULL, 0)''');
      raw.execute('''
        INSERT INTO history_items (type, tmdb_id, season, episode, action, watched_at) VALUES
          ('episode', $show, 1, 1, 'watch', 1700000002)''');
      db = _V7Database(schema.newConnection());
      await verifier.migrateAndValidate(db, 7);
    });

    tearDown(() async {
      await db.close();
    });

    Future<QueryRow> row(String sql) => db.customSelect(sql).getSingle();

    test('an episode keeps its own columns and takes over its summary and the summary freshness', () async {
      final pilot = await row('SELECT * FROM episodes WHERE episode = 1');

      expect(pilot.read<int>('show_tmdb_id'), show);
      expect(pilot.read<int?>('tmdb_id'), 11);
      expect(pilot.read<String?>('imdb_id'), 'tt0011');
      expect(pilot.read<String?>('title'), 'Pilot');
      expect(pilot.read<String?>('overview'), 'Pilot overview');
      expect(pilot.read<double>('vote_average'), 7.5);
      expect(pilot.read<int>('vote_count'), 12);
      expect(pilot.read<int?>('runtime'), 45);
      expect(pilot.read<int?>('first_aired'), 1600000000);
      expect(pilot.read<String?>('episode_type'), 'season_premiere');
      expect(pilot.read<int>('synchronized_at'), summarySyncedAt);
    });

    test('an episode without a summary has no details and is marked never synchronized', () async {
      final second = await row('SELECT * FROM episodes WHERE episode = 2');

      expect(second.read<String?>('title'), 'Second');
      expect(second.read<String?>('overview'), isNull);
      expect(second.read<double>('vote_average'), 0);
      expect(second.read<int>('vote_count'), 0);
      expect(second.read<int?>('first_aired'), isNull);
      expect(second.read<int>('synchronized_at'), 0, reason: 'the details have to be refetched from TMDB');
    });

    test('a summary without an episode row is dropped', () async {
      expect((await row('SELECT COUNT(*) AS n FROM episodes')).read<int>('n'), 2);
    });

    test('episode_summaries and the parked table are gone, and synchronized_summary_at with them', () async {
      final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map(
        (r) => r.read<String>('name'),
      );
      expect(tables, isNot(contains('episode_summaries')));
      expect(tables, isNot(contains('v6_episodes')));
      final columns = (await db.customSelect('PRAGMA table_info(episodes)').get()).map((c) => c.read<String>('name'));
      expect(columns, isNot(contains('synchronized_summary_at')));
    });

    test('the seeded user data survives', () async {
      expect((await row('SELECT COUNT(*) AS n FROM history_items')).read<int>('n'), 1);
    });

    test('the file is stamped with the v7 version', () async {
      expect((await row('PRAGMA user_version')).read<int>('user_version'), 7);
    });
  });

  group('v7 → v8 (TMDB sync outbox), in place', () {
    late DatabaseConnectionManager db;

    /// Seeds a v7 file with one row in each user table the sync touches.
    setUp(() async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(7);
      final raw = schema.rawDatabase;
      raw.execute(
        "INSERT INTO user_ratings (type, tmdb_id, season, episode, rating, rated_at) VALUES ('movie', 3000, 0, 0, 8, 1700000011)",
      );
      raw.execute("INSERT INTO watchlists (type, tmdb_id, season, episode, listed_at) VALUES ('show', 1000, 0, 0, 1700000020)");
      raw.execute("INSERT INTO recommended_items (type, tmdb_id, recommended_at) VALUES ('movie', 3001, 1700000030)");
      db = _V8Database(schema.newConnection());
      await verifier.migrateAndValidate(db, 8);
    });

    tearDown(() async {
      await db.close();
    });

    Future<QueryRow> row(String sql) => db.customSelect(sql).getSingle();

    test('tmdb_sync_outbox exists with the outbox columns and starts empty', () async {
      final columns = (await db.customSelect('PRAGMA table_info(tmdb_sync_outbox)').get()).map((c) => c.read<String>('name')).toList();
      expect(columns, ['id', 'operation', 'type', 'tmdb_id', 'season', 'episode', 'rating', 'created_at', 'attempts', 'last_error']);
      expect((await row('SELECT COUNT(*) AS n FROM tmdb_sync_outbox')).read<int>('n'), 0);
    });

    test('rows get an autoincrement id and zero attempts by default', () async {
      await db.customStatement(
        "INSERT INTO tmdb_sync_outbox (operation, type, tmdb_id, season, episode, rating, created_at) VALUES ('rate', 'movie', 3000, 0, 0, 8, 1700000040)",
      );
      final inserted = await row('SELECT * FROM tmdb_sync_outbox');
      expect(inserted.read<int>('id'), 1);
      expect(inserted.read<int>('attempts'), 0);
      expect(inserted.read<String?>('last_error'), isNull);
    });

    test('the seeded user data survives', () async {
      expect((await row('SELECT rating FROM user_ratings')).read<int>('rating'), 8);
      expect((await row('SELECT tmdb_id FROM watchlists')).read<int>('tmdb_id'), 1000);
      expect((await row('SELECT tmdb_id FROM recommended_items')).read<int>('tmdb_id'), 3001);
    });

    test('the file is stamped with the v8 version', () async {
      expect((await row('PRAGMA user_version')).read<int>('user_version'), 8);
    });
  });

  group('v8 → v9 (recommended_items renamed to favorite_items), in place', () {
    late DatabaseConnectionManager db;

    /// Seeds a v8 file with a favorite under the old table name, plus a little other user data.
    setUp(() async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(8);
      final raw = schema.rawDatabase;
      raw.execute("INSERT INTO recommended_items (type, tmdb_id, recommended_at) VALUES ('movie', 3001, 1700000030)");
      raw.execute("INSERT INTO recommended_items (type, tmdb_id, recommended_at) VALUES ('show', 3001, 1700000031)");
      raw.execute("INSERT INTO watchlists (type, tmdb_id, season, episode, listed_at) VALUES ('show', 1000, 0, 0, 1700000020)");
      raw.execute(
        "INSERT INTO tmdb_sync_outbox (operation, type, tmdb_id, season, episode, rating, created_at) VALUES ('favoriteAdd', 'movie', 3001, 0, 0, NULL, 1700000040)",
      );
      db = _V9Database(schema.newConnection());
      await verifier.migrateAndValidate(db, 9);
    });

    tearDown(() async {
      await db.close();
    });

    Future<QueryRow> row(String sql) => db.customSelect(sql).getSingle();

    test('favorite_items exists with the renamed column, keyed by type and tmdb id', () async {
      final columns = await db.customSelect('PRAGMA table_info(favorite_items)').get();

      expect(columns.map((c) => c.read<String>('name')), ['type', 'tmdb_id', 'favorited_at']);
      expect({for (final c in columns) c.read<String>('name'): c.read<int>('pk')}, {'type': 1, 'tmdb_id': 2, 'favorited_at': 0});
    });

    test('the favorites keep their rows and timestamps under the new names', () async {
      final favorites = await db.customSelect('SELECT type, tmdb_id, favorited_at FROM favorite_items ORDER BY type').get();
      expect(favorites.map((f) => (f.read<String>('type'), f.read<int>('tmdb_id'), f.read<int>('favorited_at'))), [
        ('movie', 3001, 1700000030),
        ('show', 3001, 1700000031),
      ]);
    });

    test('recommended_items is gone', () async {
      final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
      expect(tables.map((t) => t.read<String>('name')), isNot(contains('recommended_items')));
    });

    test('the seeded user data and the queued outbox row survive', () async {
      expect((await row('SELECT tmdb_id FROM watchlists')).read<int>('tmdb_id'), 1000);
      expect((await row('SELECT operation FROM tmdb_sync_outbox')).read<String>('operation'), 'favoriteAdd');
    });

    test('the file is stamped with the v9 version', () async {
      expect((await row('PRAGMA user_version')).read<int>('user_version'), 9);
    });
  });

  group('v9 → v10 (the offline-first library: snapshots, derived progress, show states), in place', () {
    late DatabaseConnectionManager db;

    // Movies 3001–3006 and 42; shows 1001–1008. Dates are seeded as local midnight so the expected
    // text is the same in every zone the test runs in.
    int localMidnight(int year, int month, int day) => DateTime(year, month, day).millisecondsSinceEpoch ~/ 1000;
    final released = localMidnight(2020, 9, 13);
    final aired = localMidnight(2011, 4, 17);
    final future = localMidnight(2099, 1, 1);
    final farFuture = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;

    setUp(() async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(9);
      final raw = schema.rawDatabase;

      // Movies.
      raw.execute('''
        INSERT INTO movies (tmdb_id, imdb_id, title, year, synchronized_at) VALUES
          (3001, 'tt3001', 'Movie One', 2020, 1700000000),
          (3002, NULL, 'Movie Two', 2021, 1700000000),
          (3003, NULL, 'Movie Three', 2022, 1700000000),
          (3004, NULL, 'Movie Four', 2023, 1700000000),
          (3005, NULL, 'Browsed Movie', 2024, 1700000000),
          (42, NULL, 'Forty-Two', 2000, 1700000000)''');
      raw.execute('''
        INSERT INTO movie_summaries (tmdb_id, title, year, overview, tagline, released, runtime, certification, country, language,
          trailer, homepage, vote_average, vote_count, popularity, genres, status, synchronized_at) VALUES
          (3001, 'Movie One', 2020, 'Overview one', 'Tag', $released, 100, 'R', 'US', 'en', NULL, NULL, 8.1, 10, 1.5, '18,53', 'released', 1700000000),
          (3005, 'Browsed Movie', 2024, NULL, NULL, NULL, 90, NULL, NULL, NULL, NULL, NULL, 5, 1, 1, '', NULL, 1700000000)''');
      raw.execute('''
        INSERT INTO movie_images (movie_tmdb_id, posterUrl, bannerUrl, synchronized_at) VALUES
          (3001, 'https://image.tmdb.org/t/p/w342/m1.jpg', 'https://image.tmdb.org/t/p/original/m1b.jpg', 1700000000)''');
      raw.execute(
        '''
        INSERT INTO posters (id, tmdb_id, season, episode, type, title, watched, watch_listed, dropped, season_premiere, season_finale,
          series_finale, mid_season_finale, rating, user_rating, poster_url, no_poster_text, loading, loading_count,
          poster_url_last_updated_at, poster_data_updated_at) VALUES
          (90000300200000000, 3002, 0, 0, 'movie', 'Movie Two', 0, 0, 0, 0, 0, 0, 0, NULL, '8', 'https://image.tmdb.org/t/p/w500/m2.jpg', 'Movie Two', 0, 0, 1, 1),
          (20000100100010000, 1001, 1, 0, 'season', 'Season 1', 0, 0, 0, 0, 0, 0, 0, NULL, NULL, 'https://image.tmdb.org/t/p/w500/s1s1-poster.jpg', 'Show One', 0, 0, 1, 1)''',
      );

      // Shows.
      raw.execute('''
        INSERT INTO shows (tmdb_id, imdb_id, title, year, synchronized_at) VALUES
          (1001, 'tt1001', 'Show One', 2011, 1700000000),
          (1002, NULL, 'Dropped Never Started', 2012, 1700000000),
          (1003, NULL, 'Browsed Show', 2013, 1700000000),
          (1004, NULL, 'Season Watchlisted', 2014, 1700000000),
          (1007, NULL, 'Finished', 2017, 1700000000),
          (1008, NULL, 'Dropped And Finished', 2018, 1700000000)''');
      raw.execute('''
        INSERT INTO show_summaries (tmdb_id, title, year, overview, tagline, first_aired, last_air_date, runtime, certification, network,
          country, language, trailer, homepage, vote_average, vote_count, popularity, aired_episodes, number_of_seasons,
          next_episode_air_date, next_episode_season, next_episode_number, genres, status, synchronized_at) VALUES
          (1001, 'Show One', 2011, 'Overview', NULL, $aired, NULL, 45, 'TV-MA', 'HBO', 'US', 'en', NULL, NULL, 8.5, 100, 2.5, 3, 2,
           $future, 1, 4, '18', 'returning', 1700000000)''');
      raw.execute('''
        INSERT INTO show_images (show_tmdb_id, posterUrl, bannerUrl, synchronized_at) VALUES
          (1001, 'https://image.tmdb.org/t/p/w342/s1.jpg', 'https://image.tmdb.org/t/p/original/s1b.jpg', 1700000000)''');
      raw.execute('''
        INSERT INTO seasons (show_tmdb_id, season, tmdb_id, title, episode_count, air_date, synchronized_at) VALUES
          (1001, 0, 500, 'Specials', 1, NULL, 1700000000),
          (1001, 1, 501, 'Season 1', 4, $aired, 1700000000),
          (1003, 1, 0, 'Season 1', 1, NULL, 0),
          (1007, 1, 701, 'Season 1', 2, $aired, 1700000000),
          (1008, 1, 801, 'Season 1', 1, $aired, 1700000000)''');
      raw.execute(
        "INSERT INTO season_images (show_tmdb_id, season, posterUrl, synchronized_at) VALUES (1001, 1, 'https://image.tmdb.org/t/p/w342/s1s1.jpg', 1)",
      );
      raw.execute('''
        INSERT INTO episodes (show_tmdb_id, season, episode, tmdb_id, imdb_id, title, overview, vote_average, vote_count, runtime,
          first_aired, episode_type, synchronized_at) VALUES
          (1001, 0, 1, 600, NULL, 'Special', NULL, 0, 0, 10, $aired, 'standard', 1700000000),
          (1001, 1, 1, 601, 'tt601', 'Pilot', 'Pilot overview', 7.5, 12, 45, $aired, 'season_premiere', 1700000000),
          (1001, 1, 2, 602, NULL, 'Second', NULL, 7, 10, 45, $aired, 'standard', 1700000000),
          (1001, 1, 3, 603, NULL, 'Third', NULL, 7, 10, 45, $aired, 'standard', 1700000000),
          (1001, 1, 4, 604, NULL, 'Future', NULL, 0, 0, NULL, $future, 'standard', 1700000000),
          (1001, 2, 1, 605, NULL, 'Orphan season', NULL, 0, 0, NULL, NULL, 'standard', 0),
          (1003, 1, 1, 300, NULL, 'Browsed', NULL, 0, 0, NULL, $aired, 'standard', 1700000000),
          (1007, 1, 1, 701, NULL, 'A', NULL, 0, 0, NULL, $aired, 'standard', 1700000000),
          (1007, 1, 2, 702, NULL, 'B', NULL, 0, 0, NULL, $aired, 'season_finale', 1700000000),
          (1008, 1, 1, 801, NULL, 'A', NULL, 0, 0, NULL, $aired, 'standard', 1700000000)''');
      raw.execute(
        "INSERT INTO episode_images (show_tmdb_id, season, episode, stillUrl, synchronized_at) VALUES (1001, 1, 1, 'https://image.tmdb.org/t/p/w300/s1e1.jpg', 1)",
      );

      // User data: a play of movie 3001, of movie 3006 (no catalogue row), a future check-in of movie 42,
      // show 1001's S1E1, S1E2 and special, show 1005's S1E1 (no catalogue row), 1007's both, 1008's one.
      raw.execute('''
        INSERT INTO history_items (history_id, type, tmdb_id, season, episode, action, watched_at) VALUES
          (5, 'movie', 3001, 0, 0, 'watch', 1700000001),
          (7, 'movie', 3006, 0, 0, 'scrobble', 1700000002),
          (10, 'episode', 1001, 1, 1, 'watch', 1700000010),
          (11, 'episode', 1001, 1, 2, 'watch', 1700000011),
          (12, 'episode', 1001, 0, 1, 'watch', 1700000012),
          (13, 'episode', 1005, 1, 1, 'watch', 1700000013),
          (14, 'episode', 1007, 1, 1, 'watch', 1700000014),
          (15, 'episode', 1007, 1, 2, 'watch', 1700000015),
          (16, 'episode', 1008, 1, 1, 'watch', 1700000016),
          (42, 'movie', 42, 0, 0, 'checkin', $farFuture)''');
      raw.execute(
        "INSERT INTO user_ratings (type, tmdb_id, season, episode, rating, rated_at) VALUES ('movie', 3002, 0, 0, 8, 1700000020)",
      );
      raw.execute('''
        INSERT INTO watchlists (type, tmdb_id, season, episode, listed_at) VALUES
          ('movie', 3003, 0, 0, 1700000030),
          ('season', 1004, 2, 0, 1700000031)''');
      raw.execute("INSERT INTO favorite_items (type, tmdb_id, favorited_at) VALUES ('movie', 3004, 1700000040)");
      raw.execute('''
        INSERT INTO dropped_items (tmdb_id, imdb_id, dropped_at) VALUES
          (1002, NULL, 1700000050),
          (1008, NULL, 1700000051)''');
      raw.execute(
        'INSERT INTO show_progress_items (show_tmdb_id, aired, completed, last_watched_at, computed_at) VALUES (1001, 3, 2, 1700000011, 1700000012)',
      );
      raw.execute('INSERT INTO season_progress_items (show_tmdb_id, season, aired, completed) VALUES (1001, 1, 3, 2)');
      raw.execute('INSERT INTO episode_progress_items (show_tmdb_id, season, episode, completed) VALUES (1001, 1, 1, 1)');
      raw.execute('INSERT INTO up_next_episode_items (show_tmdb_id, season, episode) VALUES (1001, 1, 3)');
      raw.execute('''
        INSERT INTO item_people (type, item_tmdb_id, season, episode, role, person_tmdb_id, name, characters, profilePath, cast_order,
          episode_count) VALUES ('show', 1001, 0, 0, 'regular', 777, 'Name', 'Char', NULL, 0, 0)''');
      raw.execute(
        "INSERT INTO item_people_syncs (type, item_tmdb_id, season, episode, synchronized_at, images_synchronized_at) VALUES ('show', 1001, 0, 0, 1, NULL)",
      );

      // Caches, the outbox and a job row.
      raw.execute('''
        INSERT INTO caches (key, customData, synchronized_at) VALUES
          ('related_movie_1', '{"ids":[2]}', 1),
          ('watch_providers_show_1_US', '{"providers":[]}', 1),
          ('watch_provider_regions', '{"regions":[]}', 1),
          ('external_ratings_movie_1', '{"imdbRating":"8.0"}', 1),
          ('discover_movies_popular', '{"ids":[1]}', 1)''');
      raw.execute(
        "INSERT INTO tmdb_sync_outbox (operation, type, tmdb_id, season, episode, rating, created_at) VALUES ('rate', 'movie', 3002, 0, 0, 8, 1700000060)",
      );
      raw.execute(
        "INSERT INTO job_states (job_id, state, error_code, userMessage, started_at, finished_at) VALUES (1, 'finished', 'none', NULL, 1, 2)",
      );

      db = DatabaseConnectionManager.forTesting(schema.newConnection());
      await verifier.migrateAndValidate(db, 10);
    });

    tearDown(() async {
      await db.close();
    });

    Future<List<QueryRow>> rows(String sql) => db.customSelect(sql).get();
    Future<QueryRow> row(String sql) => db.customSelect(sql).getSingle();
    Future<QueryRow?> rowOrNull(String sql) => db.customSelect(sql).getSingleOrNull();
    Future<Set<String>> columns(String table) async =>
        (await db.customSelect('PRAGMA table_info($table)').get()).map((c) => c.read<String>('name')).toSet();

    test('every user row survives with its id, values and the AUTOINCREMENT sequence', () async {
      final history = await rows(
        'SELECT history_id, type, tmdb_id, season, episode, action, watched_at FROM history_items ORDER BY history_id',
      );
      expect(history.map((h) => h.read<int>('history_id')), [5, 7, 10, 11, 12, 13, 14, 15, 16, 42]);
      expect(history.first.read<String>('type'), 'movie');
      expect(history.first.read<int>('tmdb_id'), 3001);
      expect(history.first.read<int>('watched_at'), 1700000001);
      expect(history.last.read<String>('action'), 'checkin');
      expect(history.last.read<int>('watched_at'), farFuture);
      expect((await row("SELECT seq FROM sqlite_sequence WHERE name = 'history_items'")).read<int>('seq'), 42);

      GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
      addTearDown(GetIt.I.reset);
      final id = await HistoryRepo().insertNew(
        NewHistoryEntry.movie(tmdbId: 3001, action: HistoryAction.watch, watchedAt: DateTime.fromMillisecondsSinceEpoch(1700000099000)),
      );
      expect(id, 43);

      final rating = await row('SELECT type, tmdb_id, rating, rated_at FROM user_ratings');
      expect(
        (rating.read<String>('type'), rating.read<int>('tmdb_id'), rating.read<int>('rating'), rating.read<int>('rated_at')),
        ('movie', 3002, 8, 1700000020),
      );
      final watchlist = await rows('SELECT type, tmdb_id, season FROM watchlists ORDER BY tmdb_id');
      expect(watchlist.map((w) => (w.read<String>('type'), w.read<int>('tmdb_id'), w.read<int>('season'))), [
        ('season', 1004, 2),
        ('movie', 3003, 0),
      ]);
      expect((await row('SELECT tmdb_id, favorited_at FROM favorite_items')).read<int>('favorited_at'), 1700000040);
      expect((await row('SELECT operation FROM tmdb_sync_outbox')).read<String>('operation'), 'rate');
      expect((await row('SELECT state FROM job_states WHERE job_id = 1')).read<String>('state'), 'finished');
    });

    test('a movie with a summary keeps it folded in, dated as text, with its artwork paths and no snapshot', () async {
      final movie = await row('SELECT * FROM movies WHERE tmdb_id = 3001');

      expect(movie.read<String?>('title'), 'Movie One');
      expect(movie.read<String?>('overview'), 'Overview one');
      expect(movie.read<String?>('release_date'), '2020-09-13');
      expect(movie.read<int?>('runtime'), 100);
      expect(movie.read<String?>('genres'), '18,53');
      expect(movie.read<String?>('status'), 'released');
      expect(movie.read<String?>('poster_path'), '/m1.jpg');
      expect(movie.read<String?>('backdrop_path'), '/m1b.jpg');
      expect(movie.read<int?>('fetched_at'), isNull);
      expect(movie.read<int?>('tracked_at'), isNotNull);
      expect(movie.read<String?>('watch_providers_region'), isNull);
      expect(await columns('movies'), isNot(contains('synchronized_at')));
      expect(await columns('movies'), containsAll(['metadata_json'].where((_) => false)));
    });

    test('a movie without a summary is kept with defaults and its poster harvested from the poster row', () async {
      final movie = await row('SELECT * FROM movies WHERE tmdb_id = 3002');

      expect(movie.read<String?>('title'), 'Movie Two');
      expect(movie.read<String?>('release_date'), isNull);
      expect(movie.read<double>('vote_average'), 0);
      expect(movie.read<String>('genres'), '');
      expect(movie.read<String?>('poster_path'), '/m2.jpg');
    });

    test('only referenced catalogue rows survive; referenced ids without a row get a stub; the id space is per type', () async {
      final movies = (await rows('SELECT tmdb_id FROM movies ORDER BY tmdb_id')).map((m) => m.read<int>('tmdb_id')).toList();
      expect(movies, [42, 3001, 3002, 3003, 3004, 3006]);
      expect((await row('SELECT title FROM movies WHERE tmdb_id = 3006')).read<String?>('title'), isNull);

      final shows = (await rows('SELECT tmdb_id FROM shows ORDER BY tmdb_id')).map((s) => s.read<int>('tmdb_id')).toList();
      expect(shows, [1001, 1002, 1004, 1005, 1007, 1008]);
      expect(await rowOrNull('SELECT 1 FROM shows WHERE tmdb_id = 42'), isNull);
      expect(await rows('SELECT 1 FROM seasons WHERE show_tmdb_id = 1003'), isEmpty);
      expect(await rows('SELECT 1 FROM episodes WHERE show_tmdb_id = 1003'), isEmpty);
    });

    test('a show keeps its summary, dates as text, artwork, seasons and episodes', () async {
      final show = await row('SELECT * FROM shows WHERE tmdb_id = 1001');
      expect(show.read<String?>('first_air_date'), '2011-04-17');
      expect(show.read<String?>('next_episode_air_date'), '2099-01-01');
      expect(show.read<int>('number_of_seasons'), 2);
      expect(show.read<String?>('poster_path'), '/s1.jpg');
      expect(show.read<String?>('backdrop_path'), '/s1b.jpg');
      expect(show.read<int?>('fetched_at'), isNull);
      expect(await columns('shows'), isNot(contains('aired_episodes')));

      final season = await row('SELECT * FROM seasons WHERE show_tmdb_id = 1001 AND season = 1');
      expect(season.read<int?>('tmdb_id'), 501);
      expect(season.read<String?>('air_date'), '2011-04-17');
      expect(season.read<String?>('poster_path'), '/s1s1.jpg');
      expect(season.read<int?>('fetched_at'), isNull);
      // The season the episode rows name but no season row did.
      final stub = await row('SELECT * FROM seasons WHERE show_tmdb_id = 1001 AND season = 2');
      expect(stub.read<int?>('tmdb_id'), isNull);
      expect(stub.read<String?>('title'), isNull);
      final browsedSeason = await rowOrNull('SELECT 1 FROM seasons WHERE show_tmdb_id = 1003');
      expect(browsedSeason, isNull);

      final pilot = await row('SELECT * FROM episodes WHERE show_tmdb_id = 1001 AND season = 1 AND episode = 1');
      expect(pilot.read<String?>('air_date'), '2011-04-17');
      expect(pilot.read<String?>('still_path'), '/s1e1.jpg');
      expect(pilot.read<String?>('imdb_id'), 'tt601');
      expect(pilot.read<String?>('episode_type'), 'season_premiere');
      final unscheduled = await row('SELECT air_date FROM episodes WHERE show_tmdb_id = 1001 AND season = 2 AND episode = 1');
      expect(unscheduled.read<String?>('air_date'), isNull);
      expect(await columns('episodes'), isNot(contains('first_aired')));
      expect(await columns('episodes'), isNot(contains('synchronized_at')));
    });

    test('show states: dropped is sticky, the rest derives from aired and played episodes', () async {
      final states = await rows('SELECT show_tmdb_id, status FROM show_states ORDER BY show_tmdb_id');
      expect(
        {for (final s in states) s.read<int>('show_tmdb_id'): s.read<String>('status')},
        {
          1001: 'watching', // 2 of 3 aired episodes played; the special and the unaired one do not count
          1002: 'dropped', // never started
          1005: 'watching', // plays, no catalogue yet
          1007: 'watched', // every aired episode played
          1008: 'dropped', // dropped wins over finished
        },
      );
      expect((await row('SELECT updated_at FROM show_states WHERE show_tmdb_id = 1002')).read<int>('updated_at'), 1700000050);
      expect((await row('SELECT updated_at FROM show_states WHERE show_tmdb_id = 1001')).read<int>('updated_at'), 1700000012);
    });

    test('caches keep the OMDB ratings, the discover page and the regions; related and providers go', () async {
      final keys = (await rows('SELECT key FROM caches ORDER BY key')).map((c) => c.read<String>('key')).toList();
      expect(keys, ['discover_movies_popular', 'external_ratings_movie_1', 'watch_provider_regions']);
    });

    test('the dropped tables are gone, the new ones and the indexes are there, nothing is pending', () async {
      final tables = (await rows("SELECT name FROM sqlite_master WHERE type = 'table'")).map((t) => t.read<String>('name')).toSet();
      for (final gone in [
        'movie_summaries',
        'show_summaries',
        'posters',
        'show_images',
        'movie_images',
        'season_images',
        'episode_images',
        'item_people',
        'item_people_syncs',
        'show_progress_items',
        'season_progress_items',
        'episode_progress_items',
        'up_next_episode_items',
        'dropped_items',
        'v9_movies',
        'v9_shows',
        'v9_seasons',
        'v9_episodes',
      ]) {
        expect(tables, isNot(contains(gone)), reason: '$gone should have been dropped');
      }
      expect(tables, containsAll(['snapshot_documents', 'show_states', 'pending_deletions', 'asset_jobs']));
      final indexes = (await rows(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'",
      )).map((i) => i.read<String>('name')).toSet();
      expect(indexes, {
        'idx_history_items_key',
        'idx_history_items_watched_at',
        'idx_episodes_air_date',
        'idx_asset_jobs_status',
        'idx_asset_jobs_item',
      });
      expect(await rows('SELECT 1 FROM pending_deletions'), isEmpty);
      expect(await rows('SELECT 1 FROM snapshot_documents'), isEmpty);
      expect(await rows('SELECT 1 FROM asset_jobs'), isEmpty);
    });

    test('the file is stamped with the v10 version', () async {
      expect((await row('PRAGMA user_version')).read<int>('user_version'), 10);
    });
  });

  test(
    'v3 → v10 walks every step in place: re-keyed, season ratings dropped, favorites added and renamed, summaries merged, outbox added, library rebuilt',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(3);
      _seedV3(schema.rawDatabase);
      final db = DatabaseConnectionManager.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 10);

      final ratings = await db.customSelect('SELECT type, tmdb_id FROM user_ratings ORDER BY type').get();
      // The v3 fixture's season rating is gone; the movie and show ratings survived the re-key.
      expect(ratings.map((r) => (r.read<String>('type'), r.read<int>('tmdb_id'))), [('movie', _movieX.tmdb), ('show', _showB.tmdb)]);
      final history = await db.customSelect('SELECT COUNT(*) AS n FROM history_items').getSingle();
      expect(history.read<int>('n'), greaterThan(0));
      // The 3 → 4 step put the table there under its v6 name; 5 → 6's IF NOT EXISTS left it alone and
      // 8 → 9 renamed it.
      final favorites = await db.customSelect('SELECT COUNT(*) AS n FROM favorite_items').getSingle();
      expect(favorites.read<int>('n'), 0);
      final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map(
        (t) => t.read<String>('name'),
      );
      expect(tables, isNot(contains('recommended_items')));
      expect(tables, isNot(contains('posters')));
      expect(tables, isNot(contains('show_progress_items')));
      expect(tables, isNot(contains('movie_summaries')));
      // The v3 episode summary travelled through the v4–v6 tables onto the episode row, and the 9 → 10
      // step turned its local-midnight seconds into a date in this zone.
      final pilot = await db.customSelect('SELECT * FROM episodes WHERE season = 1 AND episode = 1').getSingle();
      expect(pilot.read<int>('show_tmdb_id'), _showA.tmdb);
      expect(pilot.read<String?>('title'), 'Pilot');
      expect(pilot.read<String?>('overview'), 'Pilot overview');
      final airedLocal = DateTime.fromMillisecondsSinceEpoch(1600000000 * 1000);
      expect(
        pilot.read<String?>('air_date'),
        '${airedLocal.year}-${airedLocal.month.toString().padLeft(2, '0')}-${airedLocal.day.toString().padLeft(2, '0')}',
      );
      final second = await db.customSelect('SELECT air_date FROM episodes WHERE season = 1 AND episode = 2').getSingle();
      expect(second.read<String?>('air_date'), isNull);
      // Every catalogue row is referenced (the fixture has no browse residue), none has a snapshot yet.
      final shows = await db.customSelect('SELECT tmdb_id, fetched_at FROM shows ORDER BY tmdb_id').get();
      expect(shows.map((s) => s.read<int>('tmdb_id')), [_showA.tmdb, _showB.tmdb, _dupFresh.tmdb]);
      expect(shows.map((s) => s.read<int?>('fetched_at')), everyElement(isNull));
      // Show B was dropped in v3; Show A has a check-in on S1E2 but its only aired episode is the pilot.
      final states = await db.customSelect('SELECT show_tmdb_id, status FROM show_states ORDER BY show_tmdb_id').get();
      expect(
        {for (final s in states) s.read<int>('show_tmdb_id'): s.read<String>('status')},
        {_showA.tmdb: 'watching', _showB.tmdb: 'dropped', _dupFresh.tmdb: 'watching'},
      );
      // The 3 → 4 step's createAll() already built the outbox too; 7 → 8's IF NOT EXISTS left it alone.
      final outbox = await db.customSelect('SELECT COUNT(*) AS n FROM tmdb_sync_outbox').getSingle();
      expect(outbox.read<int>('n'), 0);
      expect((await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 10);
    },
  );

  test('only upgrades made entirely of listed steps run in place', () {
    expect(DatabaseConnectionManager.currentSchemaVersion, 10);
    expect(DatabaseConnectionManager.nonDestructiveMigrations, {(3, 4), (4, 5), (5, 6), (6, 7), (7, 8), (8, 9), (9, 10)});
    expect(DatabaseConnectionManager.canMigrateInPlace(3, 4), isTrue);
    expect(DatabaseConnectionManager.canMigrateInPlace(4, 5), isTrue);
    expect(DatabaseConnectionManager.canMigrateInPlace(5, 6), isTrue);
    expect(DatabaseConnectionManager.canMigrateInPlace(6, 7), isTrue);
    expect(DatabaseConnectionManager.canMigrateInPlace(7, 8), isTrue);
    expect(DatabaseConnectionManager.canMigrateInPlace(8, 9), isTrue);
    expect(DatabaseConnectionManager.canMigrateInPlace(9, 10), isTrue);
    expect(DatabaseConnectionManager.canMigrateInPlace(3, 10), isTrue);
    expect(DatabaseConnectionManager.canMigrateInPlace(2, 10), isFalse);
    expect(DatabaseConnectionManager.canMigrateInPlace(10, 11), isFalse);
    expect(DatabaseConnectionManager.canMigrateInPlace(10, 9), isFalse);
    expect(DatabaseConnectionManager.canMigrateInPlace(10, 10), isFalse);
  });

  /// Any other version change must leave the database exactly like a first install: every object
  /// in the file dropped — including tables/views/indexes that no longer exist in the Dart schema —
  /// and the current schema recreated empty.
  group('any other version change, destructively', () {
    late Database raw;

    // `closeUnderlyingOnClose: false` lets the same in-memory database survive a drift
    // close/reopen, standing in for the on-device file across an app update.
    NativeDatabase executor() => NativeDatabase.opened(raw, closeUnderlyingOnClose: false);

    setUp(() {
      raw = sqlite3.openInMemory();
    });

    tearDown(() {
      raw.close();
    });

    Future<Set<String>> objectNames(DatabaseConnectionManager db, String type) async {
      final result = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = '$type' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'")
          .get();
      return result.map((r) => r.read<String>('name')).toSet();
    }

    test('a schema version bump wipes and recreates the database like a fresh install', () async {
      final current = DatabaseConnectionManager.forTesting(executor());
      // Rows in real tables, plus stray objects that are absent from the current Dart schema — the
      // old `allTables`-based wipe left these behind.
      await current.customStatement("INSERT INTO caches (key, customData, synchronized_at) VALUES ('key', 'value', 0)");
      await current.customStatement(
        "INSERT INTO history_items (type, tmdb_id, season, episode, action, watched_at) VALUES ('movie', 1, 0, 0, 'watch', 0)",
      );
      await current.customStatement('CREATE TABLE legacy_table (id INTEGER PRIMARY KEY, name TEXT)');
      await current.customStatement("INSERT INTO legacy_table (name) VALUES ('old')");
      await current.customStatement('CREATE INDEX legacy_index ON legacy_table (name)');
      await current.customStatement('CREATE VIEW legacy_view AS SELECT name FROM legacy_table');
      await current.close();

      final next = _NextVersionDatabase(executor());
      addTearDown(next.close);

      final tables = await objectNames(next, 'table');
      expect(tables, isNot(contains('legacy_table')));
      expect(await objectNames(next, 'index'), isNot(contains('legacy_index')));
      expect(await objectNames(next, 'view'), isNot(contains('legacy_view')));

      for (final table in next.allTables) {
        final name = table.actualTableName;
        expect(tables, contains(name));
        final count = await next.customSelect('SELECT COUNT(*) AS row_count FROM "$name"').getSingle();
        expect(count.read<int>('row_count'), 0, reason: 'table $name should be empty after the wipe');
      }

      final version = await next.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), _NextVersionDatabase.version);
    });

    test('a downgrade also wipes and recreates the database', () async {
      final current = DatabaseConnectionManager.forTesting(executor());
      await current.customStatement("INSERT INTO caches (key, customData, synchronized_at) VALUES ('key', 'value', 0)");
      await current.close();

      final older = _PreviousVersionDatabase(executor());
      addTearDown(older.close);

      final count = await older.customSelect('SELECT COUNT(*) AS row_count FROM caches').getSingle();
      expect(count.read<int>('row_count'), 0);

      final version = await older.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), _PreviousVersionDatabase.version);
    });
  });
}
