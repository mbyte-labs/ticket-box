import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/movie/movie_details.dart';

/// `/movie/{id}?append_to_response=external_ids,release_dates,videos`.
void main() {
  final fixture = <String, dynamic>{
    'id': 550,
    'title': 'Fight Club',
    'overview': 'A ticking-time-bomb insomniac and a slippery soap salesman...',
    'tagline': 'Mischief. Mayhem. Soap.',
    'release_date': '1999-10-15',
    'runtime': 139,
    'status': 'Released',
    'homepage': 'http://www.foxmovies.com/movies/fight-club',
    'imdb_id': 'tt0137523',
    'original_language': 'en',
    'production_countries': [
      {'iso_3166_1': 'DE', 'name': 'Germany'},
      {'iso_3166_1': 'US', 'name': 'United States of America'},
    ],
    'popularity': 61.4,
    'vote_average': 8.4,
    'vote_count': 26280,
    'genres': [
      {'id': 18, 'name': 'Drama'},
      {'id': 53, 'name': 'Thriller'},
    ],
    'release_dates': {
      'results': [
        {
          'iso_3166_1': 'US',
          'release_dates': [
            {'certification': '', 'type': 1, 'release_date': '1999-09-21T00:00:00.000Z'},
            {'certification': 'R', 'type': 3, 'release_date': '1999-10-15T00:00:00.000Z'},
          ],
        },
        {
          'iso_3166_1': 'DE',
          'release_dates': [
            {'certification': '18', 'type': 3, 'release_date': '1999-11-11T00:00:00.000Z'},
          ],
        },
      ],
    },
    'videos': {
      'results': [
        {'name': 'Trailer', 'key': 'abc', 'site': 'YouTube', 'type': 'Trailer', 'official': false},
      ],
    },
    'external_ids': {
      'imdb_id': 'tt0137523',
      'wikidata_id': 'Q190050',
      'facebook_id': 'FightClub',
      'instagram_id': null,
      'twitter_id': null,
    },
    'poster_path': '/poster.jpg',
    'backdrop_path': '/backdrop.jpg',
  };

  test('parses the movie header and the appended objects', () {
    final movie = TmdbMovieDetails.fromJson(fixture);

    expect(movie.id, 550);
    expect(movie.title, 'Fight Club');
    expect(movie.releaseDate, '1999-10-15');
    expect(movie.runtime, 139);
    expect(movie.status, 'Released');
    expect(movie.imdbId, 'tt0137523');
    expect(movie.productionCountries.map((c) => c.iso3166_1), ['DE', 'US']);
    expect(movie.voteAverage, 8.4);
    expect(movie.voteCount, 26280);
    expect(movie.genres.map((g) => g.id), [18, 53]);
    expect(movie.externalIds?.wikidataId, 'Q190050');
    expect(movie.videos?.results.single.site, 'YouTube');
    expect(movie.backdropPath, '/backdrop.jpg');
  });

  test('the first non-empty certification per country wins', () {
    final movie = TmdbMovieDetails.fromJson(fixture);

    expect(movie.releaseDates?.certificationForCountry('US'), 'R');
    expect(movie.releaseDates?.certificationForCountry('DE'), '18');
    expect(movie.releaseDates?.certificationForCountry('FR'), isNull);
    expect(movie.releaseDates?.results.first.releaseDates.first.type, 1);
  });

  test('a minimal payload (an unreleased movie) parses with defaults', () {
    final movie = TmdbMovieDetails.fromJson({'id': 1, 'title': 'Untitled', 'release_date': '', 'runtime': null, 'imdb_id': null});

    expect(movie.title, 'Untitled');
    expect(movie.releaseDate, '');
    expect(movie.runtime, isNull);
    expect(movie.imdbId, isNull);
    expect(movie.productionCountries, isEmpty);
    expect(movie.genres, isEmpty);
    expect(movie.voteAverage, 0);
    expect(movie.voteCount, 0);
    expect(movie.releaseDates, isNull);
    expect(movie.videos, isNull);
  });

  test('integer vote_average and popularity decode as doubles', () {
    final movie = TmdbMovieDetails.fromJson({'id': 1, 'vote_average': 7, 'popularity': 12});

    expect(movie.voteAverage, 7.0);
    expect(movie.popularity, 12.0);
  });
}
