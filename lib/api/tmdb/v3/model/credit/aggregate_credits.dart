// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/api/tmdb/v3/model/credit/person_credit.dart';

part 'aggregate_credits.freezed.dart';
part 'aggregate_credits.g.dart';

@freezed
abstract class TmdbCredits with _$TmdbCredits {
  const factory TmdbCredits({
    @JsonSerializable(explicitToJson: true) required List<TmdbCastPerson> cast,
    @JsonSerializable(explicitToJson: true) required List<TmdbCrewPerson> crew,

    /// Only the flat episode-credits endpoint returns this; the show and season *aggregate* ones
    /// have no such key, so they fall back to the default rather than failing to parse.
    @JsonKey(name: 'guest_stars') @Default(<TmdbCastPerson>[]) List<TmdbCastPerson> guestStars,
  }) = _TmdbCredits;

  factory TmdbCredits.fromJson(Map<String, dynamic> json) => _$TmdbCreditsFromJson(json);
}
