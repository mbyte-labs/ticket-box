import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/filter/genres/genre.dart';

part 'genres.freezed.dart';

part 'genres.g.dart';

@freezed
abstract class FilterGenres with _$FilterGenres {
  const factory FilterGenres({required List<Genre> availableGenres, required List<Genre> selectedGenres}) = _FilterGenres;

  factory FilterGenres.initial() {
    return const FilterGenres(availableGenres: [], selectedGenres: []);
  }

  factory FilterGenres.fromJson(Map<String, dynamic> json) => _$FilterGenresFromJson(json);
}
