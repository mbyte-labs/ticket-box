import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_page.dart';
import 'package:ticketbox/api/tmdb/v3/search/search_result.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';

/// `/3/search/{movie|tv|multi}`.
///
/// Documentation: https://developer.themoviedb.org/reference/search-multi
class TmdbSearchApi {
  static final _log = Logger('[API] [Tmdb] TmdbSearchApi');
  static final _singleton = TmdbSearchApi._internal();

  final Client _client = TmdbHttpClient.instance;

  TmdbSearchApi._internal();

  factory TmdbSearchApi() {
    return _singleton;
  }

  Future<TmdbPage<TmdbSearchResult>> searchMovies(String query, [int page = 1]) async {
    final json = await _search('movie', query, page);
    return TmdbPage.fromJson(json, (row) => TmdbSearchResult.movie(TmdbMovieListItem.fromJson(row)));
  }

  Future<TmdbPage<TmdbSearchResult>> searchShows(String query, [int page = 1]) async {
    final json = await _search('tv', query, page);
    return TmdbPage.fromJson(json, (row) => TmdbSearchResult.show(TmdbShowListItem.fromJson(row)));
  }

  /// Movies and shows in one ranked list; person hits are dropped, so a page can come back with
  /// fewer than 20 rows while `totalResults` still counts them.
  Future<TmdbPage<TmdbSearchResult>> searchMulti(String query, [int page = 1]) async {
    final json = await _search('multi', query, page);
    return TmdbPage<TmdbSearchResult?>.fromJson(json, TmdbSearchResult.fromMultiJson).map((result) => result);
  }

  Future<Map<String, dynamic>> _search(String kind, String query, int page) {
    final uri = tmdbUri('/3/search/$kind', {'query': query, 'page': '$page', 'include_adult': 'false'});
    _log.finer('Searching $kind for "$query", page $page');
    return tmdbGetJsonMap(_client, uri, _log, '$kind search results');
  }
}
