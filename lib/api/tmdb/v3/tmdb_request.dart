import 'dart:convert';

import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/api_provider.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/http/response_decoding.dart';
import 'package:ticketbox/api/tmdb/tmdb_configuration.dart';

/// The status handling every TMDB v3 wrapper shares.
///
/// 401/429/5xx never reach here — `TmdbHttpClient` already turned them into typed exceptions — so
/// what is left is 200/201 (decode), 404 (the item does not exist) and the odd 4xx (throw).

const Map<String, String> _jsonBodyHeaders = {'Content-Type': 'application/json;charset=utf-8'};

/// Builds a v3 URL. Every wrapper asks for English; [extra] adds endpoint-specific parameters.
Uri tmdbUri(String path, [Map<String, String> extra = const {}]) {
  return Uri.https(TmDbApi.url, path, <String, String>{'language': 'en-US', ...extra});
}

/// GETs a single item. Returns `null` on 404 — a removed or merged TMDB entry — and throws an
/// [ApiException] on any other non-200 answer.
Future<Map<String, dynamic>?> tmdbGetJsonMapOrNull(Client client, Uri uri, Logger log, String context) async {
  final response = await client.get(uri);
  if (response.statusCode == 404) {
    log.info('TMDB has no $context');
    return null;
  }
  return _decodeOrThrow(response, context);
}

/// GETs an endpoint that must answer, such as a list. Throws an [ApiNotFoundException] on 404 so
/// callers that want "empty" for a vanished parent can catch that one case.
Future<Map<String, dynamic>> tmdbGetJsonMap(Client client, Uri uri, Logger log, String context) async {
  final response = await client.get(uri);
  if (response.statusCode == 404) {
    log.info('TMDB has no $context');
    throw ApiNotFoundException(ApiProvider.tmdb, response.body, 'TMDB - $context not found');
  }
  return _decodeOrThrow(response, context);
}

/// POSTs a JSON [body] to an account endpoint (ratings, watchlist, favorites, sessions). TMDB answers
/// 201 when it created something and 200 when it updated it; both decode. A 404 — the title no
/// longer exists — throws an [ApiNotFoundException] so callers can drop the write instead of retrying.
Future<Map<String, dynamic>> tmdbPostJsonMap(Client client, Uri uri, Map<String, dynamic> body, Logger log, String context) async {
  final response = await client.post(uri, headers: _jsonBodyHeaders, body: json.encode(body));
  return _decodeWriteOrThrow(response, log, context);
}

/// DELETEs with an optional JSON [body] (TMDB's session delete carries the session id in the body).
Future<Map<String, dynamic>> tmdbDeleteJsonMap(Client client, Uri uri, Map<String, dynamic>? body, Logger log, String context) async {
  final response = await client.delete(uri, headers: body == null ? null : _jsonBodyHeaders, body: body == null ? null : json.encode(body));
  return _decodeWriteOrThrow(response, log, context);
}

Map<String, dynamic> _decodeOrThrow(Response response, String context) {
  if (response.statusCode != 200) {
    throw ApiException(ApiProvider.tmdb, response.statusCode, response.body, 'TMDB - error downloading $context');
  }
  return decodeJsonMapBody(response, ApiProvider.tmdb, context);
}

Map<String, dynamic> _decodeWriteOrThrow(Response response, Logger log, String context) {
  if (response.statusCode == 404) {
    log.info('TMDB has no $context');
    throw ApiNotFoundException(ApiProvider.tmdb, response.body, 'TMDB - $context not found');
  }
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw ApiException(ApiProvider.tmdb, response.statusCode, response.body, 'TMDB - error writing $context');
  }
  return decodeJsonMapBody(response, ApiProvider.tmdb, context);
}
