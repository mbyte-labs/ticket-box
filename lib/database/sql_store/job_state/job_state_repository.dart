import 'package:drift/drift.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_entity.dart';

class JobStateRepo {
  final DatabaseConnectionManager _connectionManager;

  JobStateRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// The progress refresh job's row, created idle on first read.
  Future<JobStateEntity> getProgressRefresh() => get(PROGRESS_REFRESH_JOB_ID);

  Future<JobStateEntity> get(int jobId) async {
    final query = _connectionManager.select(_connectionManager.jobStates)..where((item) => item.jobId.equals(jobId));
    final existing = await query.getSingleOrNull();
    if (existing != null) {
      return existing;
    }
    final initial = JobStateEntity.build(jobId: jobId, state: JobState.idle, startedAt: DateTime(2000), finishedAt: DateTime(2000));
    await insert(initial);
    return initial;
  }

  Future<void> insert(JobStateEntity item) async {
    await _connectionManager.into(_connectionManager.jobStates).insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> updateMessage(int jobId, String? message) async {
    await (_connectionManager.update(
      _connectionManager.jobStates,
    )..where((t) => t.jobId.equals(jobId))).write(JobStatesCompanion(userMessage: Value(message)));
  }

  Stream<JobStateEntity?> streamChanges(int jobId) {
    final query = _connectionManager.select(_connectionManager.jobStates)..where((item) => item.jobId.equals(jobId));
    return query.watch().map((entities) => entities.isNotEmpty ? entities.first : null);
  }

  /// Whether any of [jobIds] is running, re-emitted whenever one of their rows changes — the
  /// app-bar indicator watches the progress refresh and the TMDB sync together.
  Stream<bool> streamAnyRunning(List<int> jobIds) {
    final query = _connectionManager.select(_connectionManager.jobStates)..where((item) => item.jobId.isIn(jobIds));
    return query.watch().map((entities) => entities.any((job) => job.state == JobState.running));
  }
}
