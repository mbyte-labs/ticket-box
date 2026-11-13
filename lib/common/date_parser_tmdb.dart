/// TMDB publishes dates (`yyyy-MM-dd`), not instants. They are stored as local midnight so that
/// "aired today" comparisons and the Up Next ordering behave the way a viewer reads a date.
DateTime? tmdbDateOrNull(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

int? tmdbYearOrNull(String? value) => tmdbDateOrNull(value)?.year;
