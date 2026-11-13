import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_page.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';

/// `/3/trending/{movie|tv}/week`.
///
/// Documentation: https://developer.themoviedb.org/reference/trending-movies
class TmdbTrendingApi {
  static final _log = Logger('[API] [Tmdb] TmdbTrendingApi');
  static final _singleton = TmdbTrendingApi._internal();

  final Client _client = TmdbHttpClient.instance;

  TmdbTrendingApi._internal();

  factory TmdbTrendingApi() {
    return _singleton;
  }

  Future<TmdbPage<TmdbMovieListItem>> movies([int page = 1]) async {
    final json = await _get('movie', page);
    return TmdbPage.fromJson(json, TmdbMovieListItem.fromJson);
  }

  Future<TmdbPage<TmdbShowListItem>> shows([int page = 1]) async {
    final json = await _get('tv', page);
    return TmdbPage.fromJson(json, TmdbShowListItem.fromJson);
  }

  Future<Map<String, dynamic>> _get(String kind, int page) {
    final uri = tmdbUri('/3/trending/$kind/week', {'page': '$page'});
    _log.finer('Downloading trending $kind, page $page');
    return tmdbGetJsonMap(_client, uri, _log, 'trending $kind');
  }
}
