import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/http/response_decoding.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_external_ids.dart';

part 'person_details.freezed.dart';
part 'person_details.g.dart';

final _log = Logger('[API] [Tmdb] TmdbPersonCredit');

/// `/person/{id}` with `combined_credits` and `external_ids` appended.
@Freezed(toJson: false)
abstract class TmdbPersonDetails with _$TmdbPersonDetails {
  const factory TmdbPersonDetails({
    required int id,
    required String name,
    String? biography,
    String? birthday,
    String? deathday,
    @JsonKey(name: 'place_of_birth') String? placeOfBirth,
    String? homepage,
    @JsonKey(name: 'profile_path') String? profilePath,
    @JsonKey(name: 'imdb_id') String? imdbId,
    @JsonKey(name: 'known_for_department') String? knownForDepartment,
    @JsonKey(name: 'also_known_as') @Default(<String>[]) List<String> alsoKnownAs,
    @JsonKey(name: 'external_ids') TmdbExternalIds? externalIds,
    @JsonKey(name: 'combined_credits') TmdbCombinedCredits? combinedCredits,
  }) = _TmdbPersonDetails;

  factory TmdbPersonDetails.fromJson(Map<String, dynamic> json) => _$TmdbPersonDetailsFromJson(json);
}

/// The `combined_credits` object: every movie and show the person was credited on. Only the cast
/// list is read — the app has no use for crew credits, and a director's or producer's crew list
/// can be as long again as their cast list, so it is not even parsed.
///
/// The cast decodes tolerantly: one malformed credit (no `id`, no `media_type`) is skipped and
/// logged rather than failing the whole person, which would take the page down with it.
@Freezed(toJson: false)
abstract class TmdbCombinedCredits with _$TmdbCombinedCredits {
  const factory TmdbCombinedCredits({@JsonKey(fromJson: _castFromJson) @Default(<TmdbPersonCredit>[]) List<TmdbPersonCredit> cast}) =
      _TmdbCombinedCredits;

  factory TmdbCombinedCredits.fromJson(Map<String, dynamic> json) => _$TmdbCombinedCreditsFromJson(json);
}

List<TmdbPersonCredit> _castFromJson(List<dynamic>? rows) {
  return rows == null ? const [] : buildRowsTolerantly(rows, TmdbPersonCredit.fromJson, _log, 'person credit');
}

/// One credit of a person. [mediaType] is `movie` or `tv`; TMDB names the title `title` /
/// `release_date` for movies and `name` / `first_air_date` for shows, hence both pairs.
@Freezed(toJson: false)
abstract class TmdbPersonCredit with _$TmdbPersonCredit {
  const TmdbPersonCredit._();

  const factory TmdbPersonCredit({
    required int id,
    @JsonKey(name: 'media_type') required String mediaType,
    String? title,
    String? name,
    @JsonKey(name: 'release_date') String? releaseDate,
    @JsonKey(name: 'first_air_date') String? firstAirDate,
    @Default(0) double popularity,

    /// TMDB's community score, 0 when the title has no votes yet.
    @JsonKey(name: 'vote_average') double? voteAverage,

    /// Cast credits only.
    String? character,

    /// Crew credits only.
    String? job,
    @JsonKey(name: 'poster_path') String? posterPath,

    /// Show credits only.
    @JsonKey(name: 'episode_count') @Default(0) int episodeCount,
  }) = _TmdbPersonCredit;

  factory TmdbPersonCredit.fromJson(Map<String, dynamic> json) => _$TmdbPersonCreditFromJson(json);

  bool get isMovie => mediaType == 'movie';

  bool get isShow => mediaType == 'tv';

  /// [title] for a movie, [name] for a show.
  String? get displayTitle => isMovie ? title : name;

  /// [releaseDate] for a movie, [firstAirDate] for a show.
  String? get displayDate => isMovie ? releaseDate : firstAirDate;
}
