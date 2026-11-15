/// The time window the stats page is computed over: the whole history, or one calendar year.
///
/// A year is a *local* year - a play at 00:30 on January 1st belongs to the new year the user
/// experienced, so [start] and [end] are the local midnights converted to UTC, which is how the
/// history rows are stored.
class StatsPeriod {
  /// Null for all time.
  final int? year;

  const StatsPeriod.allTime() : year = null;

  const StatsPeriod.year(int this.year);

  bool get isAllTime => year == null;

  /// "All time" or the year, for the selector and the headline card.
  String get label => year == null ? 'All time' : year.toString();

  /// The first instant of the year in UTC, null for all time.
  DateTime? get start => year == null ? null : DateTime(year!).toUtc();

  /// The first instant *after* the year in UTC (exclusive bound), null for all time.
  DateTime? get end => year == null ? null : DateTime(year! + 1).toUtc();

  /// Whether [instant] falls inside the period, by local calendar year.
  bool contains(DateTime instant) => year == null || instant.toLocal().year == year;

  /// The month the 12 monthly buckets end with: [now]'s month for all time (the last 12 months),
  /// December of the year otherwise (so the buckets are exactly January to December).
  DateTime lastMonth(DateTime now) => year == null ? now : DateTime(year!, DateTime.december);

  /// The instant the "recent" rating window counts back from: [now] for all time and for the
  /// current year, the very end of the year for a past one.
  DateTime reference(DateTime now) {
    if (year == null || year == now.year) {
      return now;
    }
    return DateTime(year!, DateTime.december, 31, 23, 59, 59, 999);
  }

  /// A year that is over - "current" facts (streak, tracking for) mean nothing in it.
  bool isPast(DateTime now) => year != null && year! < now.year;

  @override
  bool operator ==(Object other) => other is StatsPeriod && other.year == year;

  @override
  int get hashCode => year.hashCode;

  @override
  String toString() => 'StatsPeriod($label)';
}
