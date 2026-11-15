import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_account_api.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_account_models.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_rating_api.dart';
import 'package:ticketbox/api/tmdb/v3/authentication/tmdb_auth_models.dart';
import 'package:ticketbox/api/tmdb/v3/authentication/tmdb_authentication_api.dart';
import 'package:ticketbox/common/model/item_type.dart';

/// The shape of the account calls: the session goes in the query, writes are JSON bodies, and the
/// rows TMDB returns map onto the app's keys.
void main() {
  tearDown(TmdbHttpClient.resetForTesting);

  group('authentication', () {
    test('the approval URL carries the token in the path and the redirect in the query', () {
      final url = TmdbAuthenticationApi.approvalUrl('tok123', Uri.parse('ticketbox://tmdb-auth'));

      expect(url.host, 'www.themoviedb.org');
      expect(url.path, '/authenticate/tok123');
      expect(url.queryParameters['redirect_to'], 'ticketbox://tmdb-auth');
    });

    test('a session is created by POSTing the request token and read from session_id', () async {
      Request? seen;
      TmdbHttpClient.forTesting(
        MockClient((request) async {
          seen = request;
          return Response('{"success":true,"session_id":"sess-1"}', 200);
        }),
      );

      final session = await TmdbAuthenticationApi().createSession('tok123');

      expect(session.sessionId, 'sess-1');
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/3/authentication/session/new');
      expect(json.decode(seen!.body), {'request_token': 'tok123'});
      expect(seen!.headers['Content-Type'], startsWith('application/json'));
    });

    test('an unapproved token (401) surfaces as an unauthorized exception', () async {
      TmdbHttpClient.forTesting(MockClient((request) async => Response('{"status_code":17}', 401)));

      await expectLater(TmdbAuthenticationApi().createSession('tok123'), throwsA(isA<ApiUnauthorizedException>()));
    });

    test('a session is revoked with a DELETE carrying the session id in the body', () async {
      Request? seen;
      TmdbHttpClient.forTesting(
        MockClient((request) async {
          seen = request;
          return Response('{"success":true}', 200);
        }),
      );

      await TmdbAuthenticationApi().deleteSession('sess-1');

      expect(seen!.method, 'DELETE');
      expect(seen!.url.path, '/3/authentication/session');
      expect(json.decode(seen!.body), {'session_id': 'sess-1'});
    });

    test('the request token model reads TMDB\'s snake_case fields', () {
      final token = TmdbRequestToken.fromJson({'success': true, 'expires_at': '2026-10-09 12:00:00 UTC', 'request_token': 'tok'});

      expect(token.requestToken, 'tok');
      expect(token.expiresAt, '2026-10-09 12:00:00 UTC');
    });
  });

  group('account lists', () {
    test('the account call sends the session id in the query and reads id, username and name', () async {
      Request? seen;
      TmdbHttpClient.forTesting(
        MockClient((request) async {
          seen = request;
          return Response('{"id":42,"username":"alex","name":"Alex D"}', 200);
        }),
      );

      final account = await TmdbAccountApi().get('sess-1');

      expect(seen!.url.path, '/3/account');
      expect(seen!.url.queryParameters['session_id'], 'sess-1');
      expect(account.id, 42);
      expect(account.username, 'alex');
      expect(account.name, 'Alex D');
    });

    test('a rated episode row is keyed by show id and numbers, with a decimal rating', () async {
      TmdbHttpClient.forTesting(
        MockClient(
          (request) async => Response(
            '{"page":1,"total_pages":1,"total_results":1,"results":[{"id":62085,"show_id":1396,"season_number":1,"episode_number":2,"rating":7.5}]}',
            200,
          ),
        ),
      );

      final page = await TmdbAccountApi().ratedEpisodes(42, 'sess-1');

      expect(page.results.single, const TmdbRatedEpisode(showId: 1396, seasonNumber: 1, episodeNumber: 2, rating: 7.5));
    });

    test('a whole-number rating still decodes as a double', () {
      expect(TmdbRatedMovie.fromJson({'id': 1, 'rating': 8}).rating, 8.0);
      expect(TmdbRatedShow.fromJson({'id': 1, 'rating': 9}).rating, 9.0);
    });

    test('lists are paged in created_at order and the requested page is passed through', () async {
      Request? seen;
      TmdbHttpClient.forTesting(
        MockClient((request) async {
          seen = request;
          return Response('{"page":3,"total_pages":3,"total_results":41,"results":[]}', 200);
        }),
      );

      final page = await TmdbAccountApi().watchlistMovies(42, 'sess-1', 3);

      expect(seen!.url.path, '/3/account/42/watchlist/movies');
      expect(seen!.url.queryParameters, containsPair('page', '3'));
      expect(seen!.url.queryParameters, containsPair('sort_by', 'created_at.asc'));
      expect(seen!.url.queryParameters, containsPair('session_id', 'sess-1'));
      expect(page.page, 3);
      expect(page.hasMore, isFalse);
    });
  });

  group('writes', () {
    test('the watchlist write posts media_type, media_id and the flag', () async {
      Request? seen;
      TmdbHttpClient.forTesting(
        MockClient((request) async {
          seen = request;
          return Response('{"success":true,"status_code":13,"status_message":"The item/record was deleted successfully."}', 200);
        }),
      );

      final status = await TmdbAccountApi().setWatchlist(
        accountId: 42,
        sessionId: 'sess-1',
        mediaType: TmdbMediaType.tv,
        mediaId: 1396,
        listed: false,
      );

      expect(seen!.url.path, '/3/account/42/watchlist');
      expect(json.decode(seen!.body), {'media_type': 'tv', 'media_id': 1396, 'watchlist': false});
      expect(status.statusCode, 13);
    });

    test('the favorite write mirrors the watchlist one', () async {
      Request? seen;
      TmdbHttpClient.forTesting(
        MockClient((request) async {
          seen = request;
          return Response('{"success":true,"status_code":1}', 201);
        }),
      );

      final status = await TmdbAccountApi().setFavorite(
        accountId: 42,
        sessionId: 'sess-1',
        mediaType: TmdbMediaType.movie,
        mediaId: 550,
        favorite: true,
      );

      expect(seen!.url.path, '/3/account/42/favorite');
      expect(json.decode(seen!.body), {'media_type': 'movie', 'media_id': 550, 'favorite': true});
      expect(status.statusCode, 1, reason: 'a 201 decodes like a 200');
    });

    test('a rating is posted as a decimal value and removed with a bodiless DELETE', () async {
      final seen = <Request>[];
      TmdbHttpClient.forTesting(
        MockClient((request) async {
          seen.add(request);
          return Response('{"success":true,"status_code":1}', 201);
        }),
      );

      await TmdbRatingApi().rateEpisode(1396, 1, 2, 8, 'sess-1');
      await TmdbRatingApi().deleteMovieRating(550, 'sess-1');

      expect(seen[0].method, 'POST');
      expect(seen[0].url.path, '/3/tv/1396/season/1/episode/2/rating');
      expect(seen[0].url.queryParameters['session_id'], 'sess-1');
      expect(json.decode(seen[0].body), {'value': 8.0});
      expect(seen[1].method, 'DELETE');
      expect(seen[1].url.path, '/3/movie/550/rating');
      expect(seen[1].body, isEmpty);
    });

    test('a 404 on a write is a not-found exception, any other failure a plain ApiException', () async {
      var status = 404;
      TmdbHttpClient.forTesting(MockClient((request) async => Response('{"status_code":34}', status)));

      await expectLater(TmdbRatingApi().rateMovie(1, 5, 'sess-1'), throwsA(isA<ApiNotFoundException>()));
      status = 400;
      await expectLater(
        TmdbRatingApi().rateMovie(1, 5, 'sess-1'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400).having((e) => e is ApiNotFoundException, 'not found', isFalse),
        ),
      );
    });

    test('the media type of a show is tv, of a movie movie, and of a season or episode nothing', () {
      expect(TmdbMediaType.fromItemType(ItemType.show), TmdbMediaType.tv);
      expect(TmdbMediaType.fromItemType(ItemType.movie), TmdbMediaType.movie);
      expect(TmdbMediaType.fromItemType(ItemType.season), isNull);
      expect(TmdbMediaType.fromItemType(ItemType.episode), isNull);
    });
  });
}
