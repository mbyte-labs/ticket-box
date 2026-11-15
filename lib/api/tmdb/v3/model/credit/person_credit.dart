// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'person_credit.freezed.dart';
part 'person_credit.g.dart';

@freezed
abstract class TmdbCastPerson with _$TmdbCastPerson {
  const factory TmdbCastPerson({
    required int id,
    required String name,
    @JsonKey(name: 'profile_path') required String? profilePath,
    @JsonKey(name: 'total_episode_count', defaultValue: 0) required int totalEpisodeCount,

    /// Defaulted because this one model is parsed from three differently shaped endpoints (the two
    /// aggregate-credits ones and the flat episode-credits one, whose `guest_stars` entries omit
    /// it). Only `id` and `profilePath` are actually read, so a throw here would be pure collateral.
    @JsonKey(name: 'order', defaultValue: 0) required int order,

    /// Set by the flat credits endpoints (movie credits, episode credits and guest stars).
    String? character,

    /// Set by the aggregate credits endpoints (show, season) instead of [character]: one entry per
    /// character the person played, with the number of episodes for each.
    @Default(<TmdbRole>[]) List<TmdbRole> roles,
    @JsonKey(name: 'known_for_department') String? knownForDepartment,
  }) = _TmdbCastPerson;

  factory TmdbCastPerson.fromJson(Map<String, dynamic> json) => _$TmdbCastPersonFromJson(json);
}

/// One `roles[]` entry of an aggregate cast credit. `credit_id` is deliberately not modelled.
@freezed
abstract class TmdbRole with _$TmdbRole {
  const factory TmdbRole({String? character, @JsonKey(name: 'episode_count') @Default(0) int episodeCount}) = _TmdbRole;

  factory TmdbRole.fromJson(Map<String, dynamic> json) => _$TmdbRoleFromJson(json);
}

@freezed
abstract class TmdbCrewPerson with _$TmdbCrewPerson {
  const factory TmdbCrewPerson({
    required int id,
    required String name,
    @JsonKey(name: 'profile_path') required String? profilePath,

    /// Set by the flat credits endpoints (movie, episode).
    String? job,
    String? department,

    /// Set by the aggregate credits endpoints (show, season) instead of [job]: one entry per job
    /// the person held, with the number of episodes for each.
    @Default(<TmdbJob>[]) List<TmdbJob> jobs,
  }) = _TmdbCrewPerson;

  factory TmdbCrewPerson.fromJson(Map<String, dynamic> json) => _$TmdbCrewPersonFromJson(json);
}

/// One `jobs[]` entry of an aggregate crew credit. `credit_id` is deliberately not modelled.
@freezed
abstract class TmdbJob with _$TmdbJob {
  const factory TmdbJob({String? job, @JsonKey(name: 'episode_count') @Default(0) int episodeCount}) = _TmdbJob;

  factory TmdbJob.fromJson(Map<String, dynamic> json) => _$TmdbJobFromJson(json);
}
