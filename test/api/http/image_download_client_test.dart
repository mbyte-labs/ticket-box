import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/http/image_download_client.dart';

/// The image CDN client: no credential, an image Accept header, exactly one retry for a blip.
/// Runs in real time (a body read goes through the stall guard, which never completes under fake
/// time) and pays `RetryClient`'s sub-second back-off once per retrying test.
void main() {
  final url = Uri.parse('https://image.tmdb.org/t/p/w342/abc.jpg');

  tearDown(ImageDownloadClient.resetForTesting);

  test('asks for images and sends no Authorization header', () async {
    Request? seen;
    final client = ImageDownloadClient.forTesting(
      MockClient((request) async {
        seen = request;
        return Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/jpeg'});
      }),
    );

    final response = await client.get(url);

    expect(response.statusCode, 200);
    expect(seen!.headers['Accept'], 'image/*');
    expect(seen!.headers.keys.map((key) => key.toLowerCase()), isNot(contains('authorization')));
  });

  test('the singleton hands out the client installed for testing', () {
    final client = ImageDownloadClient.forTesting(MockClient((request) async => Response('', 200)));

    expect(ImageDownloadClient.instance, same(client));
  });

  test('retries a 503 once and returns the second answer', () async {
    var attempts = 0;
    final client = ImageDownloadClient.forTesting(
      MockClient((request) async {
        attempts++;
        return attempts == 1 ? Response('', 503) : Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/jpeg'});
      }),
    );

    final response = await client.get(url);

    expect(response.statusCode, 200);
    expect(attempts, 2);
  });

  test('a persistent 503 is returned after the one retry, not thrown', () async {
    var attempts = 0;
    final client = ImageDownloadClient.forTesting(
      MockClient((request) async {
        attempts++;
        return Response('', 503);
      }),
    );

    final response = await client.get(url);

    expect(response.statusCode, 503);
    expect(attempts, 2);
  });

  test('a 404 passes through untouched and is not retried', () async {
    var attempts = 0;
    final client = ImageDownloadClient.forTesting(
      MockClient((request) async {
        attempts++;
        return Response('', 404);
      }),
    );

    final response = await client.get(url);

    expect(response.statusCode, 404);
    expect(attempts, 1);
  });

  test('a transport failure is retried once and then surfaces', () async {
    var attempts = 0;
    final client = ImageDownloadClient.forTesting(
      MockClient((request) async {
        attempts++;
        throw ClientException('connection reset', request.url);
      }),
    );

    await expectLater(client.get(url), throwsA(isA<ClientException>()));
    expect(attempts, 2);
  });
}
