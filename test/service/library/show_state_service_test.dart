import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/service/library/show_state_service.dart';

import '../catalog/catalog_test_support.dart';

/// `ShowStateService` is the one writer of a show's status, reproducible from `episodes` and the
/// watch log: a first play creates `watching`, every aired non-special episode played makes it
/// `watched`, no plays left removes the row, and `dropped` is the user's and sticky.
void main() {
  late DatabaseConnectionManager db;
  late ShowStateService service;
  late ShowStateRepo states;

  // Pinned "today": 15 June 2026.
  final now = DateTime(2026, 6, 15, 12);
  const show = 10;

  setUp(() async {
    db = openTestDatabase();
    states = ShowStateRepo();
    service = ShowStateService();
    // S0E1 special, S1E1/E2 aired, S1E3 announced without a date.
    await seedShow(show);
    await seedEpisode(show, 0, 1, airDate: '2026-01-01');
    await seedEpisode(show, 1, 1, airDate: '2026-06-01');
    await seedEpisode(show, 1, 2, airDate: '2026-06-10');
    await seedEpisode(show, 1, 3);
  });

  tearDown(() => closeTestDatabase(db));

  Future<ShowWatchStatus?> status() async => (await states.get(show))?.status;

  group('recomputeShowStatus', () {
    test('the first play creates watching', () async {
      await playEpisode(show, 1, 1);

      await service.recomputeShowStatus(show, now: now);

      expect(await status(), ShowWatchStatus.watching);
      expect((await states.get(show))!.updatedAt.toUtc(), now.toUtc());
    });

    test('every aired non-special episode played is watched, an undated announced one notwithstanding', () async {
      await playEpisode(show, 1, 1);
      await playEpisode(show, 1, 2);

      await service.recomputeShowStatus(show, now: now);

      expect(await status(), ShowWatchStatus.watched);
    });

    test('a watched special does not count', () async {
      await playEpisode(show, 0, 1);
      await service.recomputeShowStatus(show, now: now);
      expect(await status(), ShowWatchStatus.watching, reason: 'a play exists, nothing aired is watched');

      await playEpisode(show, 1, 1);
      await playEpisode(show, 1, 2);
      await service.recomputeShowStatus(show, now: now);
      expect(await status(), ShowWatchStatus.watched);
    });

    test('a newly aired episode flips watched back to watching on recompute', () async {
      await playEpisode(show, 1, 1);
      await playEpisode(show, 1, 2);
      await service.recomputeShowStatus(show, now: now);
      expect(await status(), ShowWatchStatus.watched);

      await seedEpisode(show, 1, 4, airDate: ymd(now.subtract(const Duration(days: 1))));
      await service.recomputeShowStatus(show, now: now);

      expect(await status(), ShowWatchStatus.watching);
    });

    test('an unchanged status is not rewritten', () async {
      await playEpisode(show, 1, 1);
      await service.recomputeShowStatus(show, now: now);

      await service.recomputeShowStatus(show, now: now.add(const Duration(hours: 1)));

      expect((await states.get(show))!.updatedAt.toUtc(), now.toUtc());
    });

    test('deleting the last play removes the row', () async {
      await playEpisode(show, 1, 1);
      await service.recomputeShowStatus(show, now: now);
      expect(await status(), isNotNull);

      await HistoryRepo().deleteByShowId(show);
      await service.recomputeShowStatus(show, now: now);

      expect(await states.get(show), isNull);
    });

    test('no plays and no row stays no row', () async {
      await service.recomputeShowStatus(show, now: now);

      expect(await states.get(show), isNull);
    });

    test('dropped is sticky through a recompute', () async {
      await service.drop(show, now: now);
      await playEpisode(show, 1, 1);
      await playEpisode(show, 1, 2);

      await service.recomputeShowStatus(show, now: now);

      expect(await status(), ShowWatchStatus.dropped);
      expect(await service.isDropped(show), isTrue);
    });
  });

  group('drop and undrop', () {
    test('undrop lands on watched when the show is finished', () async {
      await playEpisode(show, 1, 1);
      await playEpisode(show, 1, 2);
      await service.drop(show, now: now);

      await service.undrop(show, now: now);

      expect(await status(), ShowWatchStatus.watched);
    });

    test('undrop lands on watching when episodes are left', () async {
      await playEpisode(show, 1, 1);
      await service.drop(show, now: now);

      await service.undrop(show, now: now);

      expect(await status(), ShowWatchStatus.watching);
    });

    test('undrop with no plays removes the row', () async {
      await service.drop(show, now: now);

      await service.undrop(show, now: now);

      expect(await states.get(show), isNull);
    });

    test('undrop of a show that is not dropped changes nothing', () async {
      await playEpisode(show, 1, 1);
      await service.recomputeShowStatus(show, now: now);

      await service.undrop(show, now: now.add(const Duration(days: 1)));

      expect((await states.get(show))!.updatedAt.toUtc(), now.toUtc());
      await service.undrop(99, now: now);
      expect(await states.get(99), isNull);
    });

    test('getDropped lists the most recently dropped first', () async {
      await seedShow(20);
      await service.drop(show, now: now);
      await service.drop(20, now: now.add(const Duration(minutes: 1)));

      expect((await service.getDropped()).map((s) => s.showTmdbId), [20, show]);
      expect(await service.countDropped(), 2);
    });
  });

  group('recomputeAll', () {
    test('covers shows with plays and shows with a non-dropped state, leaves dropped ones alone', () async {
      // Show 10: plays, no row yet → watching.
      await playEpisode(show, 1, 1);
      // Show 20: a stale watching row with no plays left → removed.
      await seedShow(20);
      await seedState(20, ShowWatchStatus.watching);
      // Show 30: dropped with plays → stays dropped.
      await seedShow(30);
      await seedEpisode(30, 1, 1, airDate: '2026-01-01');
      await playEpisode(30, 1, 1);
      await seedState(30, ShowWatchStatus.dropped);
      // Show 40: finished but still marked watching → watched.
      await seedShow(40);
      await seedEpisode(40, 1, 1, airDate: '2026-01-01');
      await playEpisode(40, 1, 1);
      await seedState(40, ShowWatchStatus.watching);

      await service.recomputeAll(now: now);

      expect(await status(), ShowWatchStatus.watching);
      expect(await states.get(20), isNull);
      expect((await states.get(30))!.status, ShowWatchStatus.dropped);
      expect((await states.get(40))!.status, ShowWatchStatus.watched);
    });

    test('with nothing to do it does nothing', () async {
      await service.recomputeAll(now: now);

      expect(await states.getNonDroppedIds(), isEmpty);
    });
  });
}
