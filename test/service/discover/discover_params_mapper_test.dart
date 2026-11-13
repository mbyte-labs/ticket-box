import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/discover/discover_params.dart';
import 'package:ticketbox/common/model/discover_mode.dart';
import 'package:ticketbox/common/model/filter/genres/genre.dart';
import 'package:ticketbox/common/model/filter/genres/genres.dart';
import 'package:ticketbox/common/model/filter/rating/rating_range.dart';
import 'package:ticketbox/common/model/filter/year/year_range.dart';
import 'package:ticketbox/service/discover/discover_params_mapper.dart';

/// Pins the one property the discover services depend on: a filter sheet left at its defaults
/// maps to an *empty* [TmdbDiscoverParams], which is what lets page one come from the cache and
/// the trending endpoint be used at all. Everything narrower has to make it onto the wire.
void main() {
  const drama = Genre(id: 18, name: 'Drama');
  const comedy = Genre(id: 35, name: 'Comedy');

  group('nothing selected', () {
    test('null filters map to empty params', () {
      expect(DiscoverParamsMapper.toParams().isEmpty, isTrue);
    });

    test('filters at their full allowed extent map to empty params', () {
      final params = DiscoverParamsMapper.toParams(
        ratingRange: FilterRatingRange.initial(),
        yearRange: FilterYearRange.initial(),
        genres: const FilterGenres(availableGenres: [drama, comedy], selectedGenres: []),
      );

      expect(params.isEmpty, isTrue);
    });
  });

  group('genres', () {
    test('selected genres become their TMDB ids, in selection order', () {
      final params = DiscoverParamsMapper.toParams(
        genres: const FilterGenres(availableGenres: [drama, comedy], selectedGenres: [comedy, drama]),
      );

      expect(params.genreIds, [35, 18]);
    });

    test('available but unselected genres are not sent', () {
      final params = DiscoverParamsMapper.toParams(
        genres: const FilterGenres(availableGenres: [drama, comedy], selectedGenres: [drama]),
      );

      expect(params.genreIds, [18]);
    });
  });

  group('years', () {
    const range = FilterYearRange(minAllowedYear: 1900, maxAllowedYear: 2031, minYear: 1900, maxYear: 2031);

    test('only a raised lower bound sets yearFrom', () {
      final params = DiscoverParamsMapper.toParams(yearRange: range.copyWith(minYear: 1990));

      expect(params.yearFrom, 1990);
      expect(params.yearTo, isNull);
    });

    test('only a lowered upper bound sets yearTo', () {
      final params = DiscoverParamsMapper.toParams(yearRange: range.copyWith(maxYear: 2010));

      expect(params.yearFrom, isNull);
      expect(params.yearTo, 2010);
    });

    test('both bounds narrowed are both sent', () {
      final params = DiscoverParamsMapper.toParams(yearRange: range.copyWith(minYear: 2000, maxYear: 2005));

      expect((params.yearFrom, params.yearTo), (2000, 2005));
    });
  });

  group('rating', () {
    const range = FilterRatingRange(minAllowedRange: 1, maxAllowedRange: 10, minRange: 1, maxRange: 10);

    test('only a raised lower bound sets voteAverageFrom', () {
      final params = DiscoverParamsMapper.toParams(ratingRange: range.copyWith(minRange: 7.5));

      expect(params.voteAverageFrom, 7.5);
      expect(params.voteAverageTo, isNull);
      expect(params.hasVoteFilter, isTrue);
    });

    test('only a lowered upper bound sets voteAverageTo', () {
      final params = DiscoverParamsMapper.toParams(ratingRange: range.copyWith(maxRange: 6));

      expect(params.voteAverageFrom, isNull);
      expect(params.voteAverageTo, 6);
    });
  });

  group('list and minimum votes', () {
    test('popular sorts by popularity and sends no vote floor even when given one', () {
      final params = DiscoverParamsMapper.toParams(mode: DiscoverMode.popular, minVoteCount: 300);

      expect(params.sort, TmdbDiscoverSort.popularity);
      expect(params.minVoteCount, isNull);
      expect(params.isEmpty, isTrue);
    });

    test('trending sorts by popularity and sends no vote floor either', () {
      final params = DiscoverParamsMapper.toParams(mode: DiscoverMode.trending, minVoteCount: 300);

      expect(params.sort, TmdbDiscoverSort.popularity);
      expect(params.minVoteCount, isNull);
      expect(params.isEmpty, isTrue);
    });

    test('top rated sorts by vote average with the given vote floor, and stays empty', () {
      final params = DiscoverParamsMapper.toParams(mode: DiscoverMode.topRated, minVoteCount: 300);

      expect(params.sort, TmdbDiscoverSort.voteAverage);
      expect(params.minVoteCount, 300);
      expect(params.isEmpty, isTrue);
    });

    test('the mode defaults to popular', () {
      expect(DiscoverParamsMapper.toParams().sort, TmdbDiscoverSort.popularity);
    });
  });

  test('every filter kind lands in one params object', () {
    final params = DiscoverParamsMapper.toParams(
      ratingRange: const FilterRatingRange(minAllowedRange: 1, maxAllowedRange: 10, minRange: 8, maxRange: 10),
      yearRange: const FilterYearRange(minAllowedYear: 1900, maxAllowedYear: 2031, minYear: 1900, maxYear: 1999),
      genres: const FilterGenres(availableGenres: [drama], selectedGenres: [drama]),
    );

    expect(params.isEmpty, isFalse);
    expect(params.genreIds, [18]);
    expect(params.yearTo, 1999);
    expect(params.voteAverageFrom, 8);
  });
}
