import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/pending_deletion/pending_deletion_entity.dart';

class PendingDeletionRepo {
  final DatabaseConnectionManager _connectionManager;

  PendingDeletionRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Queues an item; an already queued one keeps its original timestamp.
  Future<void> enqueue(ItemType type, int tmdbId, DateTime queuedAt) async {
    await _connectionManager
        .into(_connectionManager.pendingDeletions)
        .insert(
          PendingDeletionEntity.build(type: type, tmdbId: tmdbId, queuedAt: queuedAt).toInsertable(),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Dequeues an item — it was referenced again before the sweep.
  Future<void> delete(ItemType type, int tmdbId) async {
    await (_connectionManager.delete(
      _connectionManager.pendingDeletions,
    )..where((row) => row.type.equalsValue(type) & row.tmdbId.equals(tmdbId))).go();
  }

  Future<void> deleteAll() async {
    await _connectionManager.delete(_connectionManager.pendingDeletions).go();
  }

  /// Items queued at or before [cutoff], oldest first.
  Future<List<PendingDeletionEntity>> getDue(DateTime cutoff) async {
    final query = _connectionManager.select(_connectionManager.pendingDeletions)
      ..where((row) => row.queuedAt.isSmallerOrEqualValue(cutoff))
      ..orderBy([(t) => OrderingTerm(expression: t.queuedAt)]);
    return await query.get();
  }

  Future<List<PendingDeletionEntity>> getAll() => _connectionManager.select(_connectionManager.pendingDeletions).get();

  Future<int> count() async {
    final table = _connectionManager.pendingDeletions;
    final count = table.tmdbId.count();
    final query = _connectionManager.selectOnly(table)..addColumns([count]);
    return (await query.getSingle()).read(count) ?? 0;
  }
}
