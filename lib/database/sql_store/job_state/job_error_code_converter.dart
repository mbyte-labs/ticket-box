import 'package:drift/drift.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';

class JobErrorCodeConverter extends TypeConverter<JobErrorCode, String> {
  const JobErrorCodeConverter();

  @override
  JobErrorCode fromSql(String fromDb) {
    return JobErrorCode.values.firstWhere((code) => code.name == fromDb, orElse: () => JobErrorCode.unknownError);
  }

  @override
  String toSql(JobErrorCode value) => value.name;
}
