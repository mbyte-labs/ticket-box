import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/ui/pages/app_init_page/app_init_page_bloc.dart';
import 'package:ticketbox/ui/routes.dart';

void main() {
  test('a drawer destination is used as stored', () {
    expect(AppInitPageBloc.resolveLandingRoute(Routes.discover), Routes.discover);
    expect(AppInitPageBloc.resolveLandingRoute(Routes.history), Routes.history);
    expect(AppInitPageBloc.resolveLandingRoute(Routes.lists), Routes.lists);
  });

  test('a stored watchlist landing page still lands there, though it moved under lists', () {
    expect(AppInitPageBloc.resolveLandingRoute(Routes.watchlist), Routes.watchlist);
  });

  test('the retired shows and movies pages land on discover', () {
    expect(AppInitPageBloc.resolveLandingRoute('Shows'), Routes.discover);
    expect(AppInitPageBloc.resolveLandingRoute('Movies'), Routes.discover);
  });

  test('anything else falls back to up next', () {
    expect(AppInitPageBloc.resolveLandingRoute(null), Routes.upNextToWatch);
    expect(AppInitPageBloc.resolveLandingRoute(''), Routes.upNextToWatch);
    expect(AppInitPageBloc.resolveLandingRoute('Calendar'), Routes.upNextToWatch);
    expect(AppInitPageBloc.resolveLandingRoute(Routes.movieDetails), Routes.upNextToWatch);
  });
}
