import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/service/cache_update_calculator.dart';

/// Covers [CacheNeedsUpdate.generalItem], the one day-granular TTL rule left for the generic
/// caches (OMDB ratings, discover front pages, watch-provider regions, genre lists).
///
/// The property that matters is the extra base day: a cache written `minDays` ago is still fresh,
/// it only expires once `minDays + base` whole days have passed.
void main() {
  DateTime daysAgo(int days) => DateTime.now().toUtc().subtract(Duration(days: days));

  group('generalItem', () {
    test('a just-written cache is not refreshed', () {
      expect(CacheNeedsUpdate.generalItem(daysAgo(0), 7), isFalse);
    });

    test('is left alone until minDays plus the base day', () {
      expect(CacheNeedsUpdate.generalItem(daysAgo(3), 7), isFalse);
      expect(CacheNeedsUpdate.generalItem(daysAgo(7), 7), isFalse);
    });

    test('expires after minDays plus the base day', () {
      expect(CacheNeedsUpdate.generalItem(daysAgo(8), 7), isTrue);
      expect(CacheNeedsUpdate.generalItem(daysAgo(90), 7), isTrue);
    });

    test('the base day can be overridden', () {
      expect(CacheNeedsUpdate.generalItem(daysAgo(7), 7, 0), isTrue);
      expect(CacheNeedsUpdate.generalItem(daysAgo(8), 7, 2), isFalse);
      expect(CacheNeedsUpdate.generalItem(daysAgo(9), 7, 2), isTrue);
    });

    test('a zero TTL with no base day expires immediately', () {
      expect(CacheNeedsUpdate.generalItem(daysAgo(0), 0, 0), isTrue);
    });

    test('a future timestamp is never due', () {
      expect(CacheNeedsUpdate.generalItem(DateTime.now().toUtc().add(const Duration(days: 30)), 0, 0), isFalse);
    });
  });
}
