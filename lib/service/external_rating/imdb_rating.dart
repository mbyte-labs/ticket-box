import 'package:freezed_annotation/freezed_annotation.dart';

part 'imdb_rating.freezed.dart';
part 'imdb_rating.g.dart';

/// IMDb's community rating of one title, via OMDb — what `ExternalRatingService` caches.
///
/// Round-trips through the generic `Caches` table as JSON, so it stores plain numbers —
/// formatting ("8.2", compact vote counts) happens in the widget. An instance whose fields are
/// all null is a real "IMDb has nothing" answer (or the title has no IMDb id) and is cached like
/// any other, distinct from a null [ImdbRating], which means the service never got an answer.
@freezed
abstract class ImdbRating with _$ImdbRating {
  const ImdbRating._();

  const factory ImdbRating({
    /// IMDb rating on the 0–10 scale.
    required double? rating,
    required int? votes,

    /// The IMDb id the answer belongs to. For an episode looked up through its show this is the
    /// episode's own id, which only the OMDb answer reveals.
    required String? imdbId,
  }) = _ImdbRating;

  factory ImdbRating.fromJson(Map<String, dynamic> json) => _$ImdbRatingFromJson(json);

  /// The cached "IMDb has nothing" answer.
  static const ImdbRating empty = ImdbRating(rating: null, votes: null, imdbId: null);
}
