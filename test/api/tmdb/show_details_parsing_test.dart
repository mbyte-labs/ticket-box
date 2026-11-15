import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details.dart';

/// `/tv/{id}?append_to_response=external_ids,content_ratings,videos,season/1,season/2` as TMDB
/// answers it for a show between seasons: no next episode scheduled, an unaired episode with no
/// date or runtime, and the deprecated `episode_run_time` empty.
void main() {
  final fixture = <String, dynamic>{
    'id': 1399,
    'name': 'Game of Thrones',
    'overview': 'Seven noble families fight for control of the mythical land of Westeros.',
    'tagline': 'Winter Is Coming',
    'first_air_date': '2011-04-17',
    'last_air_date': '2019-05-19',
    'status': 'Ended',
    'type': 'Scripted',
    'in_production': false,
    'homepage': 'https://www.hbo.com/game-of-thrones',
    'original_language': 'en',
    'origin_country': ['US'],
    'episode_run_time': <int>[],
    'number_of_seasons': 8,
    'number_of_episodes': 73,
    'popularity': 1234.5,
    'vote_average': 8.456,
    'vote_count': 24000,
    'genres': [
      {'id': 10765, 'name': 'Sci-Fi & Fantasy'},
      {'id': 18, 'name': 'Drama'},
    ],
    'networks': [
      {'id': 49, 'name': 'HBO', 'logo_path': '/hbo.png', 'origin_country': 'US'},
    ],
    'seasons': [
      {
        'id': 3627,
        'season_number': 0,
        'episode_count': 282,
        'air_date': '2010-12-05',
        'name': 'Specials',
        'overview': '',
        'poster_path': null,
        'vote_average': 0,
      },
      {
        'id': 3624,
        'season_number': 1,
        'episode_count': 10,
        'air_date': '2011-04-17',
        'name': 'Season 1',
        'poster_path': '/s1.jpg',
        'vote_average': 8.3,
      },
      {
        'id': 3625,
        'season_number': 2,
        'episode_count': 10,
        'air_date': '2012-04-01',
        'name': 'Season 2',
        'poster_path': '/s2.jpg',
        'vote_average': 8.2,
      },
    ],
    'last_episode_to_air': {
      'id': 1551830,
      'name': 'The Iron Throne',
      'air_date': '2019-05-19',
      'episode_number': 6,
      'episode_type': 'finale',
      'runtime': 80,
      'season_number': 8,
      'vote_average': 4.7,
      'vote_count': 300,
    },
    'next_episode_to_air': null,
    'external_ids': {
      'imdb_id': 'tt0944947',
      'tvdb_id': 121361,
      'wikidata_id': 'Q23572',
      'facebook_id': 'GameOfThrones',
      'instagram_id': null,
      'twitter_id': 'GameOfThrones',
    },
    'content_ratings': {
      'results': [
        {'descriptors': <String>[], 'iso_3166_1': 'US', 'rating': 'TV-MA'},
        {'descriptors': <String>[], 'iso_3166_1': 'DE', 'rating': '16'},
      ],
    },
    'videos': {
      'results': [
        {'iso_639_1': 'en', 'name': 'Official Trailer', 'key': 'KPLWWIOCOOQ', 'site': 'YouTube', 'type': 'Trailer', 'official': true},
      ],
    },
    'poster_path': '/poster.jpg',
    'backdrop_path': '/backdrop.jpg',
    'season/1': {
      'id': 3624,
      'season_number': 1,
      'name': 'Season 1',
      'overview': 'Trouble is brewing in the Seven Kingdoms.',
      'air_date': '2011-04-17',
      'poster_path': '/s1.jpg',
      'vote_average': 8.3,
      'episodes': [
        {
          'id': 63056,
          'episode_number': 1,
          'season_number': 1,
          'name': 'Winter Is Coming',
          'overview': 'Jon Arryn, the Hand of the King, is dead.',
          'air_date': '2011-04-17',
          'runtime': 62,
          'episode_type': 'standard',
          'vote_average': 8.1,
          'vote_count': 350,
          'still_path': '/e1.jpg',
          'production_code': '101',
        },
        {
          'id': 63057,
          'episode_number': 2,
          'season_number': 1,
          'name': 'The Kingsroad',
          'overview': '',
          'air_date': null,
          'runtime': null,
          'episode_type': 'standard',
          'vote_average': 0,
          'vote_count': 0,
          'still_path': null,
        },
      ],
    },
    'season/2': {
      'id': 3625,
      'season_number': 2,
      'name': 'Season 2',
      'air_date': '2012-04-01',
      'poster_path': null,
      'episodes': <Map<String, dynamic>>[],
    },
  };

  test('parses the show header and the appended objects', () {
    final show = TmdbShowDetails.fromJson(fixture);

    expect(show.id, 1399);
    expect(show.name, 'Game of Thrones');
    expect(show.status, 'Ended');
    expect(show.inProduction, isFalse);
    expect(show.originCountry, ['US']);
    expect(show.episodeRunTime, isEmpty);
    expect(show.numberOfSeasons, 8);
    expect(show.numberOfEpisodes, 73);
    expect(show.voteAverage, 8.456);
    expect(show.voteCount, 24000);
    expect(show.genres.map((g) => g.name), ['Sci-Fi & Fantasy', 'Drama']);
    expect(show.networks.single.name, 'HBO');
    expect(show.externalIds?.imdbId, 'tt0944947');
    expect(show.imdbId, 'tt0944947');
    expect(show.externalIds?.tvdbId, 121361);
    expect(show.externalIds?.instagramId, isNull);
    expect(show.contentRatings?.forCountry('US'), 'TV-MA');
    expect(show.contentRatings?.forCountry('FR'), isNull);
    expect(show.videos?.results.single.key, 'KPLWWIOCOOQ');
    expect(show.videos?.results.single.official, isTrue);
    expect(show.posterPath, '/poster.jpg');
  });

  test('parses the season stubs and the last/next episode, with next being null', () {
    final show = TmdbShowDetails.fromJson(fixture);

    expect(show.seasons.map((s) => s.seasonNumber), [0, 1, 2]);
    expect(show.seasons.first.name, 'Specials');
    expect(show.seasons.first.posterPath, isNull);
    expect(show.seasons[1].episodeCount, 10);
    expect(show.seasons[1].voteAverage, 8.3);
    expect(show.lastEpisodeToAir?.seasonNumber, 8);
    expect(show.lastEpisodeToAir?.episodeNumber, 6);
    expect(show.lastEpisodeToAir?.episodeType, 'finale');
    expect(show.lastEpisodeToAir?.runtime, 80);
    expect(show.nextEpisodeToAir, isNull);
  });

  test('folds the season/N keys into appendedSeasons, keyed by season number', () {
    final show = TmdbShowDetails.fromJson(fixture);

    expect(show.appendedSeasons.keys, unorderedEquals([1, 2]));
    final season1 = show.appendedSeasons[1]!;
    expect(season1.id, 3624);
    expect(season1.seasonNumber, 1);
    expect(season1.episodes, hasLength(2));
    expect(season1.episodes.first.name, 'Winter Is Coming');
    expect(season1.episodes.first.runtime, 62);
    expect(season1.episodes.first.voteCount, 350);
    expect(season1.episodes.first.productionCode, '101');
    expect(show.appendedSeasons[2]!.episodes, isEmpty);
    expect(show.appendedSeasons[2]!.posterPath, isNull);
  });

  test('an unaired episode with null air_date and runtime parses', () {
    final show = TmdbShowDetails.fromJson(fixture);

    final unaired = show.appendedSeasons[1]!.episodes[1];
    expect(unaired.airDate, isNull);
    expect(unaired.runtime, isNull);
    expect(unaired.stillPath, isNull);
    expect(unaired.productionCode, isNull);
    expect(unaired.voteAverage, 0);
    expect(unaired.voteCount, 0);
  });

  test('a payload without appended seasons leaves appendedSeasons empty', () {
    final plain = Map<String, dynamic>.from(fixture)
      ..remove('season/1')
      ..remove('season/2');

    final show = TmdbShowDetails.fromJson(plain);

    expect(show.appendedSeasons, isEmpty);
  });

  test('only exact season/N keys are picked up', () {
    final odd = Map<String, dynamic>.from(fixture)
      ..remove('season/2')
      ..['season/x'] = <String, dynamic>{'id': 1, 'season_number': 9}
      ..['seasons/3'] = <String, dynamic>{'id': 2, 'season_number': 3}
      ..['season/4'] = 'not an object';

    final show = TmdbShowDetails.fromJson(odd);

    expect(show.appendedSeasons.keys, [1]);
  });

  test('a season TMDB does not have comes back as its error object and is skipped', () {
    final withMissing = Map<String, dynamic>.from(fixture)
      ..['season/7'] = <String, dynamic>{
        'success': false,
        'status_code': 34,
        'status_message': 'The resource you requested could not be found.',
      };

    final show = TmdbShowDetails.fromJson(withMissing);

    expect(show.appendedSeasons.keys, unorderedEquals([1, 2]));
  });

  test('an appended season without an id (as TMDB sends them) still parses', () {
    final appended = Map<String, dynamic>.from(fixture);
    final season1 = Map<String, dynamic>.from(appended['season/1'] as Map<String, dynamic>)..remove('id');
    appended['season/1'] = season1;

    final show = TmdbShowDetails.fromJson(appended);

    expect(show.appendedSeasons[1]!.id, isNull);
    expect(show.appendedSeasons[1]!.seasonNumber, 1);
  });

  test('a minimal payload (an announced show) parses with defaults', () {
    final show = TmdbShowDetails.fromJson({'id': 5, 'name': 'Untitled Project'});

    expect(show.name, 'Untitled Project');
    expect(show.firstAirDate, isNull);
    expect(show.inProduction, isFalse);
    expect(show.genres, isEmpty);
    expect(show.seasons, isEmpty);
    expect(show.voteAverage, 0);
    expect(show.externalIds, isNull);
    expect(show.contentRatings, isNull);
  });
}
