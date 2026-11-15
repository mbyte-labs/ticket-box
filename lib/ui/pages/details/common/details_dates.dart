/// TMDB's `YYYY-MM-DD` dates as the details pages display them: local midnight, or null when TMDB
/// has none (an empty string is "none" too).
abstract final class DetailsDates {
  static DateTime? parse(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static int? year(String? value) => parse(value)?.year;

  /// The device's local date as TMDB writes dates, for comparing air dates with "now".
  static String today([DateTime? now]) {
    final d = (now ?? DateTime.now()).toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
