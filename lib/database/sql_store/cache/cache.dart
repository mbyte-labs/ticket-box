import 'package:drift/drift.dart';

@UseRowClass(CacheEntity, constructor: 'build', generateInsertable: true)
class Caches extends Table {
  TextColumn get key => text().customConstraint('NOT NULL UNIQUE')();

  TextColumn get customData => text().named('customData')();

  /// The date in milliseconds when the token will expire
  DateTimeColumn get synchronizedAt => dateTime()();

  // Define a primary key
  @override
  Set<Column> get primaryKey => {key};
}

class CacheEntity {
  final String key;
  final String customData;
  final DateTime synchronizedAt;

  CacheEntity.build({required this.key, required this.customData, required this.synchronizedAt});
}
