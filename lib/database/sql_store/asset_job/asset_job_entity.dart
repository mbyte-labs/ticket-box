import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/asset_job_status.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/converter/asset_job_status_converter.dart';
import 'package:ticketbox/database/sql_store/converter/item_type.converter.dart';

/// The resumable artwork download queue. One row per file the library wants on disk; [destPath]
/// (relative to the artwork root) is UNIQUE and so the idempotency key: enqueueing the same file
/// twice is a no-op, which is what makes a crashed import resumable. `done` rows are kept — they
/// record the [size] the file was fetched at — and go with their file or their item.
///
/// [kind] is the artwork kind's name (`poster`, `backdrop`, `seasonPoster`, `still`, `cast`); the
/// service layer owns the enum, the database only stores the word.
@TableIndex.sql('CREATE INDEX IF NOT EXISTS idx_asset_jobs_status ON asset_jobs (status, next_retry_at)')
@TableIndex.sql('CREATE INDEX IF NOT EXISTS idx_asset_jobs_item ON asset_jobs (media_type, item_id)')
@UseRowClass(AssetJobEntity, constructor: 'build', generateInsertable: true)
class AssetJobs extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get provider => text().withDefault(const Constant('tmdb'))();

  /// The OWNING movie or show — it keys the artwork directory the deletion sweep removes wholesale.
  TextColumn get mediaType => text().map(const ItemTypeConverter()).customConstraint("NOT NULL CHECK (media_type IN ('movie', 'show'))")();

  IntColumn get itemId => integer().customConstraint('NOT NULL')();

  TextColumn get kind => text().customConstraint("NOT NULL CHECK (kind IN ('poster', 'backdrop', 'seasonPoster', 'still', 'cast'))")();

  /// The TMDB size segment the file was (or will be) fetched at: `w342`, `w780`, `w1280`, ...
  TextColumn get size => text()();

  TextColumn get sourceUrl => text()();

  TextColumn get destPath => text().customConstraint('NOT NULL UNIQUE')();

  TextColumn get status =>
      text().map(const AssetJobStatusConverter()).customConstraint("NOT NULL CHECK (status IN ('pending', 'done', 'failed'))")();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  DateTimeColumn get nextRetryAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  TextColumn get lastError => text().nullable()();
}

class AssetJobEntity {
  int id;
  String provider;
  ItemType mediaType;
  int itemId;
  String kind;
  String size;
  String sourceUrl;
  String destPath;
  AssetJobStatus status;
  int attempts;
  DateTime? nextRetryAt;
  DateTime createdAt;
  String? lastError;

  AssetJobEntity.build({
    required this.id,
    required this.provider,
    required this.mediaType,
    required this.itemId,
    required this.kind,
    required this.size,
    required this.sourceUrl,
    required this.destPath,
    required this.status,
    required this.attempts,
    required this.nextRetryAt,
    required this.createdAt,
    required this.lastError,
  });
}
