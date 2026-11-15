/// The one TTL rule left for the generic caches: OMDB ratings, the discover front pages, the
/// watch-provider regions and the genre lists. The library's own freshness is `fetched_at` on the
/// catalogue rows (see `SnapshotFreshness`), not a TTL.
class CacheNeedsUpdate {
  const CacheNeedsUpdate._();

  /// Whether [synchronizedAt] is at least `minDays + base` days old (a day-granular TTL).
  static bool generalItem(DateTime synchronizedAt, int minDays, [int base = 1]) {
    return DateTime.now().difference(synchronizedAt).inDays >= minDays + base;
  }
}
