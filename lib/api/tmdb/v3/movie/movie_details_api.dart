import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/movie/movie_details.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';

/// `/3/movie/{id}` with everything the details page renders appended into the one request.
///
/// Eight of TMDB's twenty `append_to_response` keys: credits, external ids, videos, images, watch
/// providers, recommendations, similar titles and release dates. The response is the movie's
/// snapshot — what the library stores verbatim (pruned) and renders offline.
///
/// Documentation: https://developer.themoviedb.org/reference/movie-details
class TmdbMovieDetailsApi {
  static final _log = Logger('[API] [Tmdb] TmdbMovieDetailsApi');
  static final _singleton = TmdbMovieDetailsApi._internal();

  static const List<String> appended = [
    'credits',
    'external_ids',
    'videos',
    'images',
    'watch/providers',
    'recommendations',
    'similar',
    'release_dates',
  ];

  /// `language=en-US` alone would filter the appended `images` down to English ones; `null`
  /// keeps the language-less posters and backdrops TMDB files most artwork under.
  static const Map<String, String> query = {
    'append_to_response': 'credits,external_ids,videos,images,watch/providers,recommendations,similar,release_dates',
    'include_image_language': 'en,null',
  };

  final Client _client = TmdbHttpClient.instance;

  TmdbMovieDetailsApi._internal();

  factory TmdbMovieDetailsApi() {
    return _singleton;
  }

  /// The decoded body as TMDB sent it. Returns `null` when TMDB has no movie with that id.
  Future<Map<String, dynamic>?> getRaw(int tmdbId) async {
    final uri = tmdbUri('/3/movie/$tmdbId', query);
    _log.finer('Downloading movie $tmdbId');
    return tmdbGetJsonMapOrNull(_client, uri, _log, 'movie $tmdbId');
  }

  /// [getRaw], typed. Returns `null` when TMDB has no movie with that id.
  Future<TmdbMovieDetails?> get(int tmdbId) async {
    final json = await getRaw(tmdbId);
    return json == null ? null : TmdbMovieDetails.fromJson(json);
  }
}
