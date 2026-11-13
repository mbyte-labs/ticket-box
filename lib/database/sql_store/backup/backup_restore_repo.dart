import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';

/// Swaps the device's user data for a backup's, across every user table at once.
///
/// One batch = one transaction: a failure leaves the previous data untouched, and the change
/// streams (and so `DataChangeMonitor`) see only the final state.
class BackupRestoreRepo {
  final DatabaseConnectionManager _connectionManager;

  BackupRestoreRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Replaces history, ratings and watchlist with the given rows, and the favorites too
  /// unless [favorites] is `null` (a backup made before that section existed).
  ///
  /// History rows get fresh ids: AUTOINCREMENT continues the sequence past every deleted row, so an
  /// old id is never reused. A restore is a tracking action: every movie and show the restored rows
  /// name gets a catalogue stub row (`fetched_at` null) if it has none, which the backfill fetches;
  /// the system-maintained show states are dropped for the sweep to recompute from the restored log
  /// (the user's dropped shows stay), and the pending deletions are cleared — what was pending may
  /// be referenced again now.
  Future<void> replaceUserData({
    required List<NewHistoryEntry> history,
    required List<UserRatingEntity> ratings,
    required List<WatchlistEntity> watchlist,
    required List<FavoriteEntity>? favorites,
    required DateTime now,
  }) async {
    final movieIds = <int>{
      ...history.where((e) => e.type == ItemType.movie).map((e) => e.tmdbId),
      ...ratings.where((e) => e.type == ItemType.movie).map((e) => e.tmdbId),
      ...watchlist.where((e) => e.type == ItemType.movie).map((e) => e.tmdbId),
      ...?favorites?.where((e) => e.type == ItemType.movie).map((e) => e.tmdbId),
    };
    final showIds = <int>{
      ...history.where((e) => e.type == ItemType.episode).map((e) => e.tmdbId),
      ...ratings.where((e) => e.type != ItemType.movie).map((e) => e.tmdbId),
      ...watchlist.where((e) => e.type != ItemType.movie).map((e) => e.tmdbId),
      ...?favorites?.where((e) => e.type == ItemType.show).map((e) => e.tmdbId),
    };

    await _connectionManager.batch((batch) {
      batch.deleteAll(_connectionManager.historyItems);
      batch.insertAll(
        _connectionManager.historyItems,
        history
            .map(
              (entry) => HistoryItemsCompanion.insert(
                type: entry.type,
                tmdbId: entry.tmdbId,
                season: entry.season,
                episode: entry.episode,
                action: entry.action,
                watchedAt: entry.watchedAt,
              ),
            )
            .toList(),
      );

      batch.deleteAll(_connectionManager.userRatings);
      batch.insertAllOnConflictUpdate(_connectionManager.userRatings, ratings.map((e) => e.toInsertable()).toList());

      batch.deleteAll(_connectionManager.watchlists);
      batch.insertAllOnConflictUpdate(_connectionManager.watchlists, watchlist.map((e) => e.toInsertable()).toList());

      if (favorites != null) {
        batch.deleteAll(_connectionManager.favoriteItems);
        batch.insertAllOnConflictUpdate(_connectionManager.favoriteItems, favorites.map((e) => e.toInsertable()).toList());
      }

      batch.insertAll(_connectionManager.movies, [
        for (final id in movieIds) MoviesCompanion.insert(tmdbId: Value(id), trackedAt: now),
      ], mode: InsertMode.insertOrIgnore);
      batch.insertAll(_connectionManager.shows, [
        for (final id in showIds) ShowsCompanion.insert(tmdbId: Value(id), trackedAt: now),
      ], mode: InsertMode.insertOrIgnore);
      batch.deleteWhere(_connectionManager.showStates, (row) => row.status.equalsValue(ShowWatchStatus.dropped).not());
      batch.deleteAll(_connectionManager.pendingDeletions);
    });
  }
}
