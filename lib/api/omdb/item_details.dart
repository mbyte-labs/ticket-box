// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'item_details.freezed.dart';
part 'item_details.g.dart';

@freezed
abstract class OmdbItemModel with _$OmdbItemModel {
  const factory OmdbItemModel({
    @JsonKey(name: 'Title') required String? title,
    @JsonKey(name: 'Year') required String? year,
    @JsonKey(name: 'Genre') required String? genre,
    @JsonKey(name: 'Director') required String? director,
    @JsonKey(name: 'Writer') required String? writer,
    @JsonKey(name: 'imdbRating') required String? imdbRating,
    @JsonKey(name: 'imdbVotes') required String? imdbVotes,
    @JsonKey(name: 'imdbID') required String? imdbId,
    @JsonKey(name: 'Metascore') required String? metascore,
  }) = _OmdbItemModel;

  factory OmdbItemModel.fromJson(Map<String, dynamic> json) => _$OmdbItemModelFromJson(json);
}
