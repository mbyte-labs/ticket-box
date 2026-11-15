import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_account_models.dart';
import 'package:ticketbox/api/tmdb/v3/authentication/tmdb_auth_models.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_page.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';

/// `/3/account` and the user's lists under `/3/account/{account_id}/…`: rated titles, the watchlist
/// and the favorites, plus the two writes that add to or remove from the latter two.
///
/// Every call carries the user's `session_id` as a query parameter; the app's bearer token stays on
/// the request as well. The lists are paged 20 per page in `created_at` order; the v3 rows carry no
/// "added at" timestamp.
///
/// Documentation: https://developer.themoviedb.org/reference/account-details
class TmdbAccountApi {
  static final _log = Logger('[API] [Tmdb] TmdbAccountApi');
  static final _singleton = TmdbAccountApi._internal();

  /// Resolved per call so a client installed with `TmdbHttpClient.forTesting` is picked up.
  Client get _client => TmdbHttpClient.instance;

  TmdbAccountApi._internal();

  factory TmdbAccountApi() {
    return _singleton;
  }

  Future<TmdbAccountDetails> get(String sessionId) async {
    final json = await tmdbGetJsonMap(_client, tmdbUri('/3/account', {'session_id': sessionId}), _log, 'account');
    return TmdbAccountDetails.fromJson(json);
  }

  Future<TmdbPage<TmdbRatedMovie>> ratedMovies(int accountId, String sessionId, [int page = 1]) async {
    final json = await _list(accountId, sessionId, 'rated/movies', page);
    return TmdbPage.fromJson(json, TmdbRatedMovie.fromJson);
  }

  Future<TmdbPage<TmdbRatedShow>> ratedShows(int accountId, String sessionId, [int page = 1]) async {
    final json = await _list(accountId, sessionId, 'rated/tv', page);
    return TmdbPage.fromJson(json, TmdbRatedShow.fromJson);
  }

  Future<TmdbPage<TmdbRatedEpisode>> ratedEpisodes(int accountId, String sessionId, [int page = 1]) async {
    final json = await _list(accountId, sessionId, 'rated/tv/episodes', page);
    return TmdbPage.fromJson(json, TmdbRatedEpisode.fromJson);
  }

  Future<TmdbPage<TmdbMovieListItem>> watchlistMovies(int accountId, String sessionId, [int page = 1]) async {
    final json = await _list(accountId, sessionId, 'watchlist/movies', page);
    return TmdbPage.fromJson(json, TmdbMovieListItem.fromJson);
  }

  Future<TmdbPage<TmdbShowListItem>> watchlistShows(int accountId, String sessionId, [int page = 1]) async {
    final json = await _list(accountId, sessionId, 'watchlist/tv', page);
    return TmdbPage.fromJson(json, TmdbShowListItem.fromJson);
  }

  Future<TmdbPage<TmdbMovieListItem>> favoriteMovies(int accountId, String sessionId, [int page = 1]) async {
    final json = await _list(accountId, sessionId, 'favorite/movies', page);
    return TmdbPage.fromJson(json, TmdbMovieListItem.fromJson);
  }

  Future<TmdbPage<TmdbShowListItem>> favoriteShows(int accountId, String sessionId, [int page = 1]) async {
    final json = await _list(accountId, sessionId, 'favorite/tv', page);
    return TmdbPage.fromJson(json, TmdbShowListItem.fromJson);
  }

  /// Adds ([listed] true) or removes a movie or show on the TMDB watchlist.
  Future<TmdbStatusResponse> setWatchlist({
    required int accountId,
    required String sessionId,
    required TmdbMediaType mediaType,
    required int mediaId,
    required bool listed,
  }) async {
    _log.fine('${listed ? 'Adding' : 'Removing'} ${mediaType.apiName} $mediaId ${listed ? 'to' : 'from'} the TMDB watchlist');
    final json = await tmdbPostJsonMap(
      _client,
      tmdbUri('/3/account/$accountId/watchlist', {'session_id': sessionId}),
      {'media_type': mediaType.apiName, 'media_id': mediaId, 'watchlist': listed},
      _log,
      'watchlist ${mediaType.apiName} $mediaId',
    );
    return TmdbStatusResponse.fromJson(json);
  }

  /// Marks ([favorite] true) or unmarks a movie or show as a TMDB favorite.
  Future<TmdbStatusResponse> setFavorite({
    required int accountId,
    required String sessionId,
    required TmdbMediaType mediaType,
    required int mediaId,
    required bool favorite,
  }) async {
    _log.fine('${favorite ? 'Adding' : 'Removing'} ${mediaType.apiName} $mediaId ${favorite ? 'to' : 'from'} the TMDB favorites');
    final json = await tmdbPostJsonMap(
      _client,
      tmdbUri('/3/account/$accountId/favorite', {'session_id': sessionId}),
      {'media_type': mediaType.apiName, 'media_id': mediaId, 'favorite': favorite},
      _log,
      'favorite ${mediaType.apiName} $mediaId',
    );
    return TmdbStatusResponse.fromJson(json);
  }

  Future<Map<String, dynamic>> _list(int accountId, String sessionId, String list, int page) {
    final uri = tmdbUri('/3/account/$accountId/$list', {'session_id': sessionId, 'page': '$page', 'sort_by': 'created_at.asc'});
    _log.finer('Downloading account $list, page $page');
    return tmdbGetJsonMap(_client, uri, _log, 'account $list');
  }
}
