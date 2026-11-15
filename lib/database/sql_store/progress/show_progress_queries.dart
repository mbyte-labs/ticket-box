import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/show_progress_order_by.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/common/model/up_next_to_watch_order_by.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_list_item.dart';

/// Which watched episode the "up next" pointer continues from.
enum NextEpisodeMode {
  /// Next = the first unwatched episode after the LATEST (highest-positioned) episode the user has
  /// watched; gaps earlier in the show are skipped.
  afterLatestAiredWatched,

  /// Next = the first unwatched episode after the MOST RECENTLY watched episode (by `watchedAt`).
  afterMostRecentlyWatched,
}

/// A show's progress counts. Counts *episodes*, never plays: ten rewatches of one episode read as
/// one watched.
class ShowCounts {
  /// Aired, non-special episodes.
  final int aired;

  /// Aired, non-special episodes with a play — what completion compares with [aired].
  final int watchedAired;

  /// Non-special episodes with a play, aired or not.
  final int watched;

  /// Non-special episodes in the catalogue.
  final int total;

  /// Whether the log holds any episode play of the show, specials included.
  final bool anyPlay;

  /// The latest play, specials included; null without any.
  final DateTime? lastWatchedAt;

  const ShowCounts({
    required this.aired,
    required this.watchedAired,
    required this.watched,
    required this.total,
    required this.anyPlay,
    required this.lastWatchedAt,
  });

  static const ShowCounts none = ShowCounts(aired: 0, watchedAired: 0, watched: 0, total: 0, anyPlay: false, lastWatchedAt: null);

  /// Every aired episode is watched (and something has aired).
  bool get isComplete => aired > 0 && watchedAired >= aired;
}

/// One season's counts, for display: specials count their own episodes here.
class SeasonCounts {
  final int season;
  final int aired;
  final int watchedAired;
  final int watched;
  final int total;

  const SeasonCounts({required this.season, required this.aired, required this.watchedAired, required this.watched, required this.total});
}

/// The episode a show continues with.
class NextEpisode {
  final int showTmdbId;
  final int season;
  final int episode;
  final String? title;

  /// `YYYY-MM-DD`, or null when unscheduled.
  final String? airDate;
  final String? episodeType;

  /// Whether it has aired by the query's "today"; the pick itself ignores airedness.
  final bool aired;

  const NextEpisode({
    required this.showTmdbId,
    required this.season,
    required this.episode,
    required this.title,
    required this.airDate,
    required this.episodeType,
    required this.aired,
  });
}

/// One Up Next row: the show's next episode plus what the tile renders.
class UpNextRow {
  final NextEpisode next;
  final String showTitle;
  final String? showPosterPath;
  final String? seasonPosterPath;
  final DateTime? lastWatchedAt;

  const UpNextRow({
    required this.next,
    required this.showTitle,
    required this.showPosterPath,
    required this.seasonPosterPath,
    required this.lastWatchedAt,
  });
}

/// Progress, next episode and the Up Next / Show Progress lists, derived at query time from
/// `episodes`, `history_items` and `show_states`. Nothing here is stored.
///
/// The completion predicate is spliced verbatim into every query: an episode counts when it is not
/// a special, has an air date and that date is on or before the caller's "today" (`YYYY-MM-DD`,
/// computed in Dart from the device clock and bound — never `date('now')` in SQL). An unknown date
/// never reads as aired, so a show with one undated announced episode can still reach "watched".
/// The log is never joined: a play is tested with `EXISTS`, so rewatches cannot inflate a count.
class ShowProgressQueries {
  final DatabaseConnectionManager _db;

  ShowProgressQueries() : _db = DatabaseConnectionInitializer.getConnection();

