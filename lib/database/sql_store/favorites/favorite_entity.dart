import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/converter/item_type.converter.dart';

/// The user's favorite movies and shows — a device-local, user-curated list, flagged from the
/// details pages' overflow menu. Only `movie` and `show` rows are ever stored: there is no
/// season- or episode-level favorite.
///
/// Movies and shows share TMDB's numeric id space, so [type] is part of the key.
@UseRowClass(FavoriteEntity, constructor: 'build', generateInsertable: true)
class FavoriteItems extends Table {
  TextColumn get type => text().map(const ItemTypeConverter())();

  IntColumn get tmdbId => integer().customConstraint('NOT NULL')();

  DateTimeColumn get favoritedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {type, tmdbId};
}

class FavoriteEntity {
  final ItemType type;
  final int tmdbId;
  final DateTime favoritedAt;

  FavoriteEntity.build({required this.type, required this.tmdbId, required this.favoritedAt});

  MediaKey get key => MediaKey(type: type, tmdbId: tmdbId);
}
