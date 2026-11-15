import 'package:freezed_annotation/freezed_annotation.dart';

part 'tmdb_episode_stub.freezed.dart';
part 'tmdb_episode_stub.g.dart';

/// The `last_episode_to_air` / `next_episode_to_air` objects on `/tv/{id}`.
///
/// `air_date` and `runtime` are null for episodes TMDB has not scheduled yet; `episode_type` is
/// one of `standard`, `finale`, `mid_season` (see `EpisodeType` in `lib/common/model`).
@Freezed(toJson: false)
abstract class TmdbEpisodeStub with _$TmdbEpisodeStub {
  const factory TmdbEpisodeStub({
    required int id,
    @JsonKey(name: 'season_number') required int seasonNumber,
    @JsonKey(name: 'episode_number') required int episodeNumber,
    @JsonKey(name: 'air_date') String? airDate,
    String? name,
    @JsonKey(name: 'episode_type') String? episodeType,
    int? runtime,
  }) = _TmdbEpisodeStub;

  factory TmdbEpisodeStub.fromJson(Map<String, dynamic> json) => _$TmdbEpisodeStubFromJson(json);
}
