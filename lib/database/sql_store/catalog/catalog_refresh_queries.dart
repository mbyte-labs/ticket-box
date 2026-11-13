import 'package:drift/drift.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';

/// The refresh scheduler's selections — compile-time queries over `fetched_at`, the only freshness
/// state. The two classes are disjoint by construction: a watchlisted or favorite title always
/// takes the faster (active) cadence, the archive class names the rest.
class CatalogRefreshQueries {
  final DatabaseConnectionManager _db;

  CatalogRefreshQueries() : _db = DatabaseConnectionInitializer.getConnection();

  /// Show production statuses that end the active cadence (`ShowStatus.name` values).
  static const String _concludedSql = "('ended', 'canceled')";

  static const String _movieWatchlistedSql = "EXISTS (SELECT 1 FROM watchlists w WHERE w.type = 'movie' AND w.tmdb_id = m.tmdb_id)";
  static const String _movieFavoriteSql = "EXISTS (SELECT 1 FROM favorite_items f WHERE f.type = 'movie' AND f.tmdb_id = m.tmdb_id)";
  static const String _moviePlayedSql = "EXISTS (SELECT 1 FROM history_items h WHERE h.type = 'movie' AND h.tmdb_id = m.tmdb_id)";

  static const String _showWatchlistedSql =
      "EXISTS (SELECT 1 FROM watchlists w WHERE w.type IN ('show', 'season', 'episode') AND w.tmdb_id = s.tmdb_id)";
  static const String _showFavoriteSql = "EXISTS (SELECT 1 FROM favorite_items f WHERE f.type = 'show' AND f.tmdb_id = s.tmdb_id)";
  static const String _showFollowedSql =
      "EXISTS (SELECT 1 FROM show_states st WHERE st.show_tmdb_id = s.tmdb_id AND st.status <> 'dropped')";

  /// Movies on the watchlist or favorites whose snapshot is older than [cutoff].
  Future<List<int>> activeMovieIds(DateTime cutoff) {
    return _ids(
      '''
      SELECT m.tmdb_id FROM movies m
      WHERE m.fetched_at IS NOT NULL AND m.fetched_at <= ?1 AND ($_movieWatchlistedSql OR $_movieFavoriteSql)
      ORDER BY m.fetched_at''',
      [Variable.withDateTime(cutoff)],
      {_db.movies, _db.watchlists, _db.favoriteItems},
    );
  }

  /// Shows on the watchlist or favorites, or followed and still in production (NULL counts as in
  /// production), whose snapshot is older than [cutoff]; plus — whatever their age — followed shows
  /// whose announced next episode has aired since the snapshot was taken, so Up Next moves the day
  /// an episode airs rather than a week later. [today] is `YYYY-MM-DD`.
  Future<List<int>> activeShowIds(DateTime cutoff, String today) {
    return _ids(
      '''
      SELECT s.tmdb_id FROM shows s
      WHERE s.fetched_at IS NOT NULL AND (
        (s.fetched_at <= ?1 AND ($_showWatchlistedSql OR $_showFavoriteSql
          OR ($_showFollowedSql AND (s.status IS NULL OR s.status NOT IN $_concludedSql))))
        OR ($_showFollowedSql AND s.next_episode_air_date IS NOT NULL AND s.next_episode_air_date <= ?2
          AND s.next_episode_air_date > strftime('%Y-%m-%d', s.fetched_at, 'unixepoch', 'localtime')))
      ORDER BY s.fetched_at''',
      [Variable.withDateTime(cutoff), Variable.withString(today)],
      {_db.shows, _db.watchlists, _db.favoriteItems, _db.showStates},
    );
  }

  /// Watched movies on no watchlist or favorites, whose snapshot is older than [cutoff].
  Future<List<int>> archiveMovieIds(DateTime cutoff) {
    return _ids(
      '''
      SELECT m.tmdb_id FROM movies m
      WHERE m.fetched_at IS NOT NULL AND m.fetched_at <= ?1 AND $_moviePlayedSql
        AND NOT $_movieWatchlistedSql AND NOT $_movieFavoriteSql
      ORDER BY m.fetched_at''',
      [Variable.withDateTime(cutoff)],
      {_db.movies, _db.watchlists, _db.favoriteItems, _db.historyItems},
    );
  }

  /// Followed shows that have ended or were canceled, on no watchlist or favorites, whose snapshot
  /// is older than [cutoff].
  Future<List<int>> archiveShowIds(DateTime cutoff) {
    return _ids(
      '''
      SELECT s.tmdb_id FROM shows s
      WHERE s.fetched_at IS NOT NULL AND s.fetched_at <= ?1 AND $_showFollowedSql
        AND s.status IN $_concludedSql AND NOT $_showWatchlistedSql AND NOT $_showFavoriteSql
      ORDER BY s.fetched_at''',
      [Variable.withDateTime(cutoff)],
      {_db.shows, _db.watchlists, _db.favoriteItems, _db.showStates},
    );
  }

  /// Tracked movies / shows whose stored watch providers were pruned to another region than
  /// [region] (null = never pruned) — one refresh each after the user changes country.
  Future<List<int>> movieIdsWithOtherRegion(String? region) {
    return _ids(
      'SELECT m.tmdb_id FROM movies m WHERE m.fetched_at IS NOT NULL AND ${_otherRegionSql('m', region)} ORDER BY m.fetched_at',
      _regionVariables(region),
      {_db.movies},
    );
  }

  Future<List<int>> showIdsWithOtherRegion(String? region) {
    return _ids(
      'SELECT s.tmdb_id FROM shows s WHERE s.fetched_at IS NOT NULL AND ${_otherRegionSql('s', region)} ORDER BY s.fetched_at',
      _regionVariables(region),
      {_db.shows},
    );
  }

  /// `IS NOT ?1` would read a never-pruned row (NULL) as "other" when no region is configured —
  /// `NULL IS NOT ''` is true in SQLite — and re-fetch the whole library every tick.
  static String _otherRegionSql(String alias, String? region) {
    return region == null ? '$alias.watch_providers_region IS NOT NULL' : '$alias.watch_providers_region IS NOT ?1';
  }

  static List<Variable<Object>> _regionVariables(String? region) => region == null ? const [] : [Variable.withString(region)];

  Future<List<int>> _ids(String sql, List<Variable> variables, Set<ResultSetImplementation> readsFrom) async {
    final rows = await _db.customSelect(sql, variables: variables, readsFrom: readsFrom).get();
    return rows.map((row) => row.read<int>('tmdb_id')).toList();
  }
}
