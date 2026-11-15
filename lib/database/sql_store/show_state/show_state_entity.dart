import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/converter/show_watch_status_converter.dart';

/// A show's watch status — see [ShowWatchStatus] for when a row exists and who writes it. There is
/// no movie counterpart: a movie is watched iff the log holds a play for it.
@UseRowClass(ShowStateEntity, constructor: 'build', generateInsertable: true)
class ShowStates extends Table {
  IntColumn get showTmdbId => integer().customConstraint('NOT NULL')();

  TextColumn get status =>
      text().map(const ShowWatchStatusConverter()).customConstraint("NOT NULL CHECK (status IN ('watching', 'watched', 'dropped'))")();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {showTmdbId};
}

class ShowStateEntity {
  int showTmdbId;
  ShowWatchStatus status;
  DateTime updatedAt;

  ShowStateEntity.build({required this.showTmdbId, required this.status, required this.updatedAt});

  bool get isDropped => status == ShowWatchStatus.dropped;
}
