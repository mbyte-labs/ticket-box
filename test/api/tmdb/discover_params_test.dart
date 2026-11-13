import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/discover/discover_params.dart';
import 'package:ticketbox/common/model/item_type.dart';

void main() {
  test('empty params only carry the popularity sort and report isEmpty', () {
    const params = TmdbDiscoverParams();

    expect(params.isEmpty, isTrue);
    expect(params.toQuery(ItemType.movie), {'sort_by': 'popularity.desc'});
    expect(params.toQuery(ItemType.show), {'sort_by': 'popularity.desc'});
  });

  test('a movie query uses primary_release_date and OR-joins genres', () {
    const params = TmdbDiscoverParams(genreIds: [28, 12], yearFrom: 2000, yearTo: 2009, voteAverageFrom: 7.5, voteAverageTo: 9);

    expect(params.isEmpty, isFalse);
    expect(params.toQuery(ItemType.movie), {
      'sort_by': 'popularity.desc',
      'with_genres': '28|12',
      'primary_release_date.gte': '2000-01-01',
      'primary_release_date.lte': '2009-12-31',
      'vote_average.gte': '7.5',
      'vote_average.lte': '9',
      'vote_count.gte': '50',
    });
  });

  test('a tv query uses first_air_date', () {
    const params = TmdbDiscoverParams(genreIds: [18], yearFrom: 2015);

    expect(params.toQuery(ItemType.show), {'sort_by': 'popularity.desc', 'with_genres': '18', 'first_air_date.gte': '2015-01-01'});
  });

  test('a single vote bound still adds the vote_count floor; no vote bound does not', () {
    expect(const TmdbDiscoverParams(voteAverageFrom: 8).toQuery(ItemType.movie), {
      'sort_by': 'popularity.desc',
      'vote_average.gte': '8',
      'vote_count.gte': '50',
    });
    expect(const TmdbDiscoverParams(voteAverageTo: 5).toQuery(ItemType.show), {
      'sort_by': 'popularity.desc',
      'vote_average.lte': '5',
      'vote_count.gte': '50',
    });
    expect(const TmdbDiscoverParams(yearTo: 1999).toQuery(ItemType.movie), {
      'sort_by': 'popularity.desc',
      'primary_release_date.lte': '1999-12-31',
    });
  });

  group('sort and minimum votes', () {
    test('the vote average sort goes on the wire as vote_average.desc', () {
      const params = TmdbDiscoverParams(sort: TmdbDiscoverSort.voteAverage);

      expect(params.toQuery(ItemType.movie), {'sort_by': 'vote_average.desc'});
    });

    test('a minimum vote count is sent as vote_count.gte and leaves the params empty', () {
      const params = TmdbDiscoverParams(sort: TmdbDiscoverSort.voteAverage, minVoteCount: 300);

      expect(params.isEmpty, isTrue);
      expect(params.toQuery(ItemType.show), {'sort_by': 'vote_average.desc', 'vote_count.gte': '300'});
    });

    test('an explicit minimum wins over the 50 floor a vote bound adds', () {
      const params = TmdbDiscoverParams(voteAverageFrom: 8, minVoteCount: 300);

      expect(params.toQuery(ItemType.movie), {'sort_by': 'popularity.desc', 'vote_average.gte': '8', 'vote_count.gte': '300'});
    });

    test('a zero minimum means no floor of its own, so the vote bound floor still applies', () {
      expect(const TmdbDiscoverParams(minVoteCount: 0).toQuery(ItemType.movie), {'sort_by': 'popularity.desc'});
      expect(const TmdbDiscoverParams(minVoteCount: 0, voteAverageFrom: 8).toQuery(ItemType.movie), {
        'sort_by': 'popularity.desc',
        'vote_average.gte': '8',
        'vote_count.gte': '50',
      });
    });
  });
}
