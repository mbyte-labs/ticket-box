import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';

part 'tmdb_list_page.freezed.dart';
part 'tmdb_list_page.g.dart';

/// The `recommendations` / `similar` objects appended to `/movie/{id}`: a list page whose only
/// part a snapshot keeps is `results` — paging is meaningless inside a stored document.
@Freezed(toJson: false)
abstract class TmdbMovieListPage with _$TmdbMovieListPage {
  const factory TmdbMovieListPage({@Default(<TmdbMovieListItem>[]) List<TmdbMovieListItem> results}) = _TmdbMovieListPage;

  factory TmdbMovieListPage.fromJson(Map<String, dynamic> json) => _$TmdbMovieListPageFromJson(json);
}

/// The show counterpart of [TmdbMovieListPage], appended to `/tv/{id}`.
@Freezed(toJson: false)
abstract class TmdbShowListPage with _$TmdbShowListPage {
  const factory TmdbShowListPage({@Default(<TmdbShowListItem>[]) List<TmdbShowListItem> results}) = _TmdbShowListPage;

  factory TmdbShowListPage.fromJson(Map<String, dynamic> json) => _$TmdbShowListPageFromJson(json);
}
