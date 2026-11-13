import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_entity.dart';

/// The `show_states` rows. The status itself is written by one place only, the show state
/// service's recompute (plus the user's drop / un-drop); this repo just stores it.
class ShowStateRepo {
  final DatabaseConnectionManager _connectionManager;

  ShowStateRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  Future<ShowStateEntity?> get(int showTmdbId) async {
    final query = _connectionManager.select(_connectionManager.showStates)..where((row) => row.showTmdbId.equals(showTmdbId));
    return await query.getSingleOrNull();
  }

  Future<void> upsert(int showTmdbId, ShowWatchStatus status, DateTime updatedAt) async {
    await _connectionManager
        .into(_connectionManager.showStates)
        .insertOnConflictUpdate(ShowStateEntity.build(showTmdbId: showTmdbId, status: status, updatedAt: updatedAt).toInsertable());
  }

  Future<void> upsertAll(List<ShowStateEntity> states) async {
    if (states.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.showStates, states.map((e) => e.toInsertable()).toList());
    });
  }

  Future<void> delete(int showTmdbId) async {
    await (_connectionManager.delete(_connectionManager.showStates)..where((row) => row.showTmdbId.equals(showTmdbId))).go();
  }

  /// Removes every system-maintained row, keeping the user's dropped ones — what a backup restore
  /// does before the sweep recomputes them from the restored log.
  Future<void> deleteNonDropped() async {
    await (_connectionManager.delete(
      _connectionManager.showStates,
    )..where((row) => row.status.equalsValue(ShowWatchStatus.dropped).not())).go();
  }

  Future<bool> isDropped(int showTmdbId) async => (await get(showTmdbId))?.isDropped ?? false;

  /// The dropped shows, most recently dropped first — the Dropped Shows page.
  Future<List<ShowStateEntity>> getDropped() async {
    final query = _connectionManager.select(_connectionManager.showStates)
      ..where((row) => row.status.equalsValue(ShowWatchStatus.dropped))
      ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)]);
    return await query.get();
  }

  Future<Set<int>> getDroppedIds() => _idsWhere((row) => row.status.equalsValue(ShowWatchStatus.dropped));

  /// Every show that is `watching` or `watched` — the sweep's recompute list.
  Future<Set<int>> getNonDroppedIds() => _idsWhere((row) => row.status.equalsValue(ShowWatchStatus.dropped).not());

  /// The shows the user has finished (every aired episode played).
  Future<Set<int>> getFinishedIds() => _idsWhere((row) => row.status.equalsValue(ShowWatchStatus.watched));

  Future<Set<int>> _idsWhere(Expression<bool> Function($ShowStatesTable row) predicate) async {
    final table = _connectionManager.showStates;
    final query = _connectionManager.selectOnly(table)
      ..addColumns([table.showTmdbId])
      ..where(predicate(table));
    final rows = await query.get();
    return rows.map((row) => row.read(table.showTmdbId)!).toSet();
  }

  Future<int> countDropped() async {
    final table = _connectionManager.showStates;
    final count = table.showTmdbId.count();
    final query = _connectionManager.selectOnly(table)
      ..addColumns([count])
      ..where(table.status.equalsValue(ShowWatchStatus.dropped));
    return (await query.getSingle()).read(count) ?? 0;
  }

  Stream<void> listenForChanges() => _connectionManager.select(_connectionManager.showStates).watch();
}
