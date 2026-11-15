import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/people/model/person_details.dart';

/// The one person payload: `/person/{id}?append_to_response=combined_credits,external_ids`.
void main() {
  final personFixture = <String, dynamic>{
    'id': 287,
    'name': 'Brad Pitt',
    'biography': 'William Bradley Pitt is an American actor and film producer.',
    'birthday': '1963-12-18',
    'deathday': null,
    'place_of_birth': 'Shawnee, Oklahoma, USA',
    'homepage': null,
    'profile_path': '/pitt.jpg',
    'imdb_id': 'nm0000093',
    'known_for_department': 'Acting',
    'gender': 2,
    'popularity': 50.1,
    'also_known_as': ['Брэд Питт', ' '],
    'external_ids': {
      'imdb_id': 'nm0000093',
      'wikidata_id': 'Q35332',
      'facebook_id': null,
      'instagram_id': 'bradpittofflcial',
      'twitter_id': null,
      'tvdb_id': null,
    },
    'combined_credits': {
      'cast': [
        {
          'id': 550,
          'media_type': 'movie',
          'title': 'Fight Club',
          'release_date': '1999-10-15',
          'popularity': 61.4,
          'character': 'Tyler Durden',
          'poster_path': '/fc.jpg',
          'vote_average': 8.4,
        },
        {
          'id': 1396,
          'media_type': 'tv',
          'name': 'Friends',
          'first_air_date': '1994-09-22',
          'popularity': 300.2,
          'character': 'Will Colbert',
          'poster_path': '/friends.jpg',
          'episode_count': 1,
          'vote_average': 0,
        },
        // No id: a malformed row TMDB should never send, skipped rather than failing the person.
        {'media_type': 'movie', 'title': 'Broken'},
      ],
      'crew': [
        {
          'id': 68718,
          'media_type': 'movie',
          'title': 'Django Unchained',
          'release_date': '2012-12-25',
          'job': 'Producer',
          'department': 'Production',
        },
      ],
    },
  };

  test('parses the person header and ids', () {
    final person = TmdbPersonDetails.fromJson(personFixture);

    expect(person.id, 287);
    expect(person.name, 'Brad Pitt');
    expect(person.birthday, '1963-12-18');
    expect(person.deathday, isNull);
    expect(person.placeOfBirth, 'Shawnee, Oklahoma, USA');
    expect(person.homepage, isNull);
    expect(person.profilePath, '/pitt.jpg');
    expect(person.imdbId, 'nm0000093');
    expect(person.knownForDepartment, 'Acting');
    // Blanks are the service's job to strip; the model keeps what TMDB sent.
    expect(person.alsoKnownAs, ['Брэд Питт', ' ']);
    expect(person.externalIds?.instagramId, 'bradpittofflcial');
    expect(person.externalIds?.tvdbId, isNull);
  });

  test('parses the appended credits, telling movies from shows, skipping a broken row and ignoring the crew', () {
    final credits = TmdbPersonDetails.fromJson(personFixture).combinedCredits!;

    expect(credits.cast, hasLength(2));
    final movie = credits.cast.first;
    expect(movie.isMovie, isTrue);
    expect(movie.displayTitle, 'Fight Club');
    expect(movie.displayDate, '1999-10-15');
    expect(movie.character, 'Tyler Durden');
    expect(movie.voteAverage, 8.4);
    expect(movie.episodeCount, 0);

    final show = credits.cast.last;
    expect(show.isShow, isTrue);
    expect(show.displayTitle, 'Friends');
    expect(show.displayDate, '1994-09-22');
    expect(show.episodeCount, 1);
    // An integer 0 (no votes) parses as a double.
    expect(show.voteAverage, 0.0);
  });

  test('a person without appended objects parses', () {
    final person = TmdbPersonDetails.fromJson({'id': 1, 'name': 'Nobody'});

    expect(person.externalIds, isNull);
    expect(person.combinedCredits, isNull);
    expect(person.biography, isNull);
    expect(person.alsoKnownAs, isEmpty);
  });

  test('empty combined credits default to an empty cast', () {
    final credits = TmdbCombinedCredits.fromJson({'id': 1});

    expect(credits.cast, isEmpty);
  });
}
