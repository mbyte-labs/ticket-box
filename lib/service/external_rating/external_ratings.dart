import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/service/external_rating/imdb_rating.dart';

part 'external_ratings.freezed.dart';
part 'external_ratings.g.dart';

/// Community ratings from sources other than TMDB, shown as the second row of the
/// details-page Ratings card.
///
/// Round-trips through the generic `Caches` table as JSON, so it stores plain numbers —
/// formatting ("84%", "8.2", compact vote counts) happens in the widget. A null field means
/// that source has no data for the item (or was never reached); an instance where every field
/// is null is still a real "nothing exists" answer, distinct from a null [ExternalRatings].
@freezed
abstract class ExternalRatings with _$ExternalRatings {
  const ExternalRatings._();

  const factory ExternalRatings({
    /// TMDB vote_average on the 0–10 scale. For seasons this is the vote-count-weighted
    /// average of the season's episodes (TMDB has no season-level score).
    required double? tmdbScore,
    required int? tmdbVotes,

    /// IMDb rating on the 0–10 scale, via OMDb.
    required double? imdbRating,
    required int? imdbVotes,
  }) = _ExternalRatings;

  factory ExternalRatings.fromJson(Map<String, dynamic> json) => _$ExternalRatingsFromJson(json);

  /// Whether there is anything worth rendering a second Ratings row for.
  bool get hasAnyRating => (tmdbScore != null && (tmdbVotes ?? 0) > 0) || imdbRating != null;

  /// The card model from its two halves: the TMDB numbers of the stored snapshot and the
  /// [ImdbRating] of `ExternalRatingService`. A null [imdb] (never fetched) leaves the IMDb half
  /// empty rather than hiding the TMDB one.
  static ExternalRatings combine({double? tmdbScore, int? tmdbVotes, ImdbRating? imdb}) {
    return ExternalRatings(tmdbScore: tmdbScore, tmdbVotes: tmdbVotes, imdbRating: imdb?.rating, imdbVotes: imdb?.votes);
  }
}
