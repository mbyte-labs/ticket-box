import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/item_type.dart';

part 'discover_params.freezed.dart';

/// The orderings `/discover` is asked for, as TMDB's `sort_by` values.
enum TmdbDiscoverSort {
  popularity('popularity.desc'),
  voteAverage('vote_average.desc');

  final String queryValue;

  const TmdbDiscoverSort(this.queryValue);
}

/// The user-facing filters of the Discover page, translated to `/discover` query parameters by
/// [toQuery].
@freezed
abstract class TmdbDiscoverParams with _$TmdbDiscoverParams {
  const TmdbDiscoverParams._();

  const factory TmdbDiscoverParams({
    /// Matched as OR (`with_genres=a|b`), so adding a genre widens the result.
    @Default(<int>[]) List<int> genreIds,
    int? yearFrom,
    int? yearTo,
    double? voteAverageFrom,
    double? voteAverageTo,
    @Default(TmdbDiscoverSort.popularity) TmdbDiscoverSort sort,

    /// `vote_count.gte`. Replaces the 50-vote floor that a vote-average bound adds on its own; 0 or
    /// null means no floor of its own.
    int? minVoteCount,
  }) = _TmdbDiscoverParams;

  /// True when nothing narrows the list: no genre, year or vote-average bound.
  ///
  /// [sort] and [minVoteCount] deliberately do not count. This decides whether page one may be
  /// served from the cache and whether the trending list can be used at all (it has no filters),
  /// and a sorted or vote-floored list is still "the list", not a filtered subset the user picked.
  bool get isEmpty => genreIds.isEmpty && yearFrom == null && yearTo == null && voteAverageFrom == null && voteAverageTo == null;

  bool get hasVoteFilter => voteAverageFrom != null || voteAverageTo != null;

  /// The query parameters for `/discover/movie` ([ItemType.movie]) or `/discover/tv`
  /// ([ItemType.show]). Movies filter on `primary_release_date`, shows on `first_air_date`.
  ///
  /// Any vote-average bound also adds `vote_count.gte=50` unless [minVoteCount] sets a floor of
  /// its own: without it, a title with one 10/10 vote outranks everything, and the "rated 8+"
  /// filter fills up with unknowns.
  Map<String, String> toQuery(ItemType type) {
    final dateField = switch (type) {
      ItemType.movie => 'primary_release_date',
      ItemType.show || ItemType.season || ItemType.episode => 'first_air_date',
    };
    final voteFloor = minVoteCount != null && minVoteCount! > 0 ? minVoteCount : (hasVoteFilter ? 50 : null);

    return <String, String>{
      'sort_by': sort.queryValue,
      if (genreIds.isNotEmpty) 'with_genres': genreIds.join('|'),
      if (yearFrom != null) '$dateField.gte': '$yearFrom-01-01',
      if (yearTo != null) '$dateField.lte': '$yearTo-12-31',
      if (voteAverageFrom != null) 'vote_average.gte': _formatVote(voteAverageFrom!),
      if (voteAverageTo != null) 'vote_average.lte': _formatVote(voteAverageTo!),
      if (voteFloor != null) 'vote_count.gte': '$voteFloor',
    };
  }

  /// `8.0` → `8`, `7.5` → `7.5` — TMDB accepts both, this just keeps URLs tidy and stable.
  static String _formatVote(double value) {
    return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  }
}
