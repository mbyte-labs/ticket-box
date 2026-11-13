import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/omdb/item_details.api.dart';
import 'package:ticketbox/database/sql_store/cache/cache.dart';
import 'package:ticketbox/database/sql_store/cache/cache_repo.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/service/external_rating/external_rating_service.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/external_rating/imdb_rating.dart';

/// [ExternalRatingService] against a fake OMDb: what gets cached, what answers offline, and
/// what a failed fetch leaves behind. The distinction that matters most is null versus
/// all-null: null means "never fetched" (the details page keeps whatever it was showing), a
/// cached [ImdbRating] whose fields are all null is a real "IMDb has nothing" answer and must
/// round-trip as exactly that.
void main() {
  late DatabaseConnectionManager db;
  late InternalCacheRepo cacheRepo;
  late ExternalRatingService service;

  /// Every request the fake OMDb saw, and how it answers the next one.
  final requests = <Request>[];
  late Future<Response> Function(Request request) omdb;

  const tmdbId = 4242;
  const imdbId = 'tt0042';
  const showImdbId = 'tt0100';
  const episodeImdbId = 'tt0105';
  const movieKey = 'external_ratings_movie_$tmdbId';
  const showKey = 'external_ratings_show_$tmdbId';
  const episodeKey = 'external_ratings_episode_${tmdbId}_2_5';

  const rating = ImdbRating(rating: 8.2, votes: 135825, imdbId: imdbId);

  /// Well outside the 14-day TTL whatever today is; whole seconds because drift stores seconds.
  final expiredAt = DateTime.utc(2020, 6, 15, 12);

  Response answer({String? imdbRating = '8.2', String? imdbVotes = '135,825', String? id = imdbId}) {
    return Response(json.encode({'Title': 'x', 'imdbRating': imdbRating, 'imdbVotes': imdbVotes, 'imdbID': id, 'Response': 'True'}), 200);
  }

  Response nothing() => Response('{"Response":"False","Error":"Incorrect IMDb ID."}', 200);

  Future<void> seedExpired(String key, Map<String, dynamic> value) async {
    await cacheRepo.insert(CacheEntity.build(key: key, customData: json.encode(value), synchronizedAt: expiredAt));
  }

  EpisodeEntity episodeRow({String? withImdbId}) {
    return EpisodeEntity.build(
      showTmdbId: tmdbId,
      season: 2,
      episode: 5,
      tmdbId: 25,
      imdbId: withImdbId,
      title: 'x',
      overview: null,
      voteAverage: 0,
      voteCount: 0,
      runtime: null,
      airDate: null,
      episodeType: null,
      stillPath: null,
    );
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    cacheRepo = InternalCacheRepo();
    requests.clear();
    omdb = (_) async => answer();
    service = ExternalRatingService(
      api: OmdbDetailsApi.withClient(
        MockClient((request) {
          requests.add(request);
          return omdb(request);
        }),
      ),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('offline (updateCache false) never touches the network', () {
    test('nothing cached answers null, not an empty object', () async {
      expect(await service.getForMovie(tmdbId, imdbId, false), isNull);
      expect(await service.getForShow(tmdbId, imdbId, false), isNull);
      expect(await service.getForEpisode(tmdbId, 2, 5, showImdbId: showImdbId, updateCache: false), isNull);
      expect(requests, isEmpty);
    });

    test('a cached rating round-trips numerically', () async {
      await cacheRepo.setJson(movieKey, rating.toJson());

      expect(await service.getForMovie(tmdbId, imdbId, false), rating);
      expect(requests, isEmpty);
    });

    test('a cached all-null answer is a real answer, not "never fetched"', () async {
      await cacheRepo.setJson(movieKey, ImdbRating.empty.toJson());

      expect(await service.getForMovie(tmdbId, imdbId, false), ImdbRating.empty);
      expect(requests, isEmpty);
    });

    test('an expired row still answers offline', () async {
      await seedExpired(movieKey, rating.toJson());

      expect(await service.getForMovie(tmdbId, imdbId, false), rating);
      expect(requests, isEmpty);
    });

    test('movie and show caches do not answer for each other despite equal tmdb ids', () async {
      // TMDB movie and show ids are separate namespaces, so the same number must resolve to
      // separate cache rows.
      await cacheRepo.setJson(movieKey, rating.toJson());

      expect(await service.getForShow(tmdbId, imdbId, false), isNull);
    });

    test('the episode key carries the season and episode numbers', () async {
      await cacheRepo.setJson(episodeKey, rating.toJson());

      expect(await service.getForEpisode(tmdbId, 2, 5, showImdbId: showImdbId, updateCache: false), rating);
      expect(await service.getForEpisode(tmdbId, 2, 6, showImdbId: showImdbId, updateCache: false), isNull);
      expect(requests, isEmpty);
    });

    test('undecodable cache data degrades to null instead of throwing', () async {
      await cacheRepo.setJson(movieKey, {'rating': 'not-a-number'});

      expect(await service.getForMovie(tmdbId, imdbId, false), isNull);
    });
  });

  group('lookups', () {
    test('a movie is looked up by its IMDb id, cached, and served from the cache afterwards', () async {
      expect(await service.getForMovie(tmdbId, imdbId), rating);

      final query = requests.single.url.queryParameters;
      expect(query['i'], imdbId);
      expect(query.containsKey('Season'), isFalse);
      expect(json.decode((await cacheRepo.get(movieKey))!.customData), {'rating': 8.2, 'votes': 135825, 'imdbId': imdbId});

      // A fresh row answers both the updating and the offline pass without a second request.
      expect(await service.getForMovie(tmdbId, imdbId), rating);
      expect(await service.getForMovie(tmdbId, imdbId, false), rating);
      expect(requests, hasLength(1));
    });

    test('a show is cached under its own key', () async {
      expect(await service.getForShow(tmdbId, imdbId), rating);

      expect(await cacheRepo.get(showKey), isNotNull);
      expect(await cacheRepo.get(movieKey), isNull);
    });

    test('a null IMDb id is a cached "IMDb has nothing" answer, not a request', () async {
      expect(await service.getForMovie(tmdbId, null), ImdbRating.empty);
      expect(await service.getForShow(tmdbId, ''), ImdbRating.empty);

      expect(requests, isEmpty);
      // Cached as a real answer: offline it is still the empty rating, not null.
      expect(await service.getForMovie(tmdbId, null, false), ImdbRating.empty);
      expect(await service.getForShow(tmdbId, '', false), ImdbRating.empty);
    });

    test('an id OMDb does not know is a cached nothing answer', () async {
      omdb = (_) async => nothing();

      expect(await service.getForMovie(tmdbId, imdbId), ImdbRating.empty);
      expect(await service.getForMovie(tmdbId, imdbId, false), ImdbRating.empty);
      expect(requests, hasLength(1));
    });

    test('"N/A" numbers decode to null while the id is kept', () async {
      omdb = (_) async => answer(imdbRating: 'N/A', imdbVotes: 'N/A');

      expect(await service.getForMovie(tmdbId, imdbId), const ImdbRating(rating: null, votes: null, imdbId: imdbId));
    });

    test('an expired row is refreshed and rewritten', () async {
      await seedExpired(movieKey, const ImdbRating(rating: 7.0, votes: 10, imdbId: imdbId).toJson());

      expect(await service.getForMovie(tmdbId, imdbId), rating);

      expect(requests, hasLength(1));
      expect((await cacheRepo.get(movieKey))!.synchronizedAt.isAfter(expiredAt), isTrue);
    });

    test('an undecodable row is replaced on an updating pass', () async {
      await cacheRepo.setJson(movieKey, {'rating': 'not-a-number'});

      expect(await service.getForMovie(tmdbId, imdbId), rating);
      expect(requests, hasLength(1));
    });
  });

  group('stale fallback', () {
    test('a transport error keeps the expired cached value and leaves the row alone', () async {
      await seedExpired(movieKey, rating.toJson());
      omdb = (_) async => throw ClientException('offline');

      expect(await service.getForMovie(tmdbId, imdbId), rating);

      expect(requests, hasLength(1), reason: 'it did try');
      expect((await cacheRepo.get(movieKey))!.synchronizedAt.isAtSameMomentAs(expiredAt), isTrue, reason: 'the next pass must retry');
    });

    test('a non-200 answer is a failure too', () async {
      await seedExpired(showKey, rating.toJson());
      omdb = (_) async => Response('', 503);

      expect(await service.getForShow(tmdbId, imdbId), rating);
      expect((await cacheRepo.get(showKey))!.synchronizedAt.isAtSameMomentAs(expiredAt), isTrue);
    });

    test('with nothing cached a failed fetch answers null and caches nothing', () async {
      omdb = (_) async => throw ClientException('offline');

      expect(await service.getForMovie(tmdbId, imdbId), isNull);
      expect(await cacheRepo.get(movieKey), isNull);
    });
  });

  group('episodes', () {
    test("looked up through the show, and the answer's id lands in episodes.imdb_id", () async {
      await EpisodeRepo().insert(episodeRow());
      omdb = (_) async => answer(imdbRating: '9.1', imdbVotes: '1,200', id: episodeImdbId);

      final result = await service.getForEpisode(tmdbId, 2, 5, showImdbId: showImdbId);

      expect(result, const ImdbRating(rating: 9.1, votes: 1200, imdbId: episodeImdbId));
      final query = requests.single.url.queryParameters;
      expect(query['i'], showImdbId);
      expect(query['Season'], '2');
      expect(query['Episode'], '5');
      expect((await EpisodeRepo().get(tmdbId, 2, 5))!.imdbId, episodeImdbId);
      expect((json.decode((await cacheRepo.get(episodeKey))!.customData) as Map<String, dynamic>)['imdbId'], episodeImdbId);
    });

    test('a known episode id short-circuits to a plain lookup', () async {
      await EpisodeRepo().insert(episodeRow(withImdbId: episodeImdbId));
      omdb = (_) async => answer(id: episodeImdbId);

      await service.getForEpisode(tmdbId, 2, 5, showImdbId: showImdbId, episodeImdbId: episodeImdbId);

      final query = requests.single.url.queryParameters;
      expect(query['i'], episodeImdbId);
      expect(query.containsKey('Season'), isFalse);
      expect(query.containsKey('Episode'), isFalse);
    });

    test('the id learned on the first visit drives the plain lookup on the next refresh', () async {
      await EpisodeRepo().insert(episodeRow());
      omdb = (_) async => answer(id: episodeImdbId);
      await service.getForEpisode(tmdbId, 2, 5, showImdbId: showImdbId);
      final learned = (await EpisodeRepo().get(tmdbId, 2, 5))!.imdbId;
      // Age the row so the next updating pass asks OMDb again, the way a 14-day-old page would.
      await cacheRepo.delete(episodeKey);
      await seedExpired(episodeKey, ImdbRating.empty.toJson());

      await service.getForEpisode(tmdbId, 2, 5, showImdbId: showImdbId, episodeImdbId: learned);

      expect(requests, hasLength(2));
      expect(requests.last.url.queryParameters['i'], episodeImdbId);
      expect(requests.last.url.queryParameters.containsKey('Season'), isFalse);
    });

    test('an episode without an id on either side is a cached nothing answer', () async {
      expect(await service.getForEpisode(tmdbId, 2, 5, showImdbId: null), ImdbRating.empty);

      expect(requests, isEmpty);
      expect(await service.getForEpisode(tmdbId, 2, 5, showImdbId: null, updateCache: false), ImdbRating.empty);
    });

    test('an episode OMDb does not know writes no id', () async {
      await EpisodeRepo().insert(episodeRow());
      omdb = (_) async => nothing();

      expect(await service.getForEpisode(tmdbId, 2, 5, showImdbId: showImdbId), ImdbRating.empty);
      expect((await EpisodeRepo().get(tmdbId, 2, 5))!.imdbId, isNull);
    });

    test('a missing episode row does not fail the lookup', () async {
      omdb = (_) async => answer(id: episodeImdbId);

      expect(
        await service.getForEpisode(tmdbId, 2, 5, showImdbId: showImdbId),
        const ImdbRating(rating: 8.2, votes: 135825, imdbId: episodeImdbId),
      );
    });

    test('a failed OMDb call keeps the cached episode rating', () async {
      await seedExpired(episodeKey, rating.toJson());
      omdb = (_) async => throw ClientException('offline');

      expect(await service.getForEpisode(tmdbId, 2, 5, showImdbId: showImdbId), rating);
    });
  });

  group('rows written by the combined TMDB + IMDb layout', () {
    const combined = ExternalRatings(tmdbScore: 8.4, tmdbVotes: 3780, imdbRating: 8.2, imdbVotes: 135825);

    test('decode to their IMDb half, with no id', () async {
      await cacheRepo.setJson(movieKey, combined.toJson());

      expect(await service.getForMovie(tmdbId, imdbId, false), const ImdbRating(rating: 8.2, votes: 135825, imdbId: null));
    });

    test('an all-null row is a cached nothing answer', () async {
      await cacheRepo.setJson(
        movieKey,
        const ExternalRatings(tmdbScore: null, tmdbVotes: null, imdbRating: null, imdbVotes: null).toJson(),
      );

      expect(await service.getForMovie(tmdbId, imdbId, false), ImdbRating.empty);
    });

    test('a fresh row answers without the network on an updating pass', () async {
      await cacheRepo.setJson(movieKey, combined.toJson());

      expect(await service.getForMovie(tmdbId, imdbId), const ImdbRating(rating: 8.2, votes: 135825, imdbId: null));
      expect(requests, isEmpty);
    });

    test('an expired row is rewritten in the new layout', () async {
      await seedExpired(movieKey, combined.toJson());

      expect(await service.getForMovie(tmdbId, imdbId), rating);
      expect(json.decode((await cacheRepo.get(movieKey))!.customData), {'rating': 8.2, 'votes': 135825, 'imdbId': imdbId});
    });

    test('undecodable old-layout data degrades to null', () async {
      await cacheRepo.setJson(movieKey, {'tmdbScore': 'not-a-number'});

      expect(await service.getForMovie(tmdbId, imdbId, false), isNull);
    });
  });

  group('ExternalRatings.combine', () {
    test("joins the snapshot's TMDB numbers with the IMDb rating", () {
      final result = ExternalRatings.combine(tmdbScore: 8.4, tmdbVotes: 3780, imdb: rating);

      expect(result, const ExternalRatings(tmdbScore: 8.4, tmdbVotes: 3780, imdbRating: 8.2, imdbVotes: 135825));
      expect(result.hasAnyRating, isTrue);
    });

    test('a never-fetched IMDb half leaves the IMDb fields null and keeps the TMDB score', () {
      final result = ExternalRatings.combine(tmdbScore: 8.4, tmdbVotes: 3780, imdb: null);

      expect(result, const ExternalRatings(tmdbScore: 8.4, tmdbVotes: 3780, imdbRating: null, imdbVotes: null));
      expect(result.hasAnyRating, isTrue);
    });

    test('nothing on either side has no rating to show', () {
      final result = ExternalRatings.combine(tmdbScore: null, tmdbVotes: null, imdb: ImdbRating.empty);

      expect(result.hasAnyRating, isFalse);
    });

    test('a voteless TMDB score does not count, the IMDb rating alone does', () {
      expect(ExternalRatings.combine(tmdbScore: 8.4, tmdbVotes: 0, imdb: null).hasAnyRating, isFalse);
      expect(ExternalRatings.combine(tmdbScore: 8.4, tmdbVotes: 0, imdb: rating).hasAnyRating, isTrue);
    });
  });
}
