import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/common/model/filter/page_details.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/paged_response.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/watched_history_item.dart';

class HistoryRepo {
  static final _log = Logger('[Repository] HistoryRepo');
  final DatabaseConnectionManager _connectionManager;

  HistoryRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Upserts a row that already has an id (migrations, tests). New plays go through [insertNew].
  Future<void> insert(HistoryEntity item) async {
    await _connectionManager.into(_connectionManager.historyItems).insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> insertAll(List<HistoryEntity> items) async {
    if (items.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.historyItems, items.map((e) => e.toInsertable()).toList());
    });
  }

  /// Records a new play, letting the database assign the id. Returns that id.
  Future<int> insertNew(NewHistoryEntry entry) async {
    return await _connectionManager.into(_connectionManager.historyItems).insert(_companion(entry));
  }

  /// Records many new plays in one transaction (marking a season or a show as watched).
  Future<void> insertAllNew(List<NewHistoryEntry> entries) async {
    if (entries.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAll(_connectionManager.historyItems, entries.map(_companion).toList());
    });
  }

  HistoryItemsCompanion _companion(NewHistoryEntry entry) {
    return HistoryItemsCompanion.insert(
      type: entry.type,
      tmdbId: entry.tmdbId,
      season: entry.season,
      episode: entry.episode,
      action: entry.action,
      watchedAt: entry.watchedAt,
    );
  }

  Future<void> deleteMovie(int tmdbId) async {
    _log.fine('Deleting movie $tmdbId from repository');
    await (_connectionManager.delete(
      _connectionManager.historyItems,
    )..where((row) => row.type.equalsValue(ItemType.movie) & row.tmdbId.equals(tmdbId))).go();
  }

  Future<void> deleteByShowId(int showTmdbId) async {
    _log.fine('Deleting episodes for show $showTmdbId from repository');
    await (_connectionManager.delete(
      _connectionManager.historyItems,
    )..where((row) => row.type.equalsValue(ItemType.episode) & row.tmdbId.equals(showTmdbId))).go();
  }

  /// Deletes every history entry of one season's episodes - the delete twin of [getForSeason].
  Future<void> deleteBySeason(int showTmdbId, int season) async {
    _log.fine('Deleting episodes for show $showTmdbId season $season from repository');
    await (_connectionManager.delete(
      _connectionManager.historyItems,
    )..where((row) => row.type.equalsValue(ItemType.episode) & row.tmdbId.equals(showTmdbId) & row.season.equals(season))).go();
  }

  Future<void> deleteEpisode(int showTmdbId, int season, int episode) async {
    _log.fine('Deleting show $showTmdbId season $season episode $episode from repository');
    await (_connectionManager.delete(_connectionManager.historyItems)..where(
          (row) =>
              row.type.equalsValue(ItemType.episode) &
              row.tmdbId.equals(showTmdbId) &
              row.season.equals(season) &
              row.episode.equals(episode),
        ))
        .go();
  }

  Future<void> deleteByHistoryId(int id) async {
    await (_connectionManager.delete(_connectionManager.historyItems)..where((item) => item.historyId.equals(id))).go();
  }

  Future<void> deleteAll() async {
    await _connectionManager.delete(_connectionManager.historyItems).go();
  }

  Future<HistoryEntity?> getByHistoryId(int id) async {
    final query = _connectionManager.select(_connectionManager.historyItems)..where((item) => item.historyId.equals(id));
    return await query.map((row) => row).getSingleOrNull();
  }

  /// Every history entry, newest first. The one-shot twin of [listenForChanges].
  Future<List<HistoryEntity>> getAll() async {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return await query.map((row) => row).get();
  }

  /// Every play (one row per watch, so a rewatched episode comes back once per watch) whose
  /// `watchedAt` is before [timestamp], of the given [actions] and [types], newest first. [paged]
  /// is 0 based.
  ///
  /// [timestamp] is an exclusive upper bound on `watchedAt`. Pass "now" so that the future dated
  /// rows [getCurrentCheckInItems] treats as an in-progress check-in stay out of the history.
  ///
  /// The `historyId` tie breaker is not cosmetic: marking a whole season as watched writes the
  /// same `watchedAt` to every episode, and without a total order SQLite is free to return one of
  /// those rows on two different LIMIT/OFFSET pages while dropping another entirely.
  Future<PagedResponse<List<HistoryEntity>>> getPlays(
    int timestamp,
    List<HistoryAction> actions,
    List<ItemType> types,
    PageDetails paged,
  ) async {
    if (actions.isEmpty || types.isEmpty) {
      // `isInValues([])` renders as `IN ()`, which SQLite rejects as a syntax error.
      return PagedResponse(page: paged.page, pageSize: paged.pageSize, totalPages: 1, data: []);
    }
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc();
    final table = _connectionManager.historyItems;
    final filter = table.watchedAt.isSmallerThanValue(date) & table.action.isInValues(actions) & table.type.isInValues(types);
    final countExp = table.historyId.count();
    final countQuery = _connectionManager.selectOnly(table)
      ..addColumns([countExp])
      ..where(filter);
    final countRow = await countQuery.getSingle();
    final totalItems = countRow.read(countExp)!;
    if (totalItems == 0) {
      return PagedResponse(page: paged.page, pageSize: paged.pageSize, totalPages: 1, data: []);
    }
    final query = _connectionManager.select(table)
      ..where((_) => filter)
      ..orderBy([
        (t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.historyId, mode: OrderingMode.desc),
      ])
      ..limit(paged.pageSize, offset: paged.page * paged.pageSize);
    final result = await query.get();
    return PagedResponse(page: paged.page, pageSize: paged.pageSize, totalPages: (totalItems / paged.pageSize).ceil(), data: result);
  }

  /// The `(type, watchedAt)` of every play, for the stats aggregations, optionally only those in
  /// `[from, before)`.
  ///
  /// Future dated rows (the in-progress check-ins [getCurrentCheckInItems] looks for) are
  /// excluded - a play does not count until the check-in actually ends.
  Future<List<(ItemType, DateTime)>> getAllWatchInstants({DateTime? from, DateTime? before}) async {
    final table = _connectionManager.historyItems;
    final query = _connectionManager.selectOnly(table)
      ..addColumns([table.type, table.watchedAt])
      ..where(_playedWithin(from, before));
    final rows = await query.get();
    return rows.map((row) => (row.readWithConverter(table.type)!, row.read(table.watchedAt)!)).toList();
  }

  /// Plays and last-watched instant per movie and per show, from every play up to now, or only
  /// the plays in `[from, before)`.
  ///
  /// Episode plays are rolled up to their show, which is exactly how the v3 sync backend used to compute a
  /// show's `plays`. One GROUP BY for the whole library — the stats page's "most rewatched".
  Future<List<WatchedAggregate>> getPlayAggregates({DateTime? from, DateTime? before}) async {
    final table = _connectionManager.historyItems;
    final plays = table.historyId.count();
    final lastWatchedAt = table.watchedAt.max();
    final query = _connectionManager.selectOnly(table)
      ..addColumns([table.type, table.tmdbId, plays, lastWatchedAt])
      ..where(_playedWithin(from, before))
      ..groupBy([table.type, table.tmdbId]);
    final rows = await query.get();
    return rows.map((row) {
      final rowType = row.readWithConverter(table.type)!;
      return WatchedAggregate(
        type: rowType == ItemType.movie ? ItemType.movie : ItemType.show,
        tmdbId: row.read(table.tmdbId)!,
        plays: row.read(plays)!,
        lastWatchedAt: row.read(lastWatchedAt)!,
      );
    }).toList();
  }

  /// Minutes watched per type, summing each play's runtime: movies from `movies`,
  /// episodes from `Episodes` with the show's regular runtime as fallback. Plays whose runtime is
  /// unknown contribute nothing. Future dated check-ins are excluded, as is everything outside
  /// `[from, before)` when given.
  Future<({int movies, int episodes})> getWatchedMinutes({DateTime? from, DateTime? before}) async {
    final row = await _connectionManager
        .customSelect(
          '''
      SELECT
        (SELECT COALESCE(SUM(COALESCE(ms.runtime, 0)), 0) FROM history_items h
           LEFT JOIN movies ms ON ms.tmdb_id = h.tmdb_id
           WHERE h.type = 'movie' AND $_playedWithinSql)
        AS movie_minutes,
        (SELECT COALESCE(SUM(COALESCE(e.runtime, ss.runtime, 0)), 0) FROM history_items h
           LEFT JOIN episodes e ON e.show_tmdb_id = h.tmdb_id AND e.season = h.season AND e.episode = h.episode
           LEFT JOIN shows ss ON ss.tmdb_id = h.tmdb_id
           WHERE h.type = 'episode' AND $_playedWithinSql)
        AS episode_minutes''',
          variables: _playedWithinVariables(from, before),
          readsFrom: {_connectionManager.historyItems, _connectionManager.movies, _connectionManager.episodes, _connectionManager.shows},
        )
        .getSingle();
    return (movies: row.read<int>('movie_minutes'), episodes: row.read<int>('episode_minutes'));
  }

  /// Minutes watched per show, keyed by the show's TMDB id: the episode half of
  /// [getWatchedMinutes] split per show, with the same runtime fallbacks and the same optional
  /// `[from, before)` window. A show whose plays all have an unknown runtime comes back with 0.
  /// Future dated check-ins are excluded.
  Future<Map<int, int>> getEpisodeMinutesPerShow({DateTime? from, DateTime? before}) async {
    final rows = await _connectionManager
        .customSelect(
          '''
      SELECT h.tmdb_id AS show_tmdb_id, COALESCE(SUM(COALESCE(e.runtime, ss.runtime, 0)), 0) AS minutes
        FROM history_items h
        LEFT JOIN episodes e ON e.show_tmdb_id = h.tmdb_id AND e.season = h.season AND e.episode = h.episode
        LEFT JOIN shows ss ON ss.tmdb_id = h.tmdb_id
        WHERE h.type = 'episode' AND $_playedWithinSql
        GROUP BY h.tmdb_id''',
          variables: _playedWithinVariables(from, before),
          readsFrom: {_connectionManager.historyItems, _connectionManager.episodes, _connectionManager.shows},
        )
        .get();
    return {for (final row in rows) row.read<int>('show_tmdb_id'): row.read<int>('minutes')};
  }

  /// How many distinct episodes (show, season, episode) have at least one play, optionally only
  /// counting the plays in `[from, before)` - the stats page's "Episodes" for one year, where the
  /// progress table's completed counts (which have no dates) cannot answer. A rewatched episode
  /// counts once. Future dated check-ins are excluded.
  Future<int> countDistinctEpisodesWatched({DateTime? from, DateTime? before}) async {
    final row = await _connectionManager
        .customSelect(
          '''
      SELECT COUNT(*) AS episodes FROM (
        SELECT DISTINCT h.tmdb_id, h.season, h.episode FROM history_items h
          WHERE h.type = 'episode' AND $_playedWithinSql)''',
          variables: _playedWithinVariables(from, before),
          readsFrom: {_connectionManager.historyItems},
        )
        .getSingle();
    return row.read<int>('episodes');
  }

  /// The oldest play on record (or the oldest in `[from, before)`), or null without history.
  /// Future dated check-ins are excluded, and a tie on `watchedAt` goes to the lower id so the
  /// answer is stable across runs.
  Future<HistoryEntity?> getFirstPlay({DateTime? from, DateTime? before}) async {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => _playedWithin(from, before))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt), (t) => OrderingTerm(expression: t.historyId)])
      ..limit(1);
    return await query.getSingleOrNull();
  }

  /// The stats window of the Drift queries: every play up to now (future dated check-ins are
  /// not plays yet), narrowed to `[from, before)` when either bound is given.
  Expression<bool> _playedWithin(DateTime? from, DateTime? before) {
    final table = _connectionManager.historyItems;
    Expression<bool> where = table.watchedAt.isSmallerOrEqualValue(DateTime.now().toUtc());
    if (from != null) {
      where = where & table.watchedAt.isBiggerOrEqualValue(from);
    }
    if (before != null) {
      where = where & table.watchedAt.isSmallerThanValue(before);
    }
    return where;
  }

  /// The same window for the raw SQL queries, over the `h` alias of `history_items`; the bounds
  /// are the three variables of [_playedWithinVariables].
  static const _playedWithinSql = 'h.watched_at <= ?1 AND h.watched_at >= ?2 AND h.watched_at < ?3';

  /// `?1` now, `?2` the lower and `?3` the exclusive upper bound, as the unix seconds Drift
  /// stores; a missing bound binds the epoch / the far future rather than branching the SQL.
  static List<Variable<int>> _playedWithinVariables(DateTime? from, DateTime? before) {
    return [
      Variable<int>(_unixSeconds(DateTime.now().toUtc())),
      Variable<int>(from == null ? 0 : _unixSeconds(from)),
      Variable<int>(before == null ? _farFutureSeconds : _unixSeconds(before)),
    ];
  }

  /// Year 3000, well past any check-in a user could date.
  static const _farFutureSeconds = 32503680000;

  static int _unixSeconds(DateTime instant) => instant.toUtc().millisecondsSinceEpoch ~/ 1000;

  Future<List<HistoryEntity>> getForMovie(int tmdbId) async {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => item.tmdbId.equals(tmdbId) & item.type.equalsValue(ItemType.movie))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return await query.map((row) => row).get();
  }

  Future<List<HistoryEntity>> getForEpisode(int showTmdbId, int season, int episode) async {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where(
        (item) =>
            item.tmdbId.equals(showTmdbId) &
            item.type.equalsValue(ItemType.episode) &
            item.season.equals(season) &
            item.episode.equals(episode),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return await query.map((row) => row).get();
  }

  /// Every history entry for the episodes of one season, newest first.
  Future<List<HistoryEntity>> getForSeason(int showTmdbId, int season) async {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => item.tmdbId.equals(showTmdbId) & item.type.equalsValue(ItemType.episode) & item.season.equals(season))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return await query.map((row) => row).get();
  }

  /// The newest watched episode of every show, keyed by the show's TMDB id.
  ///
  /// One `GROUP BY tmdbId` query for the whole library. The non-aggregated `season`/`episode`
  /// columns come from the row holding `MAX(watchedAt)`; that bare-column-with-max() behaviour is
  /// SQLite specific, but guaranteed by it.
  ///
  /// Future dated rows (the in-progress check-ins [getCurrentCheckInItems] looks for) are
  /// excluded - an episode is not "last watched" until the check-in actually ends.
  Future<Map<int, WatchedHistoryItem>> getLatestEpisodeEntryPerShow() async {
    final table = _connectionManager.historyItems;
    final now = DateTime.now().toUtc();
    final lastWatchedAt = table.watchedAt.max();
    final query = _connectionManager.selectOnly(table)
      ..addColumns([table.tmdbId, table.season, table.episode, lastWatchedAt])
      ..where(table.type.equalsValue(ItemType.episode) & table.watchedAt.isSmallerOrEqualValue(now))
      ..groupBy([table.tmdbId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(table.tmdbId)!: WatchedHistoryItem(
          type: ItemType.episode,
          tmdbId: row.read(table.tmdbId)!,
          season: row.read(table.season)!,
          episode: row.read(table.episode)!,
          lastWatchedAt: row.read(lastWatchedAt)!,
        ),
    };
  }

  /// Every history entry for every episode of one show, newest first.
  Future<List<HistoryEntity>> getForShow(int showTmdbId) async {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => item.tmdbId.equals(showTmdbId) & item.type.equalsValue(ItemType.episode))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return await query.map((row) => row).get();
  }

  /// The TMDB ids of every movie with at least one play.
  /// The `(season, episode)` positions of a show with at least one play, specials included — the
  /// idempotent bulk mark skips them, the grids mark them.
  Future<Set<(int, int)>> getWatchedPositions(int showTmdbId) async {
    final rows = await _connectionManager
        .customSelect(
          "SELECT DISTINCT season, episode FROM history_items WHERE type = 'episode' AND tmdb_id = ?1",
          variables: [Variable.withInt(showTmdbId)],
          readsFrom: {_connectionManager.historyItems},
        )
        .get();
    return {for (final row in rows) (row.read<int>('season'), row.read<int>('episode'))};
  }

  /// [getWatchedPositions] for many shows at once, keyed by show id; a show with no play is absent.
  Future<Map<int, Set<(int, int)>>> getWatchedPositionsForShows(Iterable<int> showTmdbIds) async {
    final ids = showTmdbIds.toSet().toList();
    if (ids.isEmpty) {
      return {};
    }
    final result = <int, Set<(int, int)>>{};
    for (final chunk in ids.chunked(500)) {
      final rows = await _connectionManager
          .customSelect(
            "SELECT DISTINCT tmdb_id, season, episode FROM history_items WHERE type = 'episode' AND tmdb_id IN (${chunk.map((_) => '?').join(', ')})",
            variables: [for (final id in chunk) Variable.withInt(id)],
            readsFrom: {_connectionManager.historyItems},
          )
          .get();
      for (final row in rows) {
        result.putIfAbsent(row.read<int>('tmdb_id'), () => {}).add((row.read<int>('season'), row.read<int>('episode')));
      }
    }
    return result;
  }

  Future<Set<int>> getWatchedMovieIds() async {
    final table = _connectionManager.historyItems;
    final query = _connectionManager.selectOnly(table, distinct: true)
      ..addColumns([table.tmdbId])
      ..where(table.type.equalsValue(ItemType.movie));
    final rows = await query.get();
    return rows.map((row) => row.read(table.tmdbId)!).toSet();
  }

  /// The TMDB ids of every show with at least one episode play.
  Future<Set<int>> getWatchedShowIds() async {
    final table = _connectionManager.historyItems;
    final query = _connectionManager.selectOnly(table, distinct: true)
      ..addColumns([table.tmdbId])
      ..where(table.type.equalsValue(ItemType.episode));
    final rows = await query.get();
    return rows.map((row) => row.read(table.tmdbId)!).toSet();
  }

  Future<bool> isMovieWatched(int tmdbId) async {
    return await _count(ItemType.movie, tmdbId) > 0;
  }

  Future<bool> isShowWatched(int showTmdbId) async {
    return await _count(ItemType.episode, showTmdbId) > 0;
  }

  Future<bool> isEpisodeWatched(int showTmdbId, int season, int episode) async {
    return await _count(ItemType.episode, showTmdbId, season: season, episode: episode) > 0;
  }

  /// How many distinct episodes of the season have at least one play.
  Future<int> seasonWatchedEpisodeCount(int showTmdbId, int season) async {
    final table = _connectionManager.historyItems;
    final distinctEpisodes = table.episode.count(distinct: true);
    final query = _connectionManager.selectOnly(table)
      ..addColumns([distinctEpisodes])
      ..where(table.tmdbId.equals(showTmdbId) & table.type.equalsValue(ItemType.episode) & table.season.equals(season));
    final row = await query.getSingle();
    return row.read(distinctEpisodes)!;
  }

  Future<int> _count(ItemType type, int tmdbId, {int? season, int? episode}) async {
    final table = _connectionManager.historyItems;
    final countExp = table.historyId.count();
    Expression<bool> filter = table.tmdbId.equals(tmdbId) & table.type.equalsValue(type);
    if (season != null) {
      filter = filter & table.season.equals(season);
    }
    if (episode != null) {
      filter = filter & table.episode.equals(episode);
    }
    final query = _connectionManager.selectOnly(table)
      ..addColumns([countExp])
      ..where(filter);
    final row = await query.getSingle();
    return row.read(countExp)!;
  }

  Future<List<HistoryEntity>> getAllAfterDate(int timestamp, HistoryAction action) async {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc();
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => item.watchedAt.isBiggerThanValue(date) & item.action.equalsValue(action))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return await query.map((row) => row).get();
  }

  Future<List<HistoryEntity>> getBetweenDates(ItemType type, int startDate, int endDate) async {
    DateTime start = DateTime.fromMillisecondsSinceEpoch(startDate).toUtc();
    DateTime end = DateTime.fromMillisecondsSinceEpoch(endDate).toUtc();
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => item.watchedAt.isBetweenValues(start, end) & item.type.equalsValue(type))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return await query.map((row) => row).get();
  }

  /// The running check-ins: `checkin` rows whose end (`watchedAt`) is still in the future.
  Future<List<HistoryEntity>> getCurrentCheckInItems() async {
    final currentDate = DateTime.now().add(const Duration(seconds: 5)).toUtc();
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => item.watchedAt.isBiggerThanValue(currentDate) & item.action.equalsValue(HistoryAction.checkin))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return await query.map((row) => row).get();
  }

  /// The watching twin of [getCurrentCheckInItems].
  ///
  /// Note the `watchedAt` bound is evaluated once, when the query is built — the stream re-emits on
  /// writes to the table, not with the passing of time, so the listener still needs its own
  /// heartbeat to notice a check-in expiring.
  Stream<List<HistoryEntity>> watchCurrentCheckInItems() {
    final currentDate = DateTime.now().add(const Duration(seconds: 5)).toUtc();
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => item.watchedAt.isBiggerThanValue(currentDate) & item.action.equalsValue(HistoryAction.checkin))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return query.map((row) => row).watch();
  }

  Stream<List<HistoryEntity>> listenForChanges([bool fireImmediately = false]) {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return query.map((row) => row).watch();
  }

  Stream<List<HistoryEntity>> listenForItem(ItemType type, int tmdbId, {int season = 0, int episode = 0, bool fireImmediately = false}) {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where(
        (item) => item.type.equalsValue(type) & item.tmdbId.equals(tmdbId) & item.season.equals(season) & item.episode.equals(episode),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return query.map((row) => row).watch();
  }

  /// Watches every history entry belonging to the episodes of one season.
  Stream<List<HistoryEntity>> listenForSeason(int showTmdbId, int season) {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => item.tmdbId.equals(showTmdbId) & item.type.equalsValue(ItemType.episode) & item.season.equals(season))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return query.map((row) => row).watch();
  }

  /// Watches every history entry belonging to any episode of one show.
  Stream<List<HistoryEntity>> listenForShow(int showTmdbId) {
    final query = _connectionManager.select(_connectionManager.historyItems)
      ..where((item) => item.tmdbId.equals(showTmdbId) & item.type.equalsValue(ItemType.episode))
      ..orderBy([(t) => OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc)]);
    return query.map((row) => row).watch();
  }
}
