import 'package:freezed_annotation/freezed_annotation.dart';

part 'genre.freezed.dart';
part 'genre.g.dart';

/// This is the model used by the FilterGenres class to store values.
///
/// The GenresEntity cannot be used directly since it cannot be serialised as json. [id] is TMDB's
/// numeric genre id, which is what `/discover` filters on (`with_genres`).
@freezed
abstract class Genre with _$Genre {
  const factory Genre({required int id, required String name}) = _Genre;

  factory Genre.fromJson(Map<String, dynamic> json) => _$GenreFromJson(json);
}
