import 'dart:convert';

import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/api_provider.dart';
import 'package:ticketbox/api/exception.dart';

/// Shared decoding for API responses.
///
/// Three failure classes these helpers close off at one place instead of per API:
/// - `response.body` falls back to latin1 when the Content-Type carries no charset, mojibaking any
///   non-ASCII text — decode from [Response.bodyBytes] as UTF-8 instead.
/// - `json.decode(...) as List` / implicit casts turn an HTML error page served with HTTP 200 into a
///   `TypeError` (an `Error`, invisible to `on Exception`) — guard with `is` and throw a contextual
///   [ApiException] that classifies properly.
/// - One malformed row aborting a whole workflow — [buildRowsTolerantly] skips and logs per row.

/// Decodes a JSON array body, throwing a classified [ApiException] when the payload is not an array.
List<dynamic> decodeJsonListBody(Response response, ApiProvider provider, String context) {
  final decoded = _decode(response, provider, context);
  if (decoded is! List) {
    throw ApiException(provider, response.statusCode, _truncate(response.body), '${provider.name} - $context: expected a JSON array');
  }
  return decoded;
}

/// Decodes a JSON object body, throwing a classified [ApiException] when the payload is not an object.
Map<String, dynamic> decodeJsonMapBody(Response response, ApiProvider provider, String context) {
  final decoded = _decode(response, provider, context);
  if (decoded is! Map<String, dynamic>) {
    throw ApiException(provider, response.statusCode, _truncate(response.body), '${provider.name} - $context: expected a JSON object');
  }
  return decoded;
}

/// Builds one result per JSON row, skipping (and logging) rows that are not objects, fail to build,
/// or build to null — one bad row must never abort a whole list.
///
/// The bare `catch` is intentional: decode faults are usually `TypeError`s, which `on Exception`
/// would let straight through.
List<T> buildRowsTolerantly<T>(List<dynamic> rows, T? Function(Map<String, dynamic> row) build, Logger log, String context) {
  final results = <T>[];
  for (final row in rows) {
    if (row is! Map<String, dynamic>) {
      log.severe('Skipping a $context row that is not a JSON object: $row');
      continue;
    }

    try {
      final built = build(row);
      if (built != null) {
        results.add(built);
      }
    } catch (e, stackTrace) {
      log.severe('Could not decode a $context row, skipping: $row', e, stackTrace);
    }
  }
  return results;
}

dynamic _decode(Response response, ApiProvider provider, String context) {
  try {
    return json.decode(utf8.decode(response.bodyBytes));
  } on FormatException catch (e) {
    throw ApiException(provider, response.statusCode, _truncate(response.body), '${provider.name} - $context: body is not valid JSON ($e)');
  }
}

String _truncate(String body) => body.length <= 200 ? body : '${body.substring(0, 199)}…';
