import 'package:drift/drift.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code_converter.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_converter.dart';

/// Status of the app's background jobs — one row per job id (see `job_constants.dart`).
///
/// The database is the channel between a job and the UI: `AppBarLoadingIndicatorWidget` streams the
/// progress refresh row and renders a bar while it is [JobState.running].
@UseRowClass(JobStateEntity, constructor: 'build', generateInsertable: true)
class JobStates extends Table {
  IntColumn get jobId => integer().customConstraint('NOT NULL')();

  TextColumn get state => text().map(const JobStateConverter())();

  TextColumn get errorCode => text().map(const JobErrorCodeConverter())();

  TextColumn get userMessage => text().named('userMessage').nullable()();

  DateTimeColumn get startedAt => dateTime()();

  DateTimeColumn get finishedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {jobId};
}

class JobStateEntity {
  final int jobId;
  JobState state;
  JobErrorCode errorCode;
  String? userMessage;
  DateTime startedAt;
  DateTime finishedAt;

  JobStateEntity.build({
    required this.jobId,
    required this.state,
    this.errorCode = JobErrorCode.none,
    this.userMessage,
    required this.startedAt,
    required this.finishedAt,
  });
}
