import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/poster/poster_model.dart';

/// One row of a browse list (search, discover, trending): the few fields a tile needs, taken from
/// TMDB's list payload. Never written to the catalogue — browsing writes nothing — only the first
/// discover page is cached as these entries so it paints offline.
class BrowseEntry {
  final ItemType type;
  final int tmdbId;
  final String? title;
  final String? posterPath;
  final double voteAverage;

  /// `YYYY-MM-DD` release / first-air date, or null.
  final String? date;

  const BrowseEntry({
    required this.type,
    required this.tmdbId,
    required this.title,
    required this.posterPath,
    required this.voteAverage,
    required this.date,
  });

  factory BrowseEntry.movie(TmdbMovieListItem item) => BrowseEntry(
    type: ItemType.movie,
    tmdbId: item.id,
    title: item.title,
    posterPath: item.posterPath,
    voteAverage: item.voteAverage,
    date: item.releaseDate,
  );

  factory BrowseEntry.show(TmdbShowListItem item) => BrowseEntry(
    type: ItemType.show,
    tmdbId: item.id,
    title: item.name,
    posterPath: item.posterPath,
    voteAverage: item.voteAverage,
    date: item.firstAirDate,
  );

  factory BrowseEntry.fromJson(Map<String, dynamic> json) {
    return BrowseEntry(
      type: json['type'] == 'show' ? ItemType.show : ItemType.movie,
      tmdbId: json['id'] as int,
      title: json['title'] as String?,
      posterPath: json['poster_path'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
      date: json['date'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'id': tmdbId,
    'title': title,
    'poster_path': posterPath,
    'vote_average': voteAverage,
    'date': date,
  };

  MediaKey get key => MediaKey(type: type, tmdbId: tmdbId);

  /// A tile without marks; the grid stamps them.
  PosterModel toPosterModel() {
    const noTitle = '-No title available-';
    return PosterModel(
      key: key,
      title: title ?? noTitle,
      noPosterText: title ?? noTitle,
      posterPath: posterPath,
      tracked: false,
      rating: voteAverage <= 0 ? null : voteAverage.toStringAsFixed(1),
    );
  }
}
