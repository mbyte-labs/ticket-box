/// The one staleness rule for stored snapshots.
///
/// A tracked item's `fetched_at` is its only freshness state: a page view refreshes the snapshot
/// (silently, keeping the stale copy on failure) once it is older than [viewTtl], and the refresh
/// scheduler selects by the same column on its own, longer intervals. There is no other TTL.
class SnapshotFreshness {
  const SnapshotFreshness._();

  /// How old a snapshot may be before a page view refreshes it.
  static const Duration viewTtl = Duration(hours: 48);

  /// Whether a snapshot fetched at [fetchedAt] should be refreshed on view. A never-fetched row
  /// (`null`, the backfill's work list) always counts as stale.
  static bool isStale(DateTime? fetchedAt, {DateTime? now}) {
    if (fetchedAt == null) {
      return true;
    }
    return (now ?? DateTime.now()).difference(fetchedAt) >= viewTtl;
  }
}
