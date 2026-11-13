import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/service/stats/stats_period.dart';
import 'package:ticketbox/service/stats/stats_service.dart';

/// The page opens on the current year only when the history has a play in it; otherwise all time.
void main() {
  late DatabaseConnectionManager db;
  late HistoryRepo historyRepo;

  var nextHistoryId = 1;

  HistoryEntity episodePlay(DateTime watchedAt) {
    return HistoryEntity.build(
      historyId: nextHistoryId++,
      tmdbId: 1,
      season: 1,
      episode: nextHistoryId,
      type: ItemType.episode,
      action: HistoryAction.watch,
      watchedAt: watchedAt.toUtc(),
    );
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    historyRepo = HistoryRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  group('defaultPeriod', () {
    final now = DateTime.now();

    test('is all time without any history', () async {
      expect(await StatsService().defaultPeriod(), const StatsPeriod.allTime());
    });

    test('is all time when the only plays are in earlier years', () async {
      await historyRepo.insertAll([episodePlay(DateTime(now.year - 1, 12, 31, 23, 30)), episodePlay(DateTime(now.year - 3, 6, 1))]);

      expect(await StatsService().defaultPeriod(), const StatsPeriod.allTime());
    });

    test('is the current year once it has a play', () async {
      await historyRepo.insertAll([episodePlay(DateTime(now.year - 1, 6, 1)), episodePlay(DateTime(now.year, 1, 1, 0, 30))]);

      expect(await StatsService().defaultPeriod(), StatsPeriod.year(now.year));
    });

    test('ignores a future dated check-in in the current year', () async {
      await historyRepo.insertAll([episodePlay(now.add(const Duration(minutes: 30)))]);

      expect(await StatsService().defaultPeriod(), const StatsPeriod.allTime());
    });
  });
}
