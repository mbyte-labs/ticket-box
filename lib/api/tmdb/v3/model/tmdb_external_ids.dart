import 'package:freezed_annotation/freezed_annotation.dart';

part 'tmdb_external_ids.freezed.dart';
part 'tmdb_external_ids.g.dart';

/// The `external_ids` object TMDB appends to movies, shows, episodes and people. Every id is
/// optional: TMDB sends `null` for the ones it does not know.
@Freezed(toJson: false)
abstract class TmdbExternalIds with _$TmdbExternalIds {
  const factory TmdbExternalIds({
    @JsonKey(name: 'imdb_id') String? imdbId,
    @JsonKey(name: 'tvdb_id') int? tvdbId,
    @JsonKey(name: 'wikidata_id') String? wikidataId,
    @JsonKey(name: 'facebook_id') String? facebookId,
    @JsonKey(name: 'instagram_id') String? instagramId,
    @JsonKey(name: 'twitter_id') String? twitterId,
  }) = _TmdbExternalIds;

  factory TmdbExternalIds.fromJson(Map<String, dynamic> json) => _$TmdbExternalIdsFromJson(json);
}
