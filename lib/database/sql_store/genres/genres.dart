import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/converter/item_type.converter.dart';

@UseRowClass(GenreEntity, constructor: 'build', generateInsertable: true)
class Genres extends Table {
  /// TMDB's numeric genre id. Movie and TV genres are separate lists that mostly share ids and
  /// names, so `type` is part of the key.
  IntColumn get id => integer().customConstraint('NOT NULL')();

  TextColumn get name => text().named('name')();

  TextColumn get type => text().map(const ItemTypeConverter())();

  DateTimeColumn get synchronizedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id, type};
}

class GenreEntity {
  final int id;
  final String name;
  final ItemType type;
  final DateTime synchronizedAt;

  GenreEntity.build({required this.id, required this.name, required this.type, required this.synchronizedAt});
}
