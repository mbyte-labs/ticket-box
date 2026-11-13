import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';

/// The details routes' path parameters are spelled in exactly one place; these pin that spelling.
void main() {
  test('movie', () {
    expect(PosterNavigation.pathParameters(const MediaKey.movie(603)), {'tmdbId': '603'});
  });

  test('show', () {
    expect(PosterNavigation.pathParameters(const MediaKey.show(1396)), {'showTmdbId': '1396'});
  });

  test('season', () {
    expect(PosterNavigation.pathParameters(const MediaKey.season(1396, 2)), {'showTmdbId': '1396', 'season': '2'});
  });

  test('episode', () {
    expect(PosterNavigation.pathParameters(const MediaKey.episode(1396, 2, 7)), {'showTmdbId': '1396', 'season': '2', 'episode': '7'});
  });
}
