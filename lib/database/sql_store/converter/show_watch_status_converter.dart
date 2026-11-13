import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';

/// Stores [ShowWatchStatus] by name, which the table's CHECK constraint mirrors.
class ShowWatchStatusConverter extends TypeConverter<ShowWatchStatus, String> {
  const ShowWatchStatusConverter();

  @override
  ShowWatchStatus fromSql(String fromDb) => ShowWatchStatus.fromName(fromDb);

  @override
  String toSql(ShowWatchStatus value) => value.name;
}
