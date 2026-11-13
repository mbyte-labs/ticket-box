import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/api_keys.dart';
import 'package:ticketbox/api/api_provider.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/http/timeout_client.dart';

/// The one HTTP client every TMDB wrapper sends through.
///
/// Authenticates with the v4 read access token as a bearer header — the v3 endpoints accept it, and
/// it keeps the key out of URLs that end up in warning logs. Retries 429s (honouring `retry-after`),
/// 5xx responses and transient transport failures with `RetryClient`'s backoff. There is no shared
/// rate-limit gate: TMDB's practical ceiling (~40–50 requests/s per IP) is far above the app's
/// bounded fan-out (at most 8 requests in flight), so a 429 is an anomaly to back off from, not a
/// budget to coordinate.
class TmdbHttpClient extends BaseClient {
  static final _log = Logger('[API] [Tmdb] TmdbHttpClient');

  static TmdbHttpClient? _instance;

  /// The process-wide client. Tests substitute one via [TmdbHttpClient.forTesting].
  static TmdbHttpClient get instance => _instance ??= TmdbHttpClient._(Client(), _attemptTimeout);

  /// Used when TMDB sends no usable `retry-after`.
  static const int _fallbackRetryAfterSeconds = 2;

  /// Upper bound on how long a `retry-after` may hold a request.
  static const int _maxRetryAfterSeconds = 60;

  static const Duration _attemptTimeout = Duration(seconds: 30);

  final Client _innerClient;
  final Duration _timeout;

  late final RetryClient _retryClient = RetryClient(
    TimeoutClient(_innerClient, _timeout),
    retries: 3,
    when: (BaseResponse response) => response.statusCode == 429 || response.statusCode >= 500,
    whenError: (Object error, StackTrace stackTrace) => error is ClientException || error is TimeoutException,
    onRetry: _onRetry,
  );

  TmdbHttpClient._(this._innerClient, this._timeout);

  /// A client over a caller-supplied transport, for tests. Also installs it as [instance] so the
  /// singleton wrappers pick it up; call [resetForTesting] afterwards.
  @visibleForTesting
  factory TmdbHttpClient.forTesting(Client innerClient, {Duration? attemptTimeout}) {
    final client = TmdbHttpClient._(innerClient, attemptTimeout ?? _attemptTimeout);
    _instance = client;
    return client;
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }

  @override
  void close() {
    _retryClient.close();
    super.close();
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    request.headers['Authorization'] = 'Bearer ${ApiKeysProvider.getTmDb4Key()}';
    request.headers['Accept'] = 'application/json';

    final response = await _retryClient.send(request);
    await _interceptResponse(response);
    return response;
  }

  /// Maps the terminal failure codes to typed exceptions. 404 is deliberately left to each wrapper,
  /// which usually returns `null` for a missing item.
  Future<void> _interceptResponse(StreamedResponse response) async {
    final statusCode = response.statusCode;
    final url = response.request?.url.replace(query: '').toString();

    if (statusCode == 401) {
      // The body tells an invalid API key (7) apart from a bad user session (3, 17). It is read
      // here because the response is thrown away anyway.
      final body = await _readBody(response);
      final tmdbStatusCode = _tmdbStatusCode(body);
      _log.warning('TMDB returned 401 (status_code $tmdbStatusCode) for $url');
      throw ApiUnauthorizedException(ApiProvider.tmdb, body, 'TMDB - invalid or missing access token', tmdbStatusCode: tmdbStatusCode);
    }
    if (statusCode == 429) {
      final retryAfter = _retryAfterSeconds(response);
      _log.warning('TMDB returned 429 for $url after retries, retry-after ${retryAfter}s');
      throw ApiToManyRequestsException(ApiProvider.tmdb, statusCode, 'TMDB - too many requests', retryAfter);
    }
    if (statusCode >= 500) {
      _log.warning('TMDB returned $statusCode for $url');
      throw ApiDownException(ApiProvider.tmdb, statusCode, response.reasonPhrase, 'TMDB - service unavailable');
    }
  }

  static Future<String?> _readBody(StreamedResponse response) async {
    try {
      return (await Response.fromStream(response)).body;
    } catch (e) {
      _log.fine('Could not read the body of a 401 response: $e');
      return null;
    }
  }

  static int? _tmdbStatusCode(String? body) {
    if (body == null || body.isEmpty) {
      return null;
    }
    try {
      final decoded = json.decode(body);
      return decoded is Map ? (decoded['status_code'] as num?)?.toInt() : null;
    } on FormatException {
      return null;
    }
  }

  static Future<void> _onRetry(BaseRequest request, BaseResponse? response, int retries) async {
    if (response != null && response.statusCode == 429) {
      final seconds = _retryAfterSeconds(response);
      _log.fine('TMDB rate limited ${request.url.path}, waiting ${seconds}s before retry ${retries + 1}');
      await Future<void>.delayed(Duration(seconds: seconds));
    }
  }

  /// `package:http` lower-cases response header names, hence `retry-after`.
  static int _retryAfterSeconds(BaseResponse response) {
    final rawValue = response.headers['retry-after'];
    if (rawValue == null) {
      return _fallbackRetryAfterSeconds;
    }
    final seconds = int.tryParse(rawValue.trim()) ?? _fallbackRetryAfterSeconds;
    return seconds > _maxRetryAfterSeconds ? _maxRetryAfterSeconds : seconds;
  }
}
