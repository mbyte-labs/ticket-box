import 'package:ticketbox/api/tmdb/v3/discover/discover_params.dart';
import 'package:ticketbox/common/model/discover_mode.dart';
import 'package:ticketbox/common/model/filter/genres/genres.dart';
import 'package:ticketbox/common/model/filter/rating/rating_range.dart';
import 'package:ticketbox/common/model/filter/year/year_range.dart';

/// Translates the Discover page's filter models into [TmdbDiscoverParams].
///
/// Pure, so the mapping rules are unit testable without a network. A bound is only emitted when
/// the user actually narrowed it below the allowed range: a slider left at its full extent must
/// produce an empty [TmdbDiscoverParams], because that is what decides whether page one may be
/// served from the cache and whether the trending list can be used at all (it has no filters).
///
/// The minimum vote count is a Top rated concern only: a popularity sort is not distorted by a
/// title with a handful of votes, and the trending endpoint accepts no filters anyway.
class DiscoverParamsMapper {
  DiscoverParamsMapper._();

  static TmdbDiscoverParams toParams({
    DiscoverMode mode = DiscoverMode.popular,
    int? minVoteCount,
    FilterRatingRange? ratingRange,
    FilterYearRange? yearRange,
    FilterGenres? genres,
  }) {
    final topRated = mode == DiscoverMode.topRated;
    return TmdbDiscoverParams(
      genreIds: genres == null ? const [] : genres.selectedGenres.map((genre) => genre.id).toList(),
      yearFrom: yearRange != null && yearRange.minYear > yearRange.minAllowedYear ? yearRange.minYear : null,
      yearTo: yearRange != null && yearRange.maxYear < yearRange.maxAllowedYear ? yearRange.maxYear : null,
      voteAverageFrom: ratingRange != null && ratingRange.minRange > ratingRange.minAllowedRange ? ratingRange.minRange : null,
      voteAverageTo: ratingRange != null && ratingRange.maxRange < ratingRange.maxAllowedRange ? ratingRange.maxRange : null,
      sort: topRated ? TmdbDiscoverSort.voteAverage : TmdbDiscoverSort.popularity,
      minVoteCount: topRated ? minVoteCount : null,
    );
  }
}
