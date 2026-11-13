import 'dart:async';

import 'package:http/http.dart';

/// Caps each individual attempt so a stalled connection surfaces as a [TimeoutException] instead of
/// hanging a request forever (there is no other timeout on the socket).
///
/// Two stalls are covered: `send()` caps connect + response headers (retryable — it throws inside
/// `RetryClient`), and the body stream gets an idle timeout that resets on every chunk, so a large
/// but flowing body is fine while a stream that stops mid-body errors. A body stall is NOT retried:
/// draining happens in the caller (`Response.fromStream`) after `RetryClient` has already returned,
/// so it surfaces from the API call itself and classifies as a network error.
class TimeoutClient extends BaseClient {
  TimeoutClient(this._inner, this._timeout);

  final Client _inner;
  final Duration _timeout;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final response = await _inner.send(request).timeout(_timeout);

    final guardedStream = response.stream.timeout(
      _timeout,
      onTimeout: (sink) {
        sink.addError(TimeoutException('Response body stalled', _timeout));
        sink.close();
      },
    );

    return StreamedResponse(
      ByteStream(guardedStream),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
