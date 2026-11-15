/// TMDB bodies as the snapshot requests return them, shared by the pruner and read-model tests.
///
/// Deliberately over-sized where the pruner cuts: three provider regions, twelve recommendations,
/// seven posters, thirty-five cast members, a non-YouTube video, twenty guest stars.
library;

Map<String, dynamic> image(String path, double votes, [String? language]) => {
  'aspect_ratio': 0.667,
  'file_path': path,
  'vote_average': votes,
  'vote_count': 10,
  'height': 1500,
  'width': 1000,
  'iso_639_1': language,
};

Map<String, dynamic> cast(int id, {String? character}) => {
  'id': id,
  'name': 'Person $id',
  'profile_path': '/p$id.jpg',
  'order': id,
  'character': character ?? 'Character $id',
};

Map<String, dynamic> provider(int id, int priority) => {
  'display_priority': priority,
  'logo_path': '/logo$id.jpg',
  'provider_name': 'Provider $id',
  'provider_id': id,
};

Map<String, dynamic> movieListItem(int id) => {
  'id': id,
  'title': 'Movie $id',
  'release_date': '2020-01-0${id % 9 + 1}',
  'poster_path': '/m$id.jpg',
};

Map<String, dynamic> showListItem(int id) => {
  'id': id,
  'name': 'Show $id',
  'first_air_date': '2019-01-0${id % 9 + 1}',
  'poster_path': '/s$id.jpg',
};

Map<String, dynamic> watchProviders() => {
  'id': 550,
  'results': {
    'US': {
      'link': 'https://www.themoviedb.org/movie/550/watch?locale=US',
      'flatrate': [provider(8, 2), provider(9, 1)],
      'rent': [provider(2, 1)],
    },
    'GB': {
      'link': 'https://www.themoviedb.org/movie/550/watch?locale=GB',
      'flatrate': [provider(8, 1)],
    },
    'DE': {
      'link': 'https://www.themoviedb.org/movie/550/watch?locale=DE',
      'buy': [provider(3, 1)],
    },
  },
};

/// `/movie/550` with every snapshot section appended.
Map<String, dynamic> rawMovie() => {
  'id': 550,
  'title': 'Fight Club',
  'overview': 'An insomniac and a soap salesman.',
  'release_date': '1999-10-15',
  'runtime': 139,
  'status': 'Released',
  'imdb_id': 'tt0137523',
  'vote_average': 8.4,
  'vote_count': 26280,
  'genres': [
    {'id': 18, 'name': 'Drama'},
    {'id': 53, 'name': 'Thriller'},
  ],
  'poster_path': '/top-level-poster.jpg',
  'backdrop_path': '/top-level-backdrop.jpg',
  'external_ids': {'imdb_id': 'tt0137523'},
  'release_dates': {
    'results': [
      {
        'iso_3166_1': 'US',
        'release_dates': [
          {'certification': 'R', 'type': 3, 'release_date': '1999-10-15T00:00:00.000Z'},
        ],
      },
    ],
  },
  'videos': {
    'results': [
      {'name': 'Vimeo cut', 'key': 'v1', 'site': 'Vimeo', 'type': 'Trailer', 'official': true},
      {'name': 'Trailer', 'key': 'yt1', 'site': 'YouTube', 'type': 'Trailer', 'official': true},
      {'name': 'Teaser', 'key': 'yt2', 'site': 'YouTube', 'type': 'Teaser', 'official': false},
    ],
  },
  'credits': {
    'cast': [for (var i = 0; i < 35; i++) cast(i)],
    'crew': [
      {'id': 900, 'name': 'Director', 'profile_path': null, 'job': 'Director', 'department': 'Directing'},
    ],
  },
  'images': {
    'posters': [
      image('/p-de-9.jpg', 9.0, 'de'),
      image('/p-null-8.jpg', 8.0),
      image('/p-en-7.jpg', 7.0, 'en'),
      image('/p-en-6.jpg', 6.0, 'en'),
      image('/p-5.jpg', 5.0),
      image('/p-4.jpg', 4.0),
      image('/p-3.jpg', 3.0),
    ],
    'backdrops': [image('/b-1.jpg', 5.5), image('/b-2.jpg', 6.5)],
    'logos': [image('/l-1.png', 1.0)],
  },
  'watch/providers': watchProviders(),
  'recommendations': {
    'page': 1,
    'total_pages': 3,
    'total_results': 60,
    'results': [for (var i = 1; i <= 12; i++) movieListItem(100 + i)],
  },
  'similar': {
    'page': 1,
    'total_pages': 1,
    'total_results': 3,
    'results': [for (var i = 1; i <= 3; i++) movieListItem(200 + i)],
  },
};

