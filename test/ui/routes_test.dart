import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/ui/routes.dart';

/// The router has no sign-in or sync pages left and every details route is keyed by TMDB ids.
void main() {
  final config = Routes.configuration.configuration;

  test('details routes resolve from TMDB ids', () {
    expect(config.namedLocation(Routes.movieDetails, pathParameters: {'tmdbId': '603'}), '/movie/603');
    expect(config.namedLocation(Routes.showDetails, pathParameters: {'showTmdbId': '1396'}), '/show/1396');
    expect(config.namedLocation(Routes.seasonDetails, pathParameters: {'showTmdbId': '1396', 'season': '1'}), '/show/1396/season/1');
    expect(
      config.namedLocation(Routes.episodeDetails, pathParameters: {'showTmdbId': '1396', 'season': '1', 'episode': '2'}),
      '/show/1396/season/1/episode/2',
    );
    expect(config.namedLocation(Routes.personDetails, pathParameters: {'personTmdbId': '287'}), '/person/287');
  });

  test('the lists page and its built-in lists resolve', () {
    expect(config.namedLocation(Routes.lists), '/lists');
    expect(config.namedLocation(Routes.watchlist), '/watchlist');
    expect(config.namedLocation(Routes.droppedShows), '/lists/dropped-shows');
    expect(config.namedLocation(Routes.favorites), '/lists/favorites');
  });

  test('no sign-in or sync routes remain', () {
    final names = <String>{};
    void collect(List<dynamic> routes) {
      for (final route in routes) {
        // ignore: avoid_dynamic_calls
        final name = route.name as String?;
        if (name != null) {
          names.add(name);
        }
        // ignore: avoid_dynamic_calls
        collect(route.routes as List<dynamic>);
      }
    }

    collect(config.routes);
    expect(names, isNot(contains('Sign In')));
    expect(names, isNot(contains('Full Sync Info')));
    expect(names, isNot(contains('Full Sync Error')));
    expect(names, containsAll([Routes.appInit, Routes.upNextToWatch, Routes.movieDetails, Routes.personDetails]));
  });

  test('the discover page replaced the separate shows and movies pages', () {
    final names = <String>{};
    void collect(List<dynamic> routes) {
      for (final route in routes) {
        // ignore: avoid_dynamic_calls
        final name = route.name as String?;
        if (name != null) {
          names.add(name);
        }
        // ignore: avoid_dynamic_calls
        collect(route.routes as List<dynamic>);
      }
    }

    collect(config.routes);
    expect(names, contains(Routes.discover));
    expect(names, isNot(contains('Shows')));
    expect(names, isNot(contains('Movies')));
    expect(
      config.namedLocation(Routes.discover, queryParameters: {'type': 'shows', 'mode': 'trending'}),
      '/discover?type=shows&mode=trending',
    );
  });
}
