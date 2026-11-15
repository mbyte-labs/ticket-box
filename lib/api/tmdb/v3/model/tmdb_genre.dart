import 'package:freezed_annotation/freezed_annotation.dart';

part 'tmdb_genre.freezed.dart';
part 'tmdb_genre.g.dart';

/// One entry of `genres[]` on a details payload, or of `/genre/{movie|tv}/list`.
@Freezed(toJson: false)
abstract class TmdbGenre with _$TmdbGenre {
  const factory TmdbGenre({required int id, required String name}) = _TmdbGenre;

  factory TmdbGenre.fromJson(Map<String, dynamic> json) => _$TmdbGenreFromJson(json);
}
