import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';
import 'package:ticketbox/api/http/timeout_client.dart';

/// The HTTP client that fetches image bytes from TMDB's image CDN (`image.tmdb.org`) — for the
/// artwork download queue and the browse cache alike.
///
/// Deliberately not `TmdbHttpClient`. That one is the JSON API client: it sends the app's bearer
/// token with every request (a credential the image CDN has no use for and should never see),
/// asks for `application/json`, and turns 429 / 5xx into the typed API exceptions the wrappers
/// expect. An image fetch wants `Accept: image/*`, no credential and the plain status code back,
/// because the queue persists its own retries (attempts, back-off, the breaker) on the job row;
/// only one immediate retry for a transient blip lives here, on top of the per-attempt timeout.
class ImageDownloadClient extends BaseClient {
  static ImageDownloadClient? _instance;

  /// The process-wide client. Tests substitute one via [ImageDownloadClient.forTesting].
  static ImageDownloadClient get instance => _instance ??= ImageDownloadClient._(Client(), _attemptTimeout);

  static const Duration _attemptTimeout = Duration(seconds: 30);

  final Client _innerClient;
  final Duration _timeout;

  late final RetryClient _retryClient = RetryClient(
    TimeoutClient(_innerClient, _timeout),
    retries: 1,
    when: (BaseResponse response) => response.statusCode == 429 || response.statusCode >= 500,
    whenError: (Object error, StackTrace stackTrace) => error is ClientException || error is TimeoutException,
  );

  ImageDownloadClient._(this._innerClient, this._timeout);

  /// A client over a caller-supplied transport, for tests. Also installs it as [instance] so the
  /// worker and the browse cache pick it up; call [resetForTesting] afterwards.
  @visibleForTesting
  factory ImageDownloadClient.forTesting(Client innerClient, {Duration? attemptTimeout}) {
    final client = ImageDownloadClient._(innerClient, attemptTimeout ?? _attemptTimeout);
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
  Future<StreamedResponse> send(BaseRequest request) {
    request.headers['Accept'] = 'image/*';
    return _retryClient.send(request);
  }
}
