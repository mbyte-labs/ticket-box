import 'dart:convert';

import 'package:ticketbox/api/tmdb/image_size_util.dart';
import 'package:ticketbox/api/tmdb/v3/model/credit/person_credit.dart';
import 'package:ticketbox/api/tmdb/v3/model/image.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_season_stub.dart';
import 'package:ticketbox/api/tmdb/v3/movie/movie_details.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details.dart';
import 'package:ticketbox/api/tmdb/v3/watch_providers/model.dart';
import 'package:ticketbox/api/tmdb/v3/watch_providers/tmdb_watch_providers_append.dart';
import 'package:ticketbox/common/converter/show.dart';
import 'package:ticketbox/service/catalog/snapshot_freshness.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';
import 'package:ticketbox/service/watch_provider/watch_provider_result.dart';

/// The read models every details page renders, whether the document came out of the database
/// (a tracked item's `metadata_json`) or straight from TMDB (an untracked item viewed live).
///
/// They wrap the API DTOs rather than re-modelling them: the snapshot *is* the provider body, so
/// the page reads the same fields either way, plus the few derived values (trailer, providers for
/// a region, related titles) that used to need a request of their own.

/// Shared by the three snapshots: where the document came from and how fresh it is.
mixin SnapshotOrigin {
  /// When the document was fetched; null for a live (untracked) view.
  DateTime? get fetchedAt;

  /// Whether the document is a stored one (the item is in the library).
  bool get tracked;

  bool get isStale => SnapshotFreshness.isStale(fetchedAt);
}

class MovieSnapshot with SnapshotOrigin {
  final TmdbMovieDetails details;

  @override
  final DateTime? fetchedAt;

  @override
  final bool tracked;

  /// The region the stored `watch/providers` was pruned to; null when none was configured.
  final String? providersRegion;

  const MovieSnapshot({required this.details, required this.fetchedAt, required this.tracked, required this.providersRegion});

  /// A stored document.
  factory MovieSnapshot.fromJson(String metadataJson, {required DateTime? fetchedAt, required String? providersRegion}) {
    return MovieSnapshot(
      details: TmdbMovieDetails.fromJson(decodeSnapshot(metadataJson)),
      fetchedAt: fetchedAt,
      tracked: true,
      providersRegion: providersRegion,
    );
  }

  /// A live view of an untracked movie: [raw] is the TMDB body, pruned here to the same shape a
  /// stored one has so the page renders identically.
  factory MovieSnapshot.live(Map<String, dynamic> raw, {required String? region}) {
    return MovieSnapshot(
      details: TmdbMovieDetails.fromJson(SnapshotPruner.movie(raw, region: region)),
      fetchedAt: null,
      tracked: false,
      providersRegion: region,
    );
  }

  int get tmdbId => details.id;

  String? get imdbId => details.imdbId ?? details.externalIds?.imdbId;

  String? get posterPath => SnapshotPruner.bestImagePath(_imagesJson(details.images?.posters), fallback: details.posterPath);

  String? get backdropPath => SnapshotPruner.bestImagePath(_imagesJson(details.images?.backdrops), fallback: details.backdropPath);

  List<TmdbCastPerson> get cast => details.credits?.cast ?? const [];

  List<TmdbMovieListItem> get related => details.related;

  List<String> get genreNames => details.genres.map((g) => g.name).toList();

  String? get trailerUrl => ShowConverter.youtubeTrailer(details.videos);

  String? certification(String region) => details.releaseDates?.certificationForCountry(region);

  /// The subscription services carrying the movie in [region], or null when the stored document
  /// was pruned to a different region (one refresh away) or TMDB lists nothing there.
  WatchProviderResult? providersFor(String region) => providersFromAppend(details.watchProviders, providersRegion, region);
}

class ShowSnapshot with SnapshotOrigin {
  final TmdbShowDetails details;

  @override
  final DateTime? fetchedAt;

  @override
  final bool tracked;

  final String? providersRegion;

  /// Season documents that arrived appended to a live view (`season/N`); a stored show keeps its
  /// seasons in their own rows, so this is empty for tracked items.
  final Map<int, SeasonSnapshot> appendedSeasons;

  const ShowSnapshot({
    required this.details,
    required this.fetchedAt,
    required this.tracked,
    required this.providersRegion,
    this.appendedSeasons = const {},
  });

  factory ShowSnapshot.fromJson(String metadataJson, {required DateTime? fetchedAt, required String? providersRegion}) {
    return ShowSnapshot(
      details: TmdbShowDetails.fromJson(decodeSnapshot(metadataJson)),
      fetchedAt: fetchedAt,
      tracked: true,
      providersRegion: providersRegion,
    );
  }

