import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_entity.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_repository.dart';

/// Covers [JobStateRepo]: the first read of a job creates its idle row, so callers never deal with
/// a missing one, and [JobStateRepo.streamChanges] is the channel between a background job and the
/// app bar's loading indicator.
void main() {
  late DatabaseConnectionManager db;
  late JobStateRepo repo;

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = JobStateRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('get', () {
    test('creates an idle row for a job that was never run', () async {
      final state = await repo.get(PROGRESS_REFRESH_JOB_ID);

      expect(state.jobId, PROGRESS_REFRESH_JOB_ID);
      expect(state.state, JobState.idle);
      expect(state.errorCode, JobErrorCode.none);
      expect(state.userMessage, isNull);
      expect(await db.select(db.jobStates).get(), hasLength(1), reason: 'the idle row must be persisted, not just returned');
    });

    test('returns the stored row on later reads instead of resetting it', () async {
      await repo.insert(
        JobStateEntity.build(
          jobId: PROGRESS_REFRESH_JOB_ID,
          state: JobState.failed,
          errorCode: JobErrorCode.networkError,
          userMessage: 'offline',
          startedAt: DateTime.utc(2026, 7, 1, 10),
          finishedAt: DateTime.utc(2026, 7, 1, 10, 5),
        ),
      );

      final state = await repo.getProgressRefresh();

      expect(state.state, JobState.failed);
      expect(state.errorCode, JobErrorCode.networkError);
      expect(state.userMessage, 'offline');
      expect(state.startedAt.isAtSameMomentAs(DateTime.utc(2026, 7, 1, 10)), isTrue);
      expect(await db.select(db.jobStates).get(), hasLength(1));
    });

    test('jobs are independent rows', () async {
      await repo.get(1);
      await repo.get(2);

      expect((await db.select(db.jobStates).get()).map((r) => r.jobId), unorderedEquals([1, 2]));
    });
  });

  test('updateMessage changes only the message', () async {
    await repo.get(PROGRESS_REFRESH_JOB_ID);

    await repo.updateMessage(PROGRESS_REFRESH_JOB_ID, 'Refreshing 3 of 10');

    final state = await repo.getProgressRefresh();
    expect(state.userMessage, 'Refreshing 3 of 10');
    expect(state.state, JobState.idle);
  });

  group('streamChanges', () {
    test('emits null for a missing row, then every state the job writes', () async {
      final emissions = <JobState?>[];
      final subscription = repo.streamChanges(PROGRESS_REFRESH_JOB_ID).listen((row) => emissions.add(row?.state));
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      final running = await repo.get(PROGRESS_REFRESH_JOB_ID);
      await pumpEventQueue();
      running.state = JobState.running;
      await repo.insert(running);
      await pumpEventQueue();
      running.state = JobState.finished;
      await repo.insert(running);
      await pumpEventQueue();

      expect(emissions.first, isNull);
      expect(emissions.whereType<JobState>(), [JobState.idle, JobState.running, JobState.finished]);
    });

    test('ignores writes to another job', () async {
      await repo.get(1);

      final emissions = <JobStateEntity?>[];
      final subscription = repo.streamChanges(1).listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await repo.get(2);
      await repo.updateMessage(2, 'other');
      await pumpEventQueue();

      expect(emissions.every((row) => row?.jobId == 1 && row?.userMessage == null), isTrue);
    });
  });
}
