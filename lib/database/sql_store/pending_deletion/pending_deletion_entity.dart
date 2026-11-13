import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/converter/item_type.converter.dart';

/// A movie or show whose last reference (play, rating, watchlist, favorite, state) was removed.
/// Nothing is deleted when the row is written: a deferred sweep re-checks the references after a
/// grace period and only then removes the catalogue rows and the artwork directory. Re-tracking
/// the item before the sweep simply drops the row.
@UseRowClass(PendingDeletionEntity, constructor: 'build', generateInsertable: true)
class PendingDeletions extends Table {
  TextColumn get type => text().map(const ItemTypeConverter()).customConstraint("NOT NULL CHECK (type IN ('movie', 'show'))")();

  IntColumn get tmdbId => integer().customConstraint('NOT NULL')();

  DateTimeColumn get queuedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {type, tmdbId};
}

class PendingDeletionEntity {
  ItemType type;
  int tmdbId;
  DateTime queuedAt;

  PendingDeletionEntity.build({required this.type, required this.tmdbId, required this.queuedAt});
}
