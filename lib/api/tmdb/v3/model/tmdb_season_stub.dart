import 'package:freezed_annotation/freezed_annotation.dart';

part 'tmdb_season_stub.freezed.dart';
part 'tmdb_season_stub.g.dart';

/// One entry of `seasons[]` on `/tv/{id}` — the season's header without its episodes.
@Freezed(toJson: false)
abstract class TmdbSeasonStub with _$TmdbSeasonStub {
  const factory TmdbSeasonStub({
    required int id,
    @JsonKey(name: 'season_number') required int seasonNumber,
    @JsonKey(name: 'episode_count') @Default(0) int episodeCount,
    @JsonKey(name: 'air_date') String? airDate,
    String? name,
    String? overview,
    @JsonKey(name: 'poster_path') String? posterPath,
    @JsonKey(name: 'vote_average') double? voteAverage,
  }) = _TmdbSeasonStub;

  factory TmdbSeasonStub.fromJson(Map<String, dynamic> json) => _$TmdbSeasonStubFromJson(json);
}
