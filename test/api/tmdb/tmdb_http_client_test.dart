import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/api_keys.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';

/// The retry and classification contract every TMDB wrapper leans on.
///
/// The tests that exhaust the retries run under [fakeAsync] so the back-off and `retry-after`
/// waits cost nothing. The ones that end in a 200 cannot: reading the body goes through
/// `Stream.timeout` (the body-stall guard in `TimeoutClient`), which never completes under fake
/// time, so those two run in real time with `retry-after: 0` and pay only `RetryClient`'s
/// sub-second back-off.
void main() {
  final url = Uri.parse('https://api.themoviedb.org/3/tv/1399');

  tearDown(TmdbHttpClient.resetForTesting);

  /// Runs [body] under fake time, flushing every timer the retry chain schedules, and returns
  /// the error it ended in. Only for requests that fail: a successful body read never completes
  /// under fake time (see the file comment).
  Object runToFailureWithFakeTime(Future<void> Function() body) {
    Object? error;
    fakeAsync((async) {
      body().then<void>(
        (_) {},
        onError: (Object e) {
          error = e;
        },
      );
      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
    });
    expect(error, isNotNull, reason: 'the request neither failed nor completed within fake time');
    return error!;
  }

  test('every request carries the v4 read token as a bearer header and asks for JSON', () async {
    Request? seen;
    final client = TmdbHttpClient.forTesting(
      MockClient((request) async {
        seen = request;
        return Response('{}', 200);
      }),
    );

    await client.get(url);

    expect(seen!.headers['Authorization'], 'Bearer ${ApiKeysProvider.getTmDb4Key()}');
    expect(seen!.headers['Accept'], 'application/json');
  });

  test('the singleton hands out the client installed for testing', () {
    final client = TmdbHttpClient.forTesting(MockClient((request) async => Response('{}', 200)));

    expect(TmdbHttpClient.instance, same(client));
  });

  test('a 404 passes through untouched so the wrapper can answer null', () async {
    final client = TmdbHttpClient.forTesting(MockClient((request) async => Response('{"status_code":34}', 404)));

    final response = await client.get(url);

    expect(response.statusCode, 404);
  });

  test('a 401 throws an ApiException without retrying', () async {
    var attempts = 0;
    final client = TmdbHttpClient.forTesting(
      MockClient((request) async {
        attempts++;
        return Response('{"status_code":7}', 401);
      }),
    );

    await expectLater(client.get(url), throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)));
    expect(attempts, 1);
  });

  test('a 401 for a bad session is an unauthorized exception that blames the session', () async {
    final client = TmdbHttpClient.forTesting(
      MockClient((request) async => Response('{"status_code":3,"status_message":"Authentication failed"}', 401)),
    );

    await expectLater(
      client.get(url),
      throwsA(
        isA<ApiUnauthorizedException>()
            .having((e) => e.tmdbStatusCode, 'tmdbStatusCode', 3)
            .having((e) => e.isSessionProblem, 'isSessionProblem', isTrue),
      ),
    );
  });

  test('a 401 for a bad API key is not blamed on the session', () async {
    final client = TmdbHttpClient.forTesting(MockClient((request) async => Response('{"status_code":7}', 401)));

    await expectLater(
      client.get(url),
      throwsA(isA<ApiUnauthorizedException>().having((e) => e.isSessionProblem, 'isSessionProblem', isFalse)),
    );
  });

  test('a 401 with no readable body still classifies as a session problem', () async {
    final client = TmdbHttpClient.forTesting(MockClient((request) async => Response('', 401)));

    await expectLater(client.get(url), throwsA(isA<ApiUnauthorizedException>().having((e) => e.tmdbStatusCode, 'tmdbStatusCode', isNull)));
  });

  test('a persistent 429 is retried, honouring retry-after, then surfaces as too-many-requests', () {
    var attempts = 0;
    final client = TmdbHttpClient.forTesting(
      MockClient((request) async {
        attempts++;
        return Response('', 429, headers: {'retry-after': '1'});
      }),
    );

    final error = runToFailureWithFakeTime(() => client.get(url));

    expect(error, isA<ApiToManyRequestsException>().having((e) => e.retryAfter, 'retryAfter', 1));
    // One initial attempt plus RetryClient's three retries.
    expect(attempts, 4);
  });

  test('a 429 that clears up on a later attempt succeeds', () async {
    var attempts = 0;
    final client = TmdbHttpClient.forTesting(
      MockClient((request) async {
        attempts++;
        if (attempts < 3) {
          return Response('', 429, headers: {'retry-after': '0'});
        }
        return Response('{"id":1399}', 200);
      }),
    );

    final response = await client.get(url);

    expect(response.statusCode, 200);
    expect(attempts, 3);
  });

  test('a persistent 5xx exhausts the retries and surfaces as service-down', () {
    var attempts = 0;
    final client = TmdbHttpClient.forTesting(
      MockClient((request) async {
        attempts++;
        return Response('', 503);
      }),
    );

    final error = runToFailureWithFakeTime(() => client.get(url));

    expect(error, isA<ApiDownException>());
    expect(attempts, 4);
  });

  test('a transient transport failure is retried until an attempt succeeds', () async {
    var attempts = 0;
    final client = TmdbHttpClient.forTesting(
      MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          throw ClientException('Connection reset by peer');
        }
        return Response('{}', 200);
      }),
    );

    final response = await client.get(url);

    expect(response.statusCode, 200);
    expect(attempts, 2);
  });
}
