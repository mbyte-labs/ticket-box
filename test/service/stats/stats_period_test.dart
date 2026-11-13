import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/service/stats/stats_period.dart';

/// The year boundaries are *local* midnights (the calculator buckets by local date), so the
/// expectations are built from local [DateTime]s and hold in whatever timezone the test runs.
void main() {
  final now = DateTime(2026, 7, 31, 12);

  group('all time', () {
    const period = StatsPeriod.allTime();

    test('has no bounds and contains everything', () {
      expect(period.isAllTime, isTrue);
      expect(period.year, isNull);
      expect(period.start, isNull);
      expect(period.end, isNull);
      expect(period.contains(DateTime.utc(1999, 1, 1)), isTrue);
      expect(period.label, 'All time');
    });

    test('ends its charts and windows at now', () {
      expect(period.lastMonth(now), now);
      expect(period.reference(now), now);
      expect(period.isPast(now), isFalse);
    });
  });

  group('year', () {
    const period = StatsPeriod.year(2024);

    test('is bounded by the local midnights starting and ending the year, in UTC', () {
      expect(period.start, DateTime(2024).toUtc());
      expect(period.start!.isUtc, isTrue);
      expect(period.end, DateTime(2025).toUtc());
      expect(period.label, '2024');
    });

    test('contains an instant by its local year', () {
      expect(period.contains(DateTime(2024, 1, 1, 0, 30).toUtc()), isTrue);
      expect(period.contains(DateTime(2024, 12, 31, 23, 59).toUtc()), isTrue);
      expect(period.contains(DateTime(2023, 12, 31, 23, 59).toUtc()), isFalse);
      expect(period.contains(DateTime(2025).toUtc()), isFalse);
    });

    test('ends its charts with December and a past year at its last instant', () {
      expect(period.lastMonth(now), DateTime(2024, 12));
      expect(period.reference(now), DateTime(2024, 12, 31, 23, 59, 59, 999));
      expect(period.isPast(now), isTrue);
    });

    test('the current year counts back from now', () {
      const current = StatsPeriod.year(2026);
      expect(current.lastMonth(now), DateTime(2026, 12));
      expect(current.reference(now), now);
      expect(current.isPast(now), isFalse);
    });

    test('is equal by year', () {
      expect(const StatsPeriod.year(2024), period);
      expect(const StatsPeriod.year(2025), isNot(period));
      expect(const StatsPeriod.allTime(), isNot(period));
      expect(const StatsPeriod.allTime(), const StatsPeriod.allTime());
    });
  });
}
