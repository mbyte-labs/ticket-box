import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/movie/movie_details_api.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details_api.dart';

/// The exact requests the two snapshot wrappers send: every section a details page renders is
/// appended to the one call, and the season slots respect TMDB's 20-key limit.
void main() {
  final requests = <Request>[];
  var status = 200;

  setUp(() {
    requests.clear();
    status = 200;
    TmdbHttpClient.forTesting(
      MockClient((request) async {
        requests.add(request);
        return Response(status == 200 ? '{"id": 1, "name": "x", "title": "x"}' : '{"success":false}', status);
      }),
    );
  });

  tearDown(TmdbHttpClient.resetForTesting);

  test('a movie appends eight sections and asks for language-less images too', () async {
    final raw = await TmdbMovieDetailsApi().getRaw(550);

    expect(raw, isNotNull);
    final uri = requests.single.url;
    expect(uri.path, '/3/movie/550');
    expect(
      uri.queryParameters['append_to_response'],
      'credits,external_ids,videos,images,watch/providers,recommendations,similar,release_dates',
    );
    expect(uri.queryParameters['include_image_language'], 'en,null');
    expect(uri.queryParameters['language'], 'en-US');
  });

  test('a 404 is null, not an exception', () async {
    status = 404;

    expect(await TmdbMovieDetailsApi().getRaw(1), isNull);
    expect(await TmdbShowDetailsApi().getRaw(1), isNull);
    expect(await TmdbShowDetailsApi().getSeasonsRaw(1, [1]), isNull);
  });

  test('a show root appends eight sections plus the requested seasons, sorted and deduplicated', () async {
    await TmdbShowDetailsApi().getRaw(1399, appendSeasons: [2, 1, 2]);

    final uri = requests.single.url;
    expect(uri.path, '/3/tv/1399');
    expect(
      uri.queryParameters['append_to_response'],
      'aggregate_credits,external_ids,content_ratings,videos,images,watch/providers,recommendations,similar,season/1,season/2',
    );
    expect(uri.queryParameters['include_image_language'], 'en,null');
  });

  test('twelve seasons fit a root request, thirteen do not', () async {
    await TmdbShowDetailsApi().getRaw(1399, appendSeasons: List.generate(12, (i) => i + 1));
    expect(requests.single.url.queryParameters['append_to_response']!.split(',').length, 20);

    expect(() => TmdbShowDetailsApi().getRaw(1399, appendSeasons: List.generate(13, (i) => i + 1)), throwsArgumentError);
    expect(TmdbShowDetailsApi.maxAppendedSeasons, 12);
  });

  test('a seasons-only request appends nothing else and takes up to twenty seasons', () async {
    await TmdbShowDetailsApi().getSeasonsRaw(1399, List.generate(20, (i) => i + 1));

    final uri = requests.single.url;
    expect(uri.queryParameters['append_to_response'], List.generate(20, (i) => 'season/${i + 1}').join(','));
    expect(uri.queryParameters.containsKey('include_image_language'), isFalse);

    expect(() => TmdbShowDetailsApi().getSeasonsRaw(1399, List.generate(21, (i) => i + 1)), throwsArgumentError);
    expect(() => TmdbShowDetailsApi().getSeasonsRaw(1399, const []), throwsArgumentError);
  });

  test('the typed get parses the same body', () async {
    final show = await TmdbShowDetailsApi().get(1399);
    final movie = await TmdbMovieDetailsApi().get(550);

    expect(show!.id, 1);
    expect(movie!.id, 1);
  });
}
