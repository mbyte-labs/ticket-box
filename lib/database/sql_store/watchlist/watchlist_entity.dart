import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/converter/item_type.converter.dart';

@UseRowClass(WatchlistEntity, constructor: 'build', generateInsertable: true)
class Watchlists extends Table {
  TextColumn get type => text().map(const ItemTypeConverter())();

  /// The movie's TMDB id, or the show's TMDB id for shows, seasons and episodes.
  IntColumn get tmdbId => integer().customConstraint('NOT NULL')();

  IntColumn get season => integer().customConstraint('NOT NULL')();

  IntColumn get episode => integer().customConstraint('NOT NULL')();

  DateTimeColumn get listedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {type, tmdbId, season, episode};
}

class WatchlistEntity {
  ItemType type;
  final int tmdbId;
  int season;
  int episode;
  DateTime listedAt;

  WatchlistEntity.build({required this.type, required this.tmdbId, this.season = 0, this.episode = 0, required this.listedAt});

  MediaKey get key => MediaKey(type: type, tmdbId: tmdbId, season: season, episode: episode);
}
