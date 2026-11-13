import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/authentication/tmdb_auth_models.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';

/// The user's own ratings on TMDB: `POST`/`DELETE /3/movie/{id}/rating`, `/3/tv/{id}/rating` and
/// `/3/tv/{id}/season/{s}/episode/{e}/rating`. A value is 0.5–10 in half steps; the app's whole
/// numbers are sent as they are.
///
/// Note that TMDB removes a title from the user's watchlist when it is rated — an account setting
/// on their side, on by default.
///
/// Documentation: https://developer.themoviedb.org/reference/movie-add-rating
class TmdbRatingApi {
  static final _log = Logger('[API] [Tmdb] TmdbRatingApi');
  static final _singleton = TmdbRatingApi._internal();

  /// Resolved per call so a client installed with `TmdbHttpClient.forTesting` is picked up.
  Client get _client => TmdbHttpClient.instance;

  TmdbRatingApi._internal();

  factory TmdbRatingApi() {
    return _singleton;
  }

  Future<TmdbStatusResponse> rateMovie(int tmdbId, double value, String sessionId) =>
      _rate('/3/movie/$tmdbId/rating', value, sessionId, 'movie $tmdbId rating');

  Future<TmdbStatusResponse> rateShow(int tmdbId, double value, String sessionId) =>
      _rate('/3/tv/$tmdbId/rating', value, sessionId, 'show $tmdbId rating');

  Future<TmdbStatusResponse> rateEpisode(int showTmdbId, int season, int episode, double value, String sessionId) =>
      _rate('/3/tv/$showTmdbId/season/$season/episode/$episode/rating', value, sessionId, 'show $showTmdbId S${season}E$episode rating');

  Future<TmdbStatusResponse> deleteMovieRating(int tmdbId, String sessionId) =>
      _unrate('/3/movie/$tmdbId/rating', sessionId, 'movie $tmdbId rating');

  Future<TmdbStatusResponse> deleteShowRating(int tmdbId, String sessionId) =>
      _unrate('/3/tv/$tmdbId/rating', sessionId, 'show $tmdbId rating');

  Future<TmdbStatusResponse> deleteEpisodeRating(int showTmdbId, int season, int episode, String sessionId) =>
      _unrate('/3/tv/$showTmdbId/season/$season/episode/$episode/rating', sessionId, 'show $showTmdbId S${season}E$episode rating');

  Future<TmdbStatusResponse> _rate(String path, double value, String sessionId, String context) async {
    _log.fine('Sending $context $value to TMDB');
    final json = await tmdbPostJsonMap(_client, tmdbUri(path, {'session_id': sessionId}), {'value': value}, _log, context);
    return TmdbStatusResponse.fromJson(json);
  }

  Future<TmdbStatusResponse> _unrate(String path, String sessionId, String context) async {
    _log.fine('Removing $context from TMDB');
    final json = await tmdbDeleteJsonMap(_client, tmdbUri(path, {'session_id': sessionId}), null, _log, context);
    return TmdbStatusResponse.fromJson(json);
  }
}
