import 'package:freezed_annotation/freezed_annotation.dart';

part 'year_range.freezed.dart';

part 'year_range.g.dart';

@freezed
abstract class FilterYearRange with _$FilterYearRange {
  static const int defaultMinAllowedYear = 1900;
  static const int defaultMaxExtraYears = 5;

  const factory FilterYearRange({required int minAllowedYear, required int maxAllowedYear, required int minYear, required int maxYear}) =
      _FilterYearRange;

  factory FilterYearRange.initial() {
    return FilterYearRange(
      minAllowedYear: defaultMinAllowedYear,
      maxAllowedYear: DateTime.now().year + defaultMaxExtraYears,
      minYear: defaultMinAllowedYear,
      maxYear: DateTime.now().year + defaultMaxExtraYears,
    );
  }

  factory FilterYearRange.fromJson(Map<String, dynamic> json) => _$FilterYearRangeFromJson(json);
}
