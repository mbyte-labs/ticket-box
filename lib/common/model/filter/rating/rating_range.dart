import 'package:freezed_annotation/freezed_annotation.dart';

part 'rating_range.freezed.dart';

part 'rating_range.g.dart';

@freezed
abstract class FilterRatingRange with _$FilterRatingRange {
  const factory FilterRatingRange({
    required double minAllowedRange,
    required double maxAllowedRange,
    required double minRange,
    required double maxRange,
  }) = _FilterRatingRange;

  factory FilterRatingRange.initial() {
    return const FilterRatingRange(minRange: 1, maxRange: 10, minAllowedRange: 1, maxAllowedRange: 10);
  }

  factory FilterRatingRange.fromJson(Map<String, dynamic> json) => _$FilterRatingRangeFromJson(json);
}
