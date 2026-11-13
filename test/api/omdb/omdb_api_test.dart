import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/error.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/omdb/item_details.api.dart';

/// The exact requests [OmdbDetailsApi] sends and how it classifies the answers. OMDb has one
/// endpoint; a title is addressed by its IMDb id, an episode by its show's id plus the season
/// and episode numbers.
void main() {
  final requests = <Request>[];
  late Response Function(Request request) omdb;
  late OmdbDetailsApi api;

  const episodeBody = '{"Title":"Pilot","imdbRating":"9.1","imdbVotes":"1,200","imdbID":"tt0105","Response":"True"}';

  setUp(() {
    requests.clear();
    omdb = (_) => Response(episodeBody, 200);
    api = OmdbDetailsApi.withClient(
      MockClient((request) async {
        requests.add(request);
        return omdb(request);
      }),
    );
  });

  test('get asks for the id with the shared key over https', () async {
    final item = await api.get('tt0042');

    final uri = requests.single.url;
    expect(uri.scheme, 'https');
    expect(uri.host, OmdbDetailsApi.omdbUrl);
    expect(uri.queryParameters, {'apikey': OmdbDetailsApi.omdbApiKey, 'i': 'tt0042'});
    expect(item!.imdbRating, '9.1');
    expect(item.imdbVotes, '1,200');
    expect(item.imdbId, 'tt0105');
  });

  test('fullDetails asks for the full plot', () async {
    await api.get('tt0042', true);

    expect(requests.single.url.queryParameters['plot'], 'full');
  });

  test('getEpisode addresses the episode through its show plus Season and Episode', () async {
    final item = await api.getEpisode('tt0100', 2, 5);

    expect(requests.single.url.queryParameters, {'apikey': OmdbDetailsApi.omdbApiKey, 'i': 'tt0100', 'Season': '2', 'Episode': '5'});
    expect(item!.imdbId, 'tt0105', reason: "the answer carries the episode's own id");
  });

  test('"Response": "False" is null, not an exception', () async {
    omdb = (_) => Response('{"Response":"False","Error":"Incorrect IMDb ID."}', 200);

    expect(await api.get('tt0000'), isNull);
    expect(await api.getEpisode('tt0100', 99, 99), isNull);
  });

  test('a non-200 status is an ApiException', () async {
    omdb = (_) => Response('Unauthorized', 401);

    await expectLater(api.get('tt0042'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)));
  });

  test('a transport error is an ApiClientError', () async {
    omdb = (_) => throw ClientException('offline');

    await expectLater(api.getEpisode('tt0100', 2, 5), throwsA(isA<ApiClientError>()));
  });
}
