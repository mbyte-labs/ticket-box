import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';

/// `/tv/{id}/season/{n}`. The old hand-written model required `air_date` and `poster_path`,
/// which TMDB nulls for unaired or sparsely edited seasons — both must be optional.
void main() {
  test('parses a season with its episodes', () {
    final season = TmdbSeasonDetails.fromJson({
      '_id': '5256c89f19c2956ff6046d47',
      'id': 3624,
      'season_number': 1,
      'name': 'Season 1',
      'overview': 'Trouble is brewing.',
      'air_date': '2011-04-17',
      'poster_path': '/s1.jpg',
      'vote_average': 8.3,
      'episodes': [
        {
          'id': 63056,
          'episode_number': 1,
          'season_number': 1,
          'name': 'Winter Is Coming',
          'overview': 'Jon Arryn is dead.',
          'air_date': '2011-04-17',
          'runtime': 62,
          'episode_type': 'standard',
          'vote_average': 8.1,
          'vote_count': 350,
          'still_path': '/e1.jpg',
          'production_code': '101',
          'crew': <Map<String, dynamic>>[],
          'guest_stars': <Map<String, dynamic>>[],
        },
        {
          'id': 63066,
          'episode_number': 10,
          'season_number': 1,
          'name': 'Fire and Blood',
          'episode_type': 'finale',
          'vote_average': 8.5,
          'vote_count': 300,
        },
      ],
    });

    expect(season.id, 3624);
    expect(season.seasonNumber, 1);
    expect(season.name, 'Season 1');
    expect(season.airDate, '2011-04-17');
    expect(season.voteAverage, 8.3);
    expect(season.episodes, hasLength(2));
    expect(season.episodes.first.episodeNumber, 1);
    expect(season.episodes.first.seasonNumber, 1);
    expect(season.episodes.first.runtime, 62);
    expect(season.episodes.first.stillPath, '/e1.jpg');
    expect(season.episodes.last.episodeType, 'finale');
    expect(season.episodes.last.airDate, isNull);
    expect(season.episodes.last.runtime, isNull);
  });

  test('null air_date and poster_path are fine (unaired season)', () {
    final season = TmdbSeasonDetails.fromJson({
      'id': 9999,
      'season_number': 3,
      'name': 'Season 3',
      'air_date': null,
      'poster_path': null,
      'episodes': <Map<String, dynamic>>[],
    });

    expect(season.airDate, isNull);
    expect(season.posterPath, isNull);
    expect(season.voteAverage, isNull);
    expect(season.episodes, isEmpty);
  });

  test('a missing episodes key defaults to an empty list', () {
    final season = TmdbSeasonDetails.fromJson({'id': 1, 'season_number': 0});

    expect(season.episodes, isEmpty);
  });

  test('episode votes default to zero when TMDB omits them', () {
    final season = TmdbSeasonDetails.fromJson({
      'id': 1,
      'season_number': 1,
      'episodes': [
        {'id': 10, 'episode_number': 1, 'season_number': 1},
      ],
    });

    expect(season.episodes.single.voteAverage, 0);
    expect(season.episodes.single.voteCount, 0);
  });
}
