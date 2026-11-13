import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/person/person_credit.dart';
import 'package:ticketbox/ui/pages/details/person/person_details_bloc.dart';
import 'package:ticketbox/ui/pages/details/person/person_details_state.dart';
import 'package:ticketbox/ui/pages/details/person/person_filmography_filter.dart';
import 'package:ticketbox/ui/pages/details/person/person_route_args.dart';

/// The person page's one load: header from the route args, then everything from the single
/// person request plus the library marks — and the page's three failure copies. The page is
/// read-only, which the write-nothing test pins down.
void main() {
  const personTmdbId = 287;

  late DatabaseConnectionManager db;
  late List<Request> requests;
  late Future<Response> Function(Request request) answer;

  Response notFound() => Response('{"status_code":34,"status_message":"not found"}', 404);

  /// UTF-8 bytes, as TMDB sends them: `Response(String)` would encode the Cyrillic alias as Latin-1 and throw.
  Response personOk() => Response.bytes(
    utf8.encode(
      json.encode({
        'id': personTmdbId,
        'name': 'Brad Pitt',
        'biography': 'An American actor.',
        'birthday': '1963-12-18',
        'place_of_birth': 'Shawnee, Oklahoma, USA',
        'known_for_department': 'Acting',
        'profile_path': '/pitt.jpg',
        'also_known_as': ['Брэд Питт'],
        'external_ids': {'imdb_id': 'nm0000093', 'instagram_id': 'bradpittofflcial'},
        'combined_credits': {
          'cast': [
            {
              'id': 550,
              'media_type': 'movie',
              'title': 'Fight Club',
              'release_date': '1999-10-15',
              'poster_path': '/fc.jpg',
              'vote_average': 8.4,
            },
            {
              'id': 1396,
              'media_type': 'tv',
              'name': 'Friends',
              'first_air_date': '1994-09-22',
              'poster_path': '/friends.jpg',
              'episode_count': 1,
            },
            {
              'id': 1396,
              'media_type': 'tv',
              'name': 'Friends',
              'first_air_date': '1994-09-22',
              'character': 'Will Colbert',
              'episode_count': 1,
            },
          ],
        },
      }),
    ),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  void serve(Response Function() person) {
    answer = (request) async => request.url.path == '/3/person/$personTmdbId' ? person() : notFound();
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    requests = [];
    answer = (request) async => notFound();
    TmdbHttpClient.forTesting(
      MockClient((request) {
        requests.add(request);
        return answer(request);
      }),
    );
  });

  tearDown(() async {
    TmdbHttpClient.resetForTesting();
    await GetIt.I.reset();
    await db.close();
  });

  /// Runs [init] with every emitted state collected, then closes the bloc.
  Future<List<PersonDetailsState>> run(PersonDetailsBloc bloc) async {
    final states = <PersonDetailsState>[];
    final subscription = bloc.stream.listen(states.add);
    await bloc.init();
    await bloc.close();
    await subscription.cancel();
    return states;
  }

  test('the route args fill the header before anything is loaded', () {
    final bloc = PersonDetailsBloc(
      personTmdbId,
      args: const PersonRouteArgs(name: 'Brad Pitt', photoUrl: 'https://img/pitt.jpg'),
    );

    expect(bloc.state.initialLoading, isTrue);
    expect(bloc.state.name, 'Brad Pitt');
    expect(bloc.state.photoUrl, 'https://img/pitt.jpg');
    expect(bloc.state.filmography, isEmpty);
  });

  test('one request, one state: the bio, the links and the folded filmography', () async {
    serve(personOk);

    final states = await run(PersonDetailsBloc(personTmdbId));

    expect(requests.map((request) => request.url.path), ['/3/person/$personTmdbId']);
    expect(requests.single.url.queryParameters['append_to_response'], 'combined_credits,external_ids');

    expect(states, hasLength(1));
    final state = states.single;
    expect(state.initialLoading, isFalse);
    expect(state.hasError, isFalse);
    expect(state.name, 'Brad Pitt');
    expect(state.biography, 'An American actor.');
    expect(state.knownForDepartment, 'Acting');
    expect(state.birthplace, 'Shawnee, Oklahoma, USA');
    expect(state.alsoKnownAs, ['Брэд Питт']);
    expect(state.photoUrl, endsWith('/pitt.jpg'));
    expect(state.externalLinks.map((link) => link.label), ['TMDB', 'IMDb', 'Instagram']);
    expect(state.externalLinks.map((link) => link.url), [
      'https://www.themoviedb.org/person/$personTmdbId',
      'https://www.imdb.com/name/nm0000093/',
      'https://www.instagram.com/bradpittofflcial',
    ]);

    expect(state.filmography.map((credit) => credit.gridKey), ['movie:550', 'show:1396']);
    expect(state.filmography.first.rating, 8.4);
    expect(state.filmography.last.character, 'Will Colbert');
    expect(state.filmography.last.episodes, 1);
    expect(state.filmography.map((credit) => credit.inLibrary), everyElement(isFalse));
    expect(state.seenWith, isEmpty);
    expect(state.hasBothKinds, isTrue);
  });

  test('the page writes nothing: no movie or show row for the filmography', () async {
    serve(personOk);

    await run(PersonDetailsBloc(personTmdbId));

    expect(await MovieRepo().get(550), isNull);
    expect(await ShowRepo().get(1396), isNull);
  });

  test('a play puts the title under "seen with"', () async {
    serve(personOk);
    await HistoryRepo().insert(
      HistoryEntity.build(
        historyId: 1,
        tmdbId: 550,
        type: ItemType.movie,
        action: HistoryAction.watch,
        watchedAt: DateTime.utc(2026, 7, 1),
      ),
    );

    final state = (await run(PersonDetailsBloc(personTmdbId))).single;

    expect(state.seenWith.map((credit) => credit.gridKey), ['movie:550']);
    expect(state.seenWith.single.watched, isTrue);
  });

  test('the filter narrows the visible filmography without touching the list', () async {
    serve(personOk);
    final bloc = PersonDetailsBloc(personTmdbId);
    await bloc.init();

    expect(bloc.state.movieCount, 1);
    expect(bloc.state.showCount, 1);

    bloc.selectFilter(PersonFilmographyFilter.shows);
    expect(bloc.state.visibleFilmography.map((credit) => credit.kind), [PersonCreditKind.show]);
    expect(bloc.state.filmography, hasLength(2));

    bloc.selectFilter(PersonFilmographyFilter.all);
    expect(bloc.state.visibleFilmography, hasLength(2));

    await bloc.close();
  });

  test('a person TMDB no longer has is the not-found page, and the header keeps what the card knew', () async {
    serve(notFound);

    final states = await run(PersonDetailsBloc(personTmdbId, args: const PersonRouteArgs(name: 'Brad Pitt')));

    expect(states, hasLength(1));
    expect(states.single.initialLoading, isFalse);
    expect(states.single.hasError, isTrue);
    expect(states.single.message, PersonDetailsBloc.notFoundMessage);
    expect(states.single.name, 'Brad Pitt');
  });

  test('TMDB not answering is the unreachable page', () async {
    answer = (request) async => throw ClientException('offline');

    final states = await run(PersonDetailsBloc(personTmdbId));

    expect(states.single.hasError, isTrue);
    expect(states.single.message, PersonDetailsBloc.unreachableMessage);
  });

  test('any other failure names itself', () async {
    serve(() => Response('{"status_code":7}', 403));

    final states = await run(PersonDetailsBloc(personTmdbId));

    expect(states.single.hasError, isTrue);
    expect(states.single.message, startsWith('Loading failed ('));
  });
}
