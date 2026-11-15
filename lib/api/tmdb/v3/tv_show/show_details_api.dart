import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details.dart';

/// `/3/tv/{id}` with everything the show page renders appended, plus optionally full seasons.
///
/// Eight of TMDB's twenty `append_to_response` keys are fixed (aggregate credits, external ids,
/// content ratings, videos, images, watch providers, recommendations, similar), which leaves
/// [maxAppendedSeasons] `season/N` slots per root request. [getSeasonsRaw] fetches seasons with
/// nothing else appended, twenty at a time, for the rest of a long show.
///
/// Documentation: https://developer.themoviedb.org/reference/tv-series-details
class TmdbShowDetailsApi {
  static final _log = Logger('[API] [Tmdb] TmdbShowDetailsApi');
  static final _singleton = TmdbShowDetailsApi._internal();

  /// TMDB's `append_to_response` limit.
  static const int maxAppendKeys = 20;

  /// `season/N` slots left on a root request after the fixed appends.
  static const int maxAppendedSeasons = maxAppendKeys - 8;

  static const List<String> appended = [
    'aggregate_credits',
    'external_ids',
    'content_ratings',
    'videos',
    'images',
    'watch/providers',
    'recommendations',
    'similar',
  ];

  /// See `TmdbMovieDetailsApi.query` for why `include_image_language` is sent.
  static const String includeImageLanguage = 'en,null';

  final Client _client = TmdbHttpClient.instance;

  TmdbShowDetailsApi._internal();

  factory TmdbShowDetailsApi() {
    return _singleton;
  }

  /// The decoded root body, with the full payload of each season in [appendSeasons] under its
  /// `season/N` key. Throws an [ArgumentError] when more than [maxAppendedSeasons] are requested;
  /// returns `null` when TMDB has no show with that id.
  Future<Map<String, dynamic>?> getRaw(int tmdbId, {Iterable<int> appendSeasons = const []}) async {
    final seasons = _sorted(appendSeasons);
    if (seasons.length > maxAppendedSeasons) {
      throw ArgumentError.value(
        seasons.length,
        'appendSeasons',
        'TMDB allows $maxAppendKeys append_to_response keys; with the ${appended.length} fixed ones at most $maxAppendedSeasons seasons fit',
      );
    }

    final keys = [...appended, for (final season in seasons) 'season/$season'];
    final uri = tmdbUri('/3/tv/$tmdbId', {'append_to_response': keys.join(','), 'include_image_language': includeImageLanguage});
    _log.finer('Downloading show $tmdbId with ${seasons.length} appended seasons');
    return tmdbGetJsonMapOrNull(_client, uri, _log, 'show $tmdbId');
  }

  /// Only seasons: the root body with nothing but `season/N` keys appended, up to [maxAppendKeys]
  /// of them. Throws an [ArgumentError] on an empty or too long list; returns `null` on a 404.
  Future<Map<String, dynamic>?> getSeasonsRaw(int tmdbId, Iterable<int> seasons) async {
    final sorted = _sorted(seasons);
    if (sorted.isEmpty || sorted.length > maxAppendKeys) {
      throw ArgumentError.value(sorted.length, 'seasons', 'between 1 and $maxAppendKeys seasons fit one seasons-only request');
    }

    final keys = [for (final season in sorted) 'season/$season'];
    final uri = tmdbUri('/3/tv/$tmdbId', {'append_to_response': keys.join(',')});
    _log.finer('Downloading ${sorted.length} season(s) of show $tmdbId');
    return tmdbGetJsonMapOrNull(_client, uri, _log, 'show $tmdbId seasons');
  }

  /// [getRaw], typed: the season payloads land in `TmdbShowDetails.appendedSeasons`.
  Future<TmdbShowDetails?> get(int tmdbId, {Iterable<int> appendSeasons = const []}) async {
    final json = await getRaw(tmdbId, appendSeasons: appendSeasons);
    return json == null ? null : TmdbShowDetails.fromJson(json);
  }

  static List<int> _sorted(Iterable<int> seasons) => seasons.toSet().toList()..sort();
}