  /// Today as the queries bind it.
  static String today([DateTime? now]) {
    final date = now ?? DateTime.now();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// `?2` is today.
  static const String _airedSql = 'e.season > 0 AND e.air_date IS NOT NULL AND e.air_date <= ?2';

  static const String _playedSql =
      "EXISTS (SELECT 1 FROM history_items h WHERE h.type = 'episode' AND h.tmdb_id = e.show_tmdb_id "
      'AND h.season = e.season AND h.episode = e.episode)';

  Future<ShowCounts> showCounts(int showTmdbId, {DateTime? now}) async {
    final counts = await _db
        .customSelect(
          '''
      SELECT
        COALESCE(SUM(CASE WHEN $_airedSql THEN 1 ELSE 0 END), 0) AS aired,
        COALESCE(SUM(CASE WHEN $_airedSql AND $_playedSql THEN 1 ELSE 0 END), 0) AS watched_aired,
        COALESCE(SUM(CASE WHEN e.season > 0 AND $_playedSql THEN 1 ELSE 0 END), 0) AS watched,
        COALESCE(SUM(CASE WHEN e.season > 0 THEN 1 ELSE 0 END), 0) AS total
      FROM episodes e WHERE e.show_tmdb_id = ?1''',
          variables: [Variable.withInt(showTmdbId), Variable.withString(today(now))],
          readsFrom: {_db.episodes, _db.historyItems},
        )
        .getSingle();
    final plays = await _db
        .customSelect(
          '''
      SELECT COUNT(*) AS n, MAX(watched_at) AS last_watched_at FROM history_items
      WHERE type = 'episode' AND tmdb_id = ?1''',
          variables: [Variable.withInt(showTmdbId)],
          readsFrom: {_db.historyItems},
        )
        .getSingle();
    return ShowCounts(
      aired: counts.read<int>('aired'),
      watchedAired: counts.read<int>('watched_aired'),
      watched: counts.read<int>('watched'),
      total: counts.read<int>('total'),
      anyPlay: plays.read<int>('n') > 0,
      lastWatchedAt: plays.read<DateTime?>('last_watched_at'),
    );
  }

  /// Per-season counts of one show, keyed by season number; a season with no episode rows is absent.
  Future<Map<int, SeasonCounts>> seasonCounts(int showTmdbId, {DateTime? now}) async {
    const aired = 'e.air_date IS NOT NULL AND e.air_date <= ?2';
    final rows = await _db
        .customSelect(
          '''
      SELECT e.season,
        SUM(CASE WHEN $aired THEN 1 ELSE 0 END) AS aired,
        SUM(CASE WHEN $aired AND $_playedSql THEN 1 ELSE 0 END) AS watched_aired,
        SUM(CASE WHEN $_playedSql THEN 1 ELSE 0 END) AS watched,
        COUNT(*) AS total
      FROM episodes e WHERE e.show_tmdb_id = ?1 GROUP BY e.season ORDER BY e.season''',
          variables: [Variable.withInt(showTmdbId), Variable.withString(today(now))],
          readsFrom: {_db.episodes, _db.historyItems},
        )
        .get();
    return {
      for (final row in rows)
        row.read<int>('season'): SeasonCounts(
          season: row.read<int>('season'),
          aired: row.read<int>('aired'),
          watchedAired: row.read<int>('watched_aired'),
          watched: row.read<int>('watched'),
          total: row.read<int>('total'),
        ),
    };
  }

  /// The first non-special episode strictly after the anchor [mode] picks, with no play. After
  /// S1E2 the answer is S1E3, never S1E1; a finished show has none; airedness is ignored and
  /// reported as a flag.
  Future<NextEpisode?> nextEpisode(int showTmdbId, NextEpisodeMode mode, {DateTime? now}) async {
    final row = await _db
        .customSelect(
          '''
      SELECT e.show_tmdb_id, e.season, e.episode, e.title, e.air_date, e.episode_type,
        CASE WHEN $_airedSql THEN 1 ELSE 0 END AS aired
      FROM episodes e
      WHERE e.show_tmdb_id = ?1 AND e.season > 0
        AND (e.season * 10000 + e.episode) > (${_anchorSql(mode)})
        AND NOT $_playedSql
      ORDER BY e.season, e.episode LIMIT 1''',
          variables: [Variable.withInt(showTmdbId), Variable.withString(today(now))],
          readsFrom: {_db.episodes, _db.historyItems},
        )
        .getSingleOrNull();
    return row == null ? null : _nextEpisode(row);
  }

  /// The Up Next list: the next episode of every followed (non-dropped) show that has one, with
  /// the title and artwork paths its tile renders. A finished show with nothing announced has no
  /// next episode and so no row; one with an unaired next episode is listed unless
  /// [displayAiredOnly] hides it.
  Future<List<UpNextRow>> upNext({
    required bool onlyWithReleaseDate,
    required bool displayAiredOnly,
    required UpNextToWatchOrderBy orderBy,
    required OrderType orderType,
    required NextEpisodeMode mode,
    DateTime? now,
  }) async {
    final filter = displayAiredOnly
        ? 'AND c.air_date IS NOT NULL AND c.air_date <= ?2'
        : onlyWithReleaseDate
        ? 'AND c.air_date IS NOT NULL'
        : '';
    final direction = orderType == OrderType.ascending ? 'ASC' : 'DESC';
    final primary = switch (orderBy) {
      UpNextToWatchOrderBy.lastWatched => 'lw.last_watched_at',
      UpNextToWatchOrderBy.episodeReleaseDate => 'c.air_date',
      UpNextToWatchOrderBy.showName => 'lower(s.title)',
    };
    final rows = await _db
        .customSelect(
          '''
      WITH anchors AS (
        SELECT h.tmdb_id AS show_id, ${_anchorExpressionSql(mode)} AS pos
        FROM history_items h WHERE h.type = 'episode' AND h.season > 0 GROUP BY h.tmdb_id),
      cand AS (
        SELECT e.show_tmdb_id, e.season, e.episode, e.title, e.air_date, e.episode_type,
          ROW_NUMBER() OVER (PARTITION BY e.show_tmdb_id ORDER BY e.season, e.episode) AS rn
        FROM episodes e JOIN anchors a ON a.show_id = e.show_tmdb_id
        WHERE e.season > 0 AND (e.season * 10000 + e.episode) > a.pos AND NOT $_playedSql)
      SELECT c.show_tmdb_id, c.season, c.episode, c.title, c.air_date, c.episode_type,
        CASE WHEN c.air_date IS NOT NULL AND c.air_date <= ?2 THEN 1 ELSE 0 END AS aired,
        s.title AS show_title, s.poster_path AS show_poster_path, se.poster_path AS season_poster_path, lw.last_watched_at
      FROM cand c
      JOIN show_states st ON st.show_tmdb_id = c.show_tmdb_id AND st.status <> 'dropped'
      JOIN shows s ON s.tmdb_id = c.show_tmdb_id
      LEFT JOIN seasons se ON se.show_tmdb_id = c.show_tmdb_id AND se.season = c.season
      LEFT JOIN (SELECT tmdb_id, MAX(watched_at) AS last_watched_at FROM history_items WHERE type = 'episode' GROUP BY tmdb_id) lw
        ON lw.tmdb_id = c.show_tmdb_id
      WHERE c.rn = 1 $filter
      ORDER BY $primary $direction, lower(s.title), c.season, c.episode''',
          variables: [const Variable(0), Variable.withString(today(now))],
          readsFrom: {_db.episodes, _db.historyItems, _db.showStates, _db.shows, _db.seasons},
        )
        .get();
    return [
      for (final row in rows)
        UpNextRow(
          next: _nextEpisode(row),
          showTitle: row.read<String?>('show_title') ?? '',
          showPosterPath: row.read<String?>('show_poster_path'),
          seasonPosterPath: row.read<String?>('season_poster_path'),
          lastWatchedAt: row.read<DateTime?>('last_watched_at'),
        ),
    ];
  }

  /// Every followed (non-dropped) show with its counts — the Show Progress page and the stats
  /// completion figures. [hideCompleted] leaves out the shows whose aired episodes are all watched.
  Future<List<ShowProgressListItem>> listing({
    required bool hideCompleted,
    required ShowProgressOrderBy orderBy,
    required OrderType orderType,
    DateTime? now,
  }) async {
    final direction = orderType == OrderType.ascending ? 'ASC' : 'DESC';
    final primary = switch (orderBy) {
      ShowProgressOrderBy.lastWatched => 'last_watched_at',
      ShowProgressOrderBy.showName => 'lower(title)',
      ShowProgressOrderBy.progress => 'CASE WHEN aired = 0 THEN 0 ELSE completed * 1.0 / aired END',
    };
    final rows = await _db
        .customSelect(
          '''
      SELECT * FROM (
        SELECT s.tmdb_id AS show_tmdb_id, s.title, s.poster_path, st.status,
          (SELECT COUNT(*) FROM episodes e WHERE e.show_tmdb_id = s.tmdb_id AND $_airedSql) AS aired,
          (SELECT COUNT(*) FROM episodes e WHERE e.show_tmdb_id = s.tmdb_id AND $_airedSql AND $_playedSql) AS completed,
          (SELECT MAX(h.watched_at) FROM history_items h WHERE h.type = 'episode' AND h.tmdb_id = s.tmdb_id) AS last_watched_at
        FROM show_states st JOIN shows s ON s.tmdb_id = st.show_tmdb_id
        WHERE st.status <> 'dropped')
      ${hideCompleted ? 'WHERE completed < aired OR aired = 0' : ''}
      ORDER BY $primary $direction, lower(title)''',
          variables: [const Variable(0), Variable.withString(today(now))],
          readsFrom: {_db.episodes, _db.historyItems, _db.showStates, _db.shows},
        )
        .get();
    return [
      for (final row in rows)
        ShowProgressListItem(
          showTmdbId: row.read<int>('show_tmdb_id'),
          title: row.read<String?>('title') ?? '',
          posterPath: row.read<String?>('poster_path'),
          status: ShowWatchStatus.fromName(row.read<String>('status')),
          aired: row.read<int>('aired'),
          completed: row.read<int>('completed'),
          lastWatchedAt: row.read<DateTime?>('last_watched_at'),
        ),
    ];
  }

  /// The anchor as a scalar subquery over one show (`?1`).
  static String _anchorSql(NextEpisodeMode mode) {
    return "SELECT ${_anchorExpressionSql(mode)} FROM history_items h WHERE h.type = 'episode' AND h.tmdb_id = ?1 AND h.season > 0";
  }

  /// The position (`season * 10000 + episode`) the search continues from, as an aggregate over
  /// the `h` rows in scope. Mode B packs the instant in front of the position so the most recent
  /// play wins, ties broken by position; the modulo peels the position back out.
  static String _anchorExpressionSql(NextEpisodeMode mode) {
    return switch (mode) {
      NextEpisodeMode.afterLatestAiredWatched => 'MAX(h.season * 10000 + h.episode)',
      NextEpisodeMode.afterMostRecentlyWatched => 'MAX(h.watched_at * 100000000 + h.season * 10000 + h.episode) % 100000000',
    };
  }

  NextEpisode _nextEpisode(QueryRow row) {
    return NextEpisode(
      showTmdbId: row.read<int>('show_tmdb_id'),
      season: row.read<int>('season'),
      episode: row.read<int>('episode'),
      title: row.read<String?>('title'),
      airDate: row.read<String?>('air_date'),
      episodeType: row.read<String?>('episode_type'),
      aired: row.read<int>('aired') == 1,
    );
  }
}
