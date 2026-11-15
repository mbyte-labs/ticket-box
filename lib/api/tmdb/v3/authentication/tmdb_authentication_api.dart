import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/authentication/tmdb_auth_models.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';

/// TMDB's v3 user authentication: a request token the user approves in the browser, turned into a
/// session id the account endpoints accept as a `session_id` query parameter next to the app's own
/// bearer token.
///
/// Documentation: https://developer.themoviedb.org/reference/authentication-how-do-i-generate-a-session-id
class TmdbAuthenticationApi {
  static final _log = Logger('[API] [Tmdb] TmdbAuthenticationApi');
  static final _singleton = TmdbAuthenticationApi._internal();

  /// Resolved per call so a client installed with `TmdbHttpClient.forTesting` is picked up.
  Client get _client => TmdbHttpClient.instance;

  TmdbAuthenticationApi._internal();

  factory TmdbAuthenticationApi() {
    return _singleton;
  }

  /// The page where the user approves [requestToken]. TMDB then redirects to [redirectTo] with
  /// `request_token=…&approved=true` appended, or `denied=true` when the user refused.
  static Uri approvalUrl(String requestToken, Uri redirectTo) {
    return Uri.https('www.themoviedb.org', '/authenticate/$requestToken', {'redirect_to': redirectTo.toString()});
  }

  Future<TmdbRequestToken> createRequestToken() async {
    _log.fine('Requesting a TMDB request token');
    final json = await tmdbGetJsonMap(_client, tmdbUri('/3/authentication/token/new'), _log, 'request token');
    return TmdbRequestToken.fromJson(json);
  }

  /// Turns an approved [requestToken] into a session. An unapproved or expired token answers 401,
  /// which `TmdbHttpClient` throws as an `ApiUnauthorizedException`.
  Future<TmdbSession> createSession(String requestToken) async {
    _log.fine('Creating a TMDB session');
    final json = await tmdbPostJsonMap(_client, tmdbUri('/3/authentication/session/new'), {'request_token': requestToken}, _log, 'session');
    return TmdbSession.fromJson(json);
  }

  /// Revokes [sessionId] on TMDB's side. Logging out works without it; it only keeps the user's
  /// TMDB session list clean.
  Future<void> deleteSession(String sessionId) async {
    _log.fine('Deleting the TMDB session');
    await tmdbDeleteJsonMap(_client, tmdbUri('/3/authentication/session'), {'session_id': sessionId}, _log, 'session');
  }
}
