import 'package:drift/drift.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/common/model/asset_job_status.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_entity.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';

/// A job to enqueue: everything but the id and the bookkeeping the worker fills in.
class NewAssetJob {
  final ItemType mediaType;
  final int itemId;
  final String kind;
  final String size;
  final String sourceUrl;
  final String destPath;

  const NewAssetJob({
    required this.mediaType,
    required this.itemId,
    required this.kind,
    required this.size,
    required this.sourceUrl,
    required this.destPath,
  });
}

/// The artwork download queue rows. The worker's policy (what to download, when to retry, when to
/// give up) lives in the service layer; this repo only stores and selects.
class AssetJobRepo {
  final DatabaseConnectionManager _connectionManager;

  AssetJobRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Inserts the jobs whose `dest_path` is not queued yet, with [status]; already queued paths are
  /// left as they are (`INSERT OR IGNORE` on the UNIQUE column).
  Future<void> insertIgnore(List<NewAssetJob> jobs, {required DateTime createdAt, AssetJobStatus status = AssetJobStatus.pending}) async {
    if (jobs.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAll(_connectionManager.assetJobs, [
        for (final job in jobs)
          AssetJobsCompanion.insert(
            mediaType: job.mediaType,
            itemId: job.itemId,
            kind: job.kind,
            size: job.size,
            sourceUrl: job.sourceUrl,
            destPath: job.destPath,
            status: status,
            createdAt: createdAt,
          ),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  /// The rows for the given destination paths, keyed by path.
  Future<Map<String, AssetJobEntity>> getByDestPaths(Iterable<String> destPaths) async {
    final paths = destPaths.toSet().toList();
    if (paths.isEmpty) {
      return {};
    }
    final result = <String, AssetJobEntity>{};
    for (final chunk in paths.chunked(_lookupChunkSize)) {
      final query = _connectionManager.select(_connectionManager.assetJobs)..where((row) => row.destPath.isIn(chunk));
      for (final job in await query.get()) {
        result[job.destPath] = job;
      }
    }
    return result;
  }

  /// Re-queues a path with a new size and source URL (the user changed the artwork quality).
  Future<void> resetForNewSize(String destPath, {required String size, required String sourceUrl}) async {
    await (_connectionManager.update(_connectionManager.assetJobs)..where((row) => row.destPath.equals(destPath))).write(
      AssetJobsCompanion(
        size: Value(size),
        sourceUrl: Value(sourceUrl),
        status: const Value(AssetJobStatus.pending),
        attempts: const Value(0),
        nextRetryAt: const Value(null),
        lastError: const Value(null),
      ),
    );
  }

  /// Re-queues every failed row, or only those of the movie or show [item] names.
  Future<void> resetFailed({MediaKey? item}) async {
    final update = _connectionManager.update(_connectionManager.assetJobs)
      ..where((row) {
        var predicate = row.status.equalsValue(AssetJobStatus.failed);
        if (item != null) {
          predicate = predicate & row.mediaType.equalsValue(item.showKey.type) & row.itemId.equals(item.showKey.tmdbId);
        }
        return predicate;
      });
    await update.write(
      const AssetJobsCompanion(status: Value(AssetJobStatus.pending), attempts: Value(0), nextRetryAt: Value(null), lastError: Value(null)),
    );
  }

  /// The next pending rows whose retry time has passed, by id, after [afterId].
  Future<List<AssetJobEntity>> getPending(int limit, {int afterId = 0, required DateTime now}) async {
    final query = _connectionManager.select(_connectionManager.assetJobs)
      ..where(
        (row) =>
            row.status.equalsValue(AssetJobStatus.pending) &
            row.id.isBiggerThanValue(afterId) &
            (row.nextRetryAt.isNull() | row.nextRetryAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.id)])
      ..limit(limit);
    return await query.get();
  }

  Future<void> markDone(int id) async {
    await (_connectionManager.update(_connectionManager.assetJobs)..where((row) => row.id.equals(id))).write(
      const AssetJobsCompanion(status: Value(AssetJobStatus.done), nextRetryAt: Value(null), lastError: Value(null)),
    );
  }

  Future<void> markFailed(int id, String error) async {
    await (_connectionManager.update(_connectionManager.assetJobs)..where((row) => row.id.equals(id))).write(
      AssetJobsCompanion(status: const Value(AssetJobStatus.failed), nextRetryAt: const Value(null), lastError: Value(error)),
    );
  }

  /// Records a failed attempt and when to try again.
  Future<void> markRetry(int id, String error, DateTime nextRetryAt) async {
    await _connectionManager.customUpdate(
      'UPDATE asset_jobs SET attempts = attempts + 1, next_retry_at = ?, last_error = ? WHERE id = ?',
      variables: [Variable.withDateTime(nextRetryAt), Variable.withString(error), Variable.withInt(id)],
      updates: {_connectionManager.assetJobs},
    );
  }

  Future<void> deleteByDestPath(String destPath) async {
    await (_connectionManager.delete(_connectionManager.assetJobs)..where((row) => row.destPath.equals(destPath))).go();
  }

  /// Removes every row of one movie or show — with its artwork directory.
  Future<void> deleteForItem(ItemType mediaType, int itemId) async {
    await (_connectionManager.delete(
      _connectionManager.assetJobs,
    )..where((row) => row.mediaType.equalsValue(mediaType) & row.itemId.equals(itemId))).go();
  }

  Future<int> countPending({required DateTime now}) => _count(
    (row) => row.status.equalsValue(AssetJobStatus.pending) & (row.nextRetryAt.isNull() | row.nextRetryAt.isSmallerOrEqualValue(now)),
  );

  Future<int> countAllPending() => _count((row) => row.status.equalsValue(AssetJobStatus.pending));

  Future<int> countFailed() => _count((row) => row.status.equalsValue(AssetJobStatus.failed));

  Future<int> _count(Expression<bool> Function($AssetJobsTable row) predicate) async {
    final table = _connectionManager.assetJobs;
    final count = table.id.count();
    final query = _connectionManager.selectOnly(table)
      ..addColumns([count])
      ..where(predicate(table));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// The pending count as a stream, for the Settings tile.
  Stream<int> watchPendingCount() {
    final table = _connectionManager.assetJobs;
    final count = table.id.count();
    final query = _connectionManager.selectOnly(table)
      ..addColumns([count])
      ..where(table.status.equalsValue(AssetJobStatus.pending));
    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  /// The destination paths of every downloaded file, for warming the in-memory index.
  Future<List<String>> donePaths() async {
    final table = _connectionManager.assetJobs;
    final query = _connectionManager.selectOnly(table)
      ..addColumns([table.destPath])
      ..where(table.status.equalsValue(AssetJobStatus.done));
    final rows = await query.get();
    return rows.map((row) => row.read(table.destPath)!).toList();
  }

  /// Well below SQLite's default limit of 999 bound variables per statement.
  static const _lookupChunkSize = 500;
}
