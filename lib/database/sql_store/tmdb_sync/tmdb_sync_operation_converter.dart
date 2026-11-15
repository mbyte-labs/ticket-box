import 'package:drift/drift.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';

class TmdbSyncOperationConverter extends TypeConverter<TmdbSyncOperation, String> {
  const TmdbSyncOperationConverter();

  @override
  TmdbSyncOperation fromSql(String fromDb) {
    return TmdbSyncOperation.values.firstWhere((operation) => operation.name == fromDb);
  }

  @override
  String toSql(TmdbSyncOperation value) => value.name;
}
