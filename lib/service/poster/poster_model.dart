import 'package:ticketbox/common/model/episode_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';

/// The user's marks on one title, read from the user tables — never stored on the tile.
class LibraryMarks {
  /// A movie: any play. A show: any episode play (or finished, where the grid says so). A season /
  /// episode: a play of it.
  final bool watched;
  final bool watchListed;
  final bool dropped;
  final bool favorite;

  /// The user's 1–10 rating; for a season the formatted average of its episode ratings.
  final String? userRating;

  const LibraryMarks({this.watched = false, this.watchListed = false, this.dropped = false, this.favorite = false, this.userRating});

  static const LibraryMarks none = LibraryMarks();

  @override
  bool operator ==(Object other) =>
      other is LibraryMarks &&
      other.watched == watched &&
      other.watchListed == watchListed &&
      other.dropped == dropped &&
      other.favorite == favorite &&
      other.userRating == userRating;

  @override
  int get hashCode => Object.hash(watched, watchListed, dropped, favorite, userRating);
}

/// One poster tile, built in memory from a catalogue row (a tracked title), a season or episode
/// row, or a TMDB list payload (a browsed title) plus the user's [marks]. Nothing about it is
/// stored: the grids rebuild their tiles on every data change.
class PosterModel {
  final MediaKey key;

  /// What the tile shows under the artwork; for an episode `S1xE2 Name`.
  final String title;

  /// Drawn on the text placeholder when there is no artwork.
  final String noPosterText;

  /// TMDB's relative poster path (a season tile: the season's, an episode tile: the season's).
  final String? posterPath;

  /// An episode's still, for the still tiles.
  final String? stillPath;

  /// Whether the title is in the library — its artwork lives on disk and every action on it is
  /// local.
  final bool tracked;

  /// TMDB's community score, `7.3`, or null.
  final String? rating;
  final LibraryMarks marks;
  final EpisodeType episodeType;

  /// An Up Next episode that has not aired yet by the device's "today"; drives the orange "Airs …"
  /// pill. Only the Up Next builder sets it.
  final bool upcoming;

  /// The episode's air date, `YYYY-MM-DD`, or null when unscheduled. Read only with [upcoming].
  final String? airDate;

  const PosterModel({
    required this.key,
    required this.title,
    required this.noPosterText,
    required this.posterPath,
    this.stillPath,
    required this.tracked,
    required this.rating,
    this.marks = LibraryMarks.none,
    this.episodeType = EpisodeType.standard,
    this.upcoming = false,
    this.airDate,
  });

  ItemType get type => key.type;

  /// The arithmetic grid id that used to be the poster row's primary key:
  /// `disc·10¹⁶ + tmdbId·10⁸ + season·10⁴ + episode`, unique across types.
  int get id => gridId(key);

  static int gridId(MediaKey key) {
    final discriminator = switch (key.type) {
      ItemType.movie => 9,
      ItemType.show => 1,
      ItemType.season => 2,
      ItemType.episode => 3,
    };
    return discriminator * 10000000000000000 + key.tmdbId * 100000000 + key.season * 10000 + key.episode;
  }

  bool get seasonPremiere => episodeType == EpisodeType.seasonPremiere;

  bool get seasonFinale => episodeType == EpisodeType.seasonFinale;

  bool get seriesFinale => episodeType == EpisodeType.seriesFinale;

  bool get midSeasonFinale => episodeType == EpisodeType.midSeasonFinale;

  PosterModel withMarks(LibraryMarks marks) => copyWith(marks: marks);

  PosterModel copyWith({
    String? title,
    String? noPosterText,
    String? posterPath,
    String? stillPath,
    bool? tracked,
    String? rating,
    LibraryMarks? marks,
    EpisodeType? episodeType,
    bool? upcoming,
    String? airDate,
  }) {
    return PosterModel(
      key: key,
      title: title ?? this.title,
      noPosterText: noPosterText ?? this.noPosterText,
      posterPath: posterPath ?? this.posterPath,
      stillPath: stillPath ?? this.stillPath,
      tracked: tracked ?? this.tracked,
      rating: rating ?? this.rating,
      marks: marks ?? this.marks,
      episodeType: episodeType ?? this.episodeType,
      upcoming: upcoming ?? this.upcoming,
      airDate: airDate ?? this.airDate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PosterModel &&
      other.key == key &&
      other.title == title &&
      other.noPosterText == noPosterText &&
      other.posterPath == posterPath &&
      other.stillPath == stillPath &&
      other.tracked == tracked &&
      other.rating == rating &&
      other.marks == marks &&
      other.episodeType == episodeType &&
      other.upcoming == upcoming &&
      other.airDate == airDate;

  @override
  int get hashCode => Object.hash(key, title, posterPath, stillPath, tracked, rating, marks, episodeType, upcoming, airDate);

  @override
  String toString() => 'PosterModel($key, $title)';
}