Map<String, dynamic> rawEpisode(int season, int number, {String? airDate, int guests = 0}) => {
  'id': season * 1000 + number,
  'episode_number': number,
  'season_number': season,
  'name': 'Episode $number',
  'overview': 'Overview $number',
  'air_date': airDate,
  'runtime': 45,
  'episode_type': 'standard',
  'vote_average': 7.5,
  'vote_count': 12,
  'still_path': '/still-$season-$number.jpg',
  'crew': [
    {'id': 901, 'name': 'Writer', 'profile_path': null, 'job': 'Writer', 'department': 'Writing'},
  ],
  'guest_stars': [for (var i = 0; i < guests; i++) cast(500 + i)],
};

/// An appended `season/N` document: no `id`, a Mongo `_id`, episodes with crew and guest stars.
Map<String, dynamic> rawAppendedSeason(int number, {int episodes = 2, int guests = 0}) => {
  '_id': '5256c89f19c2956ff600$number',
  'season_number': number,
  'name': 'Season $number',
  'overview': 'Season $number overview',
  'air_date': '2011-0$number-17',
  'poster_path': '/season-$number.jpg',
  'vote_average': 8.1,
  'episodes': [
    for (var e = 1; e <= episodes; e++) rawEpisode(number, e, airDate: e == episodes ? null : '2011-0$number-${16 + e}', guests: guests),
  ],
};

/// `/tv/1399` with every snapshot section appended plus `season/1`, `season/2` and a `season/99`
/// that does not exist (TMDB's error object).
Map<String, dynamic> rawShow() => {
  'id': 1399,
  'name': 'Game of Thrones',
  'overview': 'Seven noble families.',
  'first_air_date': '2011-04-17',
  'last_air_date': '2019-05-19',
  'status': 'Ended',
  'number_of_seasons': 2,
  'number_of_episodes': 4,
  'vote_average': 8.4,
  'vote_count': 24000,
  'genres': [
    {'id': 18, 'name': 'Drama'},
  ],
  'poster_path': '/show-poster.jpg',
  'backdrop_path': '/show-backdrop.jpg',
  'seasons': [
    {'id': 3624, 'season_number': 1, 'episode_count': 2, 'air_date': '2011-04-17', 'name': 'Season 1', 'poster_path': '/s1.jpg'},
    {'id': 3625, 'season_number': 2, 'episode_count': 2, 'air_date': '2012-04-01', 'name': 'Season 2', 'poster_path': '/s2.jpg'},
  ],
  'external_ids': {'imdb_id': 'tt0944947'},
  'content_ratings': {
    'results': [
      {'iso_3166_1': 'US', 'rating': 'TV-MA'},
    ],
  },
  'videos': {
    'results': [
      {'name': 'Trailer', 'key': 'yt-got', 'site': 'YouTube', 'type': 'Trailer', 'official': true},
    ],
  },
  'aggregate_credits': {
    'cast': [
      for (var i = 0; i < 32; i++)
        {
          'id': i,
          'name': 'Person $i',
          'profile_path': '/p$i.jpg',
          'order': i,
          'total_episode_count': 10,
          'roles': [
            {'character': 'Character $i', 'episode_count': 10},
          ],
        },
    ],
    'crew': [
      {'id': 900, 'name': 'Showrunner', 'profile_path': null, 'jobs': []},
    ],
  },
  'images': {
    'posters': [image('/sp-en-7.jpg', 7.0, 'en'), image('/sp-9.jpg', 9.0)],
    'backdrops': [image('/sb-1.jpg', 5.5)],
  },
  'watch/providers': {
    'id': 1399,
    'results': {
      'US': {
        'link': 'https://www.themoviedb.org/tv/1399/watch?locale=US',
        'flatrate': [provider(8, 1)],
      },
      'RO': {
        'link': 'https://www.themoviedb.org/tv/1399/watch?locale=RO',
        'flatrate': [provider(9, 1)],
      },
    },
  },
  'recommendations': {'page': 1, 'total_pages': 0, 'total_results': 0, 'results': <Map<String, dynamic>>[]},
  'similar': {
    'page': 1,
    'total_pages': 1,
    'total_results': 2,
    'results': [showListItem(1), showListItem(2)],
  },
  'season/1': rawAppendedSeason(1, guests: 20),
  'season/2': rawAppendedSeason(2),
  'season/99': {'success': false, 'status_code': 34, 'status_message': 'The resource you requested could not be found.'},
};