  /// A live view of an untracked show. The appended seasons are pruned and kept alongside.
  factory ShowSnapshot.live(Map<String, dynamic> raw, {required String? region}) {
    final pruned = SnapshotPruner.showRoot(raw, region: region);
    return ShowSnapshot(
      details: TmdbShowDetails.fromJson(pruned.root),
      fetchedAt: null,
      tracked: false,
      providersRegion: region,
      appendedSeasons: {for (final entry in pruned.seasons.entries) entry.key: SeasonSnapshot.live(entry.value)},
    );
  }

  int get tmdbId => details.id;

  String? get imdbId => details.imdbId;

  String? get posterPath => SnapshotPruner.bestImagePath(_imagesJson(details.images?.posters), fallback: details.posterPath);

  String? get backdropPath => SnapshotPruner.bestImagePath(_imagesJson(details.images?.backdrops), fallback: details.backdropPath);

  List<TmdbSeasonStub> get seasons => details.seasons;

  /// The show's regulars (aggregate credits); the season and episode pages show the same list.
  List<TmdbCastPerson> get cast => details.aggregateCredits?.cast ?? const [];

  List<TmdbShowListItem> get related => details.related;

  List<String> get genreNames => details.genres.map((g) => g.name).toList();

  String? get trailerUrl => ShowConverter.youtubeTrailer(details.videos);

  String? certification(String region) => details.contentRatings?.forCountry(region);

  WatchProviderResult? providersFor(String region) => providersFromAppend(details.watchProviders, providersRegion, region);
}

class SeasonSnapshot with SnapshotOrigin {
  final TmdbSeasonDetails details;

  @override
  final DateTime? fetchedAt;

  @override
  final bool tracked;

  const SeasonSnapshot({required this.details, required this.fetchedAt, required this.tracked});

  factory SeasonSnapshot.fromJson(String metadataJson, {required DateTime? fetchedAt}) {
    return SeasonSnapshot(details: TmdbSeasonDetails.fromJson(decodeSnapshot(metadataJson)), fetchedAt: fetchedAt, tracked: true);
  }

  /// An already pruned season document (see `SnapshotPruner.season`).
  factory SeasonSnapshot.live(Map<String, dynamic> pruned) {
    return SeasonSnapshot(details: TmdbSeasonDetails.fromJson(pruned), fetchedAt: null, tracked: false);
  }

  int get seasonNumber => details.seasonNumber;

  /// A season document carries no `images` section; its own `poster_path` is the artwork.
  String? get posterPath => details.posterPath;

  List<TmdbSeasonEpisode> get episodes => details.episodes;

  TmdbSeasonEpisode? episode(int episodeNumber) => details.episode(episodeNumber);
}

/// Decodes a stored document, throwing a [FormatException] with context on a corrupt row.
Map<String, dynamic> decodeSnapshot(String metadataJson) {
  final decoded = json.decode(metadataJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('A stored snapshot is not a JSON object');
  }
  return decoded;
}

/// The *Watch now* row for [region] out of an appended `watch/providers`: flatrate offers by
/// display priority with logo URLs built, plus the JustWatch link. Null when the document was
/// pruned to another region, or lists no offer in this one.
WatchProviderResult? providersFromAppend(TmdbWatchProvidersAppend? append, String? storedRegion, String region) {
  if (append == null || storedRegion != region) {
    return null;
  }
  final offers = append.forRegion(region);
  if (offers == null) {
    return null;
  }
  final providers = List<TmdbWatchProvider>.of(offers.flatrate)..sort((a, b) => a.displayPriority.compareTo(b.displayPriority));
  return WatchProviderResult(
    providers: [
      for (final provider in providers)
        provider.copyWith(logoPath: TmdbImageBuildUtil.buildUrl(provider.logoPath, imageSize: TmdbImageSizeUtil.logoSizeLow)),
    ],
    justWatchLink: offers.link,
  );
}

/// The image DTOs back as the maps [SnapshotPruner.bestImagePath] reads, so the choice rule lives
/// in one place. Only the two fields it looks at are needed.
List<Map<String, dynamic>>? _imagesJson(List<TmdbImage>? images) {
  if (images == null) {
    return null;
  }
  return [
    for (final image in images) {'file_path': image.filePath, 'iso_639_1': image.language, 'vote_average': image.voteAverage},
  ];
}
