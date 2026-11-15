import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/asset_job_status.dart';

/// Stores [AssetJobStatus] by name, which the table's CHECK constraint mirrors.
class AssetJobStatusConverter extends TypeConverter<AssetJobStatus, String> {
  const AssetJobStatusConverter();

  @override
  AssetJobStatus fromSql(String fromDb) => AssetJobStatus.fromName(fromDb);

  @override
  String toSql(AssetJobStatus value) => value.name;
}
