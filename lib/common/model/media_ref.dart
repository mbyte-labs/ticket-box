import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';

/// A lightweight, display-ready reference to a movie, show, season or episode.
///
/// Carries the identity ([key]) plus the few fields the UI needs to label the item without
/// loading its summary: title, year and numbering. Entities expose `toRef()`; services and UI pass
/// refs around instead of database rows or API DTOs.
sealed class MediaRef {
  const MediaRef();

  ItemType get type;

  MediaKey get key;

  String? get title;
}

class MovieRef extends MediaRef {
  final int tmdbId;
  final String? imdbId;
  @override
  final String? title;
  final int? year;

  const MovieRef({required this.tmdbId, this.imdbId, this.title, this.year});

  @override
  ItemType get type => ItemType.movie;

  @override
  MediaKey get key => MediaKey.movie(tmdbId);
}

class ShowRef extends MediaRef {
  final int tmdbId;
  final String? imdbId;
  @override
  final String? title;
  final int? year;

  const ShowRef({required this.tmdbId, this.imdbId, this.title, this.year});

  @override
  ItemType get type => ItemType.show;

  @override
  MediaKey get key => MediaKey.show(tmdbId);
}

class SeasonRef extends MediaRef {
  final int showTmdbId;
  final int season;

  /// TMDB's own id for the season, when known.
  final int? tmdbId;
  @override
  final String? title;

  const SeasonRef({required this.showTmdbId, required this.season, this.tmdbId, this.title});

  @override
  ItemType get type => ItemType.season;

  @override
  MediaKey get key => MediaKey.season(showTmdbId, season);
}

class EpisodeRef extends MediaRef {
  final int showTmdbId;
  final int season;
  final int episode;

  /// TMDB's own id for the episode, when known.
  final int? tmdbId;
  @override
  final String? title;

  const EpisodeRef({required this.showTmdbId, required this.season, required this.episode, this.tmdbId, this.title});

  @override
  ItemType get type => ItemType.episode;

  @override
  MediaKey get key => MediaKey.episode(showTmdbId, season, episode);
}
