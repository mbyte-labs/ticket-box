import 'package:drift/drift.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';

class JobStateConverter extends TypeConverter<JobState, String> {
  const JobStateConverter();

  @override
  JobState fromSql(String fromDb) {
    return JobState.values.firstWhere((state) => state.name == fromDb, orElse: () => JobState.idle);
  }

  @override
  String toSql(JobState value) => value.name;
}
