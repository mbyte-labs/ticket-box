import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/database/sql_store/converter/item_type.converter.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation_converter.dart';

/// Writes the user made while a TMDB sync toggle was on, waiting to reach TMDB.
///
/// A write-ahead queue: every hooked local write lands here first and a flush drains it in id
/// order, so a crash, a dead network or a revoked session loses nothing. At most one row exists per
/// data set and key — `TmdbSyncOutboxRepo.enqueue` replaces the older operation with the newer one.
/// New rows are inserted through the generated companion (the id is AUTOINCREMENT); this row class
/// is read-only.
@UseRowClass(TmdbSyncOutboxEntity, constructor: 'build')
class TmdbSyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get operation => text().map(const TmdbSyncOperationConverter())();

  /// movie, show or episode — a season is never synced.
  TextColumn get type => text().map(const ItemTypeConverter())();

  /// The movie's TMDB id, or the show's TMDB id for shows and episodes.
  IntColumn get tmdbId => integer().customConstraint('NOT NULL')();

  IntColumn get season => integer().customConstraint('NOT NULL')();

  IntColumn get episode => integer().customConstraint('NOT NULL')();

  /// The 1–10 rating, only for [TmdbSyncOperation.rate].
  IntColumn get rating => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  /// How many flushes failed to deliver this row. A row that keeps failing for a reason that is not
  /// TMDB being unreachable is dropped after a few attempts so it cannot block the queue forever.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// A short classification of the last failure, for the diagnostics log and tests.
  TextColumn get lastError => text().nullable()();
}

class TmdbSyncOutboxEntity {
  final int id;
  final TmdbSyncOperation operation;
  final ItemType type;
  final int tmdbId;
  final int season;
  final int episode;
  final int? rating;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  TmdbSyncOutboxEntity.build({
    required this.id,
    required this.operation,
    required this.type,
    required this.tmdbId,
    required this.season,
    required this.episode,
    required this.rating,
    required this.createdAt,
    required this.attempts,
    required this.lastError,
  });

  MediaKey get key => MediaKey(type: type, tmdbId: tmdbId, season: season, episode: episode);

  TmdbDataSet get dataSet => operation.dataSet;

  @override
  String toString() => '${operation.name} $key${rating == null ? '' : ' $rating'} (#$id, attempts $attempts)';
}
