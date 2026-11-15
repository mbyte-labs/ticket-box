import 'package:intl/intl.dart';

/// The person page's date and life-line formatting, pure so it can be unit-tested.
///
/// TMDB dates are `yyyy-MM-dd` strings, but a person's birthday is sometimes only a year; such a
/// date is shown as it came and never has an age computed from it.
class PersonTextFormat {
  static final _fullDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  const PersonTextFormat._();

  static bool isFullDate(String? value) => value != null && _fullDate.hasMatch(value) && DateTime.tryParse(value) != null;

  /// `18 Dec 1963` for a full date; a partial date (`1963`) as it is; null for nothing.
  static String? formatDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    if (!isFullDate(value)) {
      return value;
    }
    return DateFormat('d MMM y').format(DateTime.parse(value));
  }

  /// Whole years between [from] and [until], one less when the birthday has not come around yet
  /// in [until]'s year. Null for a negative range.
  static int? age(DateTime from, DateTime until) {
    var age = until.year - from.year;
    if (until.month < from.month || (until.month == from.month && until.day < from.day)) {
      age--;
    }
    return age < 0 ? null : age;
  }

  /// `Born 18 Dec 1963 (age 62)` while alive, `18 Dec 1963 – 5 May 2001 (aged 71)` once deceased.
  /// The age is left out whenever a date it would need is not a full date; no birthday, no line.
  static String? lifeLine(String? birthday, String? deathday, DateTime now) {
    final born = formatDate(birthday);
    if (born == null) {
      return null;
    }
    final died = formatDate(deathday);
    final fullBirthday = isFullDate(birthday);

    if (died == null) {
      final years = fullBirthday ? age(DateTime.parse(birthday!), now) : null;
      return years == null ? 'Born $born' : 'Born $born (age $years)';
    }

    final years = fullBirthday && isFullDate(deathday) ? age(DateTime.parse(birthday!), DateTime.parse(deathday!)) : null;
    return years == null ? '$born – $died' : '$born – $died (aged $years)';
  }

  /// The hero's one-line summary: department, life line and birthplace, whichever exist.
  static String? metaLine({
    required String? knownForDepartment,
    required String? birthday,
    required String? deathday,
    required String? placeOfBirth,
    required DateTime now,
  }) {
    final parts = [
      knownForDepartment,
      lifeLine(birthday, deathday, now),
      placeOfBirth,
    ].whereType<String>().where((part) => part.trim().isNotEmpty);
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
