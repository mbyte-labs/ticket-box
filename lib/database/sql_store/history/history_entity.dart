import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/converter/history_action_converter.dart';
import 'package:ticketbox/database/sql_store/converter/item_type.converter.dart';

/// One play of a movie or an episode.
///
/// [historyId] is a local AUTOINCREMENT key. Rows migrated from the v3 database kept their old ids, and
/// SQLite continues the sequence from the largest of them, so ids never collide and a deleted id is
/// never reused — the check-in cancel and history-entry removal flows rely on that.
///
/// New rows must be inserted through `HistoryRepo.insertNew`, which leaves the id to the database;
/// `toInsertable()` always carries an explicit id and is for upserts of existing rows and tests.
///
/// The key index serves the per-episode `EXISTS` every derived progress count runs and every
/// lookup by item; the `watched_at` one the history page's order and the check-in window. Both are
/// `IF NOT EXISTS` so the 3 → 10 walk, whose `createAll()` already built them, can create them again.
@TableIndex.sql('CREATE INDEX IF NOT EXISTS idx_history_items_key ON history_items (type, tmdb_id, season, episode)')
@TableIndex.sql('CREATE INDEX IF NOT EXISTS idx_history_items_watched_at ON history_items (watched_at)')
@UseRowClass(HistoryEntity, constructor: 'build', generateInsertable: true)
class HistoryItems extends Table {
  IntColumn get historyId => integer().autoIncrement()();

  TextColumn get type => text().map(const ItemTypeConverter())();

  /// The movie's TMDB id, or the SHOW's TMDB id for episode rows.
  IntColumn get tmdbId => integer().customConstraint('NOT NULL')();

  /// Season number for episode rows, 0 for movies
  IntColumn get season => integer().customConstraint('NOT NULL')();

  /// Episode number for episode rows, 0 for movies
  IntColumn get episode => integer().customConstraint('NOT NULL')();

  TextColumn get action => text().map(const HistoryActionConverter())();

  DateTimeColumn get watchedAt => dateTime().customConstraint('NOT NULL')();
}

class HistoryEntity {
  int historyId;

  /// Movie or show TMDB id
  int tmdbId;

  /// Season number if the type is episode
  int season;

  /// Episode number if the type is episode
  int episode;

  ItemType type;
  HistoryAction action;
  DateTime watchedAt;

  HistoryEntity.build({
    required this.historyId,
    required this.tmdbId,
    this.season = 0,
    this.episode = 0,
    required this.type,
    required this.action,
    required this.watchedAt,
  });
}

/// A play that has not been written yet, so it has no id.
class NewHistoryEntry {
  final ItemType type;
  final int tmdbId;
  final int season;
  final int episode;
  final HistoryAction action;
  final DateTime watchedAt;

  const NewHistoryEntry({
    required this.type,
    required this.tmdbId,
    this.season = 0,
    this.episode = 0,
    required this.action,
    required this.watchedAt,
  });

  const NewHistoryEntry.movie({required this.tmdbId, required this.action, required this.watchedAt})
    : type = ItemType.movie,
      season = 0,
      episode = 0;

  const NewHistoryEntry.episode({
    required int showTmdbId,
    required this.season,
    required this.episode,
    required this.action,
    required this.watchedAt,
  }) : type = ItemType.episode,
       tmdbId = showTmdbId;
}

/// Plays of one movie or show aggregated from the history table (the former v3 "watched" row).
class WatchedAggregate {
  /// [ItemType.movie] or [ItemType.show]; episode plays are rolled up to their show.
  final ItemType type;
  final int tmdbId;
  final int plays;
  final DateTime lastWatchedAt;

  const WatchedAggregate({required this.type, required this.tmdbId, required this.plays, required this.lastWatchedAt});
}
