import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/people/model/person_details.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/person/person_credit.dart';
import 'package:ticketbox/service/person/person_service.dart';

/// The person page's data: the one TMDB request ([PersonService.get]), the in-memory fold of the
/// credits into cards ([PersonService.filmography]) and the library marks stamped on them from
/// the user's own tables ([PersonService.withLibraryMarks]). Nothing here writes a row.
void main() {
  const posterSize = 'w185';

  TmdbPersonCredit movie(int id, {String? releaseDate, String? posterPath, String? title, String? character, double? voteAverage}) {
    return TmdbPersonCredit(
      id: id,
      mediaType: 'movie',
      title: title ?? 'Movie $id',
      releaseDate: releaseDate,
      posterPath: posterPath,
      character: character,
      voteAverage: voteAverage,
    );
  }

  TmdbPersonCredit show(int id, {String? firstAirDate, String? posterPath, String? name, String? character, int episodeCount = 0}) {
    return TmdbPersonCredit(
      id: id,
      mediaType: 'tv',
      name: name ?? 'Show $id',
      firstAirDate: firstAirDate,
      posterPath: posterPath,
      character: character,
      episodeCount: episodeCount,
    );
  }

  List<(PersonCreditKind, int)> keysOf(List<PersonCredit> credits) => credits.map((credit) => (credit.kind, credit.tmdbId)).toList();

  group('get', () {
    late List<Request> requests;
    late Future<Response> Function(Request request) answer;

    setUp(() {
      requests = [];
      answer = (request) async => Response('{"status_code":34,"status_message":"not found"}', 404);
      TmdbHttpClient.forTesting(
        MockClient((request) {
          requests.add(request);
          return answer(request);
        }),
      );
    });

    tearDown(TmdbHttpClient.resetForTesting);

    test('asks for the person with the credits and external ids appended, in one request', () async {
      // UTF-8 bytes, as TMDB sends them: `Response(String)` would encode the Cyrillic alias as Latin-1 and throw.
      answer = (request) async => Response.bytes(
        utf8.encode(
          json.encode({
            'id': 287,
            'name': 'Brad Pitt',
            'profile_path': '/pitt.jpg',
            'known_for_department': 'Acting',
            'also_known_as': [' Брэд Питт ', '', '  '],
            'external_ids': {
              'imdb_id': 'nm0000093',
              'twitter_id': 'pitt',
              'instagram_id': 'bradpittofflcial',
              'facebook_id': '',
              'wikidata_id': 'Q35332',
            },
            'combined_credits': {
              'cast': [
                {'id': 550, 'media_type': 'movie', 'title': 'Fight Club', 'release_date': '1999-10-15', 'poster_path': '/fc.jpg'},
                {'id': 1396, 'media_type': 'tv', 'name': 'Friends', 'first_air_date': '1994-09-22'},
                {'id': 550, 'media_type': 'movie', 'title': 'Fight Club', 'release_date': '1999-10-15'},
              ],
              'crew': [
                {'id': 68718, 'media_type': 'movie', 'title': 'Django Unchained', 'job': 'Producer'},
              ],
            },
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

      final person = await PersonService().get(287, PosterQualityOption.medium);

      expect(person.name, 'Brad Pitt');
      expect(person.photoUrl, endsWith('/pitt.jpg'));
      expect(person.knownForDepartment, 'Acting');
      expect(person.alsoKnownAs, ['Брэд Питт']);
      expect(person.imdbId, 'nm0000093');
      expect(person.twitter, 'https://x.com/pitt');
      expect(person.instagram, 'https://www.instagram.com/bradpittofflcial');
      expect(person.facebook, isNull);
      expect(person.wikipedia, 'https://www.wikidata.org/wiki/Q35332');
      expect(keysOf(person.filmography), [(PersonCreditKind.movie, 550), (PersonCreditKind.show, 1396)]);
      expect(person.filmography.first.posterUrl, 'https://image.tmdb.org/t/p/w342/fc.jpg');
      expect(person.filmography.first.inLibrary, isFalse);

      expect(requests.single.url.path, '/3/person/287');
      expect(requests.single.url.queryParameters['append_to_response'], 'combined_credits,external_ids');
    });

    test('reports a person TMDB no longer has', () async {
      expect(() => PersonService().get(287, PosterQualityOption.medium), throwsA(isA<PersonNotFoundException>()));
    });

    test('lets any other failure through to the caller', () async {
      answer = (request) async => Response('{"status_code":7,"status_message":"Invalid API key"}', 403);

      expect(() => PersonService().get(287, PosterQualityOption.medium), throwsA(isA<ApiException>()));
    });
  });

  group('filmography', () {
    test('keeps movies and shows with an id and a title only', () {
      final cast = [
        movie(1, releaseDate: '2001-01-01'),
        const TmdbPersonCredit(id: 4, mediaType: 'person'),
        movie(0, releaseDate: '2002-01-01'),
        movie(5, title: '  '),
        show(2, firstAirDate: '2010-05-05'),
      ];

      expect(keysOf(PersonService.filmography(cast, posterSize: posterSize)), [(PersonCreditKind.show, 2), (PersonCreditKind.movie, 1)]);
    });

    test('folds the parts of one title into one card, characters joined in first-seen order without repeats', () {
      final cast = [
        show(1, firstAirDate: '2008-01-20', character: 'Walter White', episodeCount: 62, posterPath: '/bb.jpg'),
        show(1, firstAirDate: '2008-01-20', character: ' Heisenberg ', episodeCount: 10),
        show(1, firstAirDate: '2008-01-20', character: 'Walter White', episodeCount: 5),
        show(1, firstAirDate: '2008-01-20', character: '', episodeCount: 70),
      ];

      final result = PersonService.filmography(cast, posterSize: posterSize);

      expect(result, hasLength(1));
      expect(result.single.character, 'Walter White / Heisenberg');
      // The largest part, not the sum: parts can share episodes.
      expect(result.single.episodes, 70);
      expect(result.single.posterUrl, 'https://image.tmdb.org/t/p/w185/bb.jpg');
    });

    test('a title with no named part has no character, and a movie has no episode count', () {
      final result = PersonService.filmography([movie(1, character: ' '), show(2, episodeCount: 0)], posterSize: posterSize);

      expect(result.map((credit) => credit.character), [null, null]);
      expect(result.map((credit) => credit.episodes), [null, null]);
    });

    test('a movie and a show sharing a TMDB id are both kept', () {
      final result = PersonService.filmography([
        movie(7, releaseDate: '2000-01-01'),
        show(7, firstAirDate: '2001-01-01'),
      ], posterSize: posterSize);

      expect(result, hasLength(2));
    });

    test('orders undated titles first, then newest first, then title, kind and id', () {
      final cast = [
        movie(1, releaseDate: '2001-01-01', title: 'Beta'),
        show(2, firstAirDate: '2010-05-05'),
        movie(3, title: 'Zulu'), // undated
        movie(5, releaseDate: '2020-12-31'),
        show(6, firstAirDate: '', name: 'alpha'), // blank date is undated too
        show(7, firstAirDate: '2001-01-01', name: 'beta'),
        movie(8, releaseDate: '2001-01-01', title: 'Beta'),
      ];

      final result = PersonService.filmography(cast, posterSize: posterSize);

      expect(keysOf(result), [
        (PersonCreditKind.show, 6),
        (PersonCreditKind.movie, 3),
        (PersonCreditKind.movie, 5),
        (PersonCreditKind.show, 2),
        (PersonCreditKind.movie, 1),
        (PersonCreditKind.movie, 8),
        (PersonCreditKind.show, 7),
      ]);
    });

    test('reads the year off the date and turns a score of zero into no score', () {
      final result = PersonService.filmography([
        movie(1, releaseDate: '1999-10-15', voteAverage: 8.4),
        movie(2, releaseDate: '2024', voteAverage: 0),
        movie(3),
      ], posterSize: posterSize);

      expect(result.map((credit) => credit.year), [null, 2024, 1999]);
      expect(result.map((credit) => credit.rating), [null, null, 8.4]);
    });

    test('has no cap', () {
      final cast = List.generate(40, (index) => movie(index + 1, releaseDate: '2000-01-${(index % 28 + 1).toString().padLeft(2, '0')}'));

      expect(PersonService.filmography(cast, posterSize: posterSize), hasLength(40));
    });
  });

  group('withLibraryMarks', () {
    late DatabaseConnectionManager db;
    var nextHistoryId = 1;

    HistoryEntity play(ItemType type, int tmdbId, {int season = 0, int episode = 0}) {
      return HistoryEntity.build(
        historyId: nextHistoryId++,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        type: type,
        action: HistoryAction.watch,
        watchedAt: DateTime.utc(2026, 7, 1),
      );
    }

    /// The show's state as the recompute would have left it: `watched` once every aired episode
    /// is played, `watching` before that.
    Future<void> state(int showId, ShowWatchStatus status) => ShowStateRepo().upsert(showId, status, DateTime.utc(2026, 7, 1));

    PersonCredit card(PersonCreditKind kind, int tmdbId) {
      return PersonCredit(
        kind: kind,
        tmdbId: tmdbId,
        title: 'Title $tmdbId',
        date: null,
        year: null,
        character: null,
        episodes: null,
        rating: null,
        posterUrl: null,
      );
    }

    setUp(() async {
      db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
      GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    });

    tearDown(() async {
      await GetIt.I.reset();
      await db.close();
    });

    test('marks movies by their plays and shows by their plays and state, in a few reads', () async {
      await HistoryRepo().insertAll([
        play(ItemType.movie, 550),
        play(ItemType.episode, 1, season: 1, episode: 1),
        play(ItemType.episode, 2, season: 1, episode: 1),
        play(ItemType.episode, 3, season: 0, episode: 1), // a special only
      ]);
      await state(1, ShowWatchStatus.watched);
      await state(2, ShowWatchStatus.watching);
      await state(3, ShowWatchStatus.watching);

      final marked = await PersonService().withLibraryMarks([
        card(PersonCreditKind.movie, 550),
        card(PersonCreditKind.show, 1),
        card(PersonCreditKind.show, 2),
        card(PersonCreditKind.show, 3),
        card(PersonCreditKind.movie, 1), // shares the finished show's id: untouched
      ]);

      final movie = marked[0];
      expect((movie.inLibrary, movie.watched, movie.inHistory), (true, true, true));

      final finished = marked[1];
      expect((finished.inLibrary, finished.watched, finished.inHistory), (true, true, true));

      final halfWatched = marked[2];
      expect((halfWatched.inLibrary, halfWatched.watched, halfWatched.inHistory), (true, false, true));

      final specialsOnly = marked[3];
      expect((specialsOnly.inLibrary, specialsOnly.watched, specialsOnly.inHistory), (true, false, true));

      final untouched = marked[4];
      expect((untouched.inLibrary, untouched.watched, untouched.inHistory), (false, false, false));
    });

    test('a watchlist entry or a rating puts a title in the library without a play, title-level rows only', () async {
      await WatchlistRepo().insertAll([
        WatchlistEntity.build(type: ItemType.show, tmdbId: 1, listedAt: DateTime.utc(2026, 7, 1)),
        WatchlistEntity.build(type: ItemType.season, tmdbId: 2, season: 1, listedAt: DateTime.utc(2026, 7, 1)),
      ]);
      await UserRatingRepo().insertAll([
        UserRatingEntity.build(type: ItemType.movie, tmdbId: 3, rating: 8, ratedAt: DateTime.utc(2026, 7, 1)),
        UserRatingEntity.build(type: ItemType.episode, tmdbId: 4, season: 1, episode: 1, rating: 9, ratedAt: DateTime.utc(2026, 7, 1)),
      ]);

      final marked = await PersonService().withLibraryMarks([
        card(PersonCreditKind.show, 1),
        card(PersonCreditKind.show, 2),
        card(PersonCreditKind.movie, 3),
        card(PersonCreditKind.show, 4),
      ]);

      expect(marked[0].inLibrary, isTrue);
      expect(marked[0].watchlisted, isTrue);
      expect(marked[0].watched, isFalse);
      expect(marked[1].inLibrary, isFalse);
      expect(marked[2].inLibrary, isTrue);
      expect(marked[2].userRating, 8);
      expect(marked[3].inLibrary, isFalse);
    });

    test('an empty filmography needs no reads', () async {
      expect(await PersonService().withLibraryMarks(const []), isEmpty);
    });
  });
}
