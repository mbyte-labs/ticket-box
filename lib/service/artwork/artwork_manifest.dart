import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/artwork/artwork_sizes.dart';

/// The artwork one whole movie or show wants on disk: the poster and backdrop, every season's
/// poster, every episode's still and the cast's headshots, as TMDB paths.
///
/// It is always the whole item — there is no per-season manifest — so a reconcile can compare it
/// against the item's directory and delete what is no longer named (a season TMDB removed, a
/// still that changed). Null and unsafe paths are simply not wanted.
class ArtworkManifest {
  final MediaKey item;
  final String? posterPath;
  final String? backdropPath;

  /// Season number → poster path.
  final Map<int, String?> seasonPosterPaths;

  /// `(season, episode)` → still path.
  final Map<(int, int), String?> stillPaths;

  /// TMDB profile paths of the cast to keep.
  final Set<String> castProfilePaths;

  const ArtworkManifest._({
    required this.item,
    this.posterPath,
    this.backdropPath,
    this.seasonPosterPaths = const {},
    this.stillPaths = const {},
    this.castProfilePaths = const {},
  });

  factory ArtworkManifest.movie({required int tmdbId, String? posterPath, String? backdropPath, Set<String> castProfilePaths = const {}}) =>
      ArtworkManifest._(
        item: MediaKey.movie(tmdbId),
        posterPath: posterPath,
        backdropPath: backdropPath,
        castProfilePaths: castProfilePaths,
      );

  factory ArtworkManifest.show({
    required int tmdbId,
    String? posterPath,
    String? backdropPath,
    Map<int, String?> seasonPosterPaths = const {},
    Map<(int, int), String?> stillPaths = const {},
    Set<String> castProfilePaths = const {},
  }) => ArtworkManifest._(
    item: MediaKey.show(tmdbId),
    posterPath: posterPath,
    backdropPath: backdropPath,
    seasonPosterPaths: seasonPosterPaths,
    stillPaths: stillPaths,
    castProfilePaths: castProfilePaths,
  );

  /// Every wanted file in download priority: poster, backdrop, season posters (by number), stills
  /// (by season and episode), cast. The queue inserts in this order, so ids follow priority.
  List<ArtworkRef> refs() {
    final refs = primaryRefs();
    final seasons = seasonPosterPaths.keys.toList()..sort();
    for (final season in seasons) {
      final path = seasonPosterPaths[season];
      if (ArtworkPaths.isSafeTmdbPath(path)) {
        refs.add(ArtworkRef.seasonPoster(item.tmdbId, season, path));
      }
    }
    final episodes = stillPaths.keys.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    for (final (season, episode) in episodes) {
      final path = stillPaths[(season, episode)];
      if (ArtworkPaths.isSafeTmdbPath(path)) {
        refs.add(ArtworkRef.still(item.tmdbId, season, episode, path));
      }
    }
    for (final profile in castProfilePaths) {
      if (ArtworkPaths.isSafeTmdbPath(profile)) {
        refs.add(ArtworkRef.cast(item, profile));
      }
    }
    return refs;
  }

  /// The poster and the backdrop — what a tile and a details page need first.
  List<ArtworkRef> primaryRefs() => [
    if (ArtworkPaths.isSafeTmdbPath(posterPath)) ArtworkRef.poster(item, posterPath),
    if (ArtworkPaths.isSafeTmdbPath(backdropPath)) ArtworkRef.backdrop(item, backdropPath),
  ];

  /// The relative paths of every wanted file — what a reconcile keeps.
  Set<String> desiredRelativePaths(ArtworkPaths paths) => refs().map(paths.relativePath).toSet();

  List<NewAssetJob> toJobs(ArtworkPaths paths, PosterQualityOption quality) => _jobs(refs(), paths, quality);

  List<NewAssetJob> primaryJobs(ArtworkPaths paths, PosterQualityOption quality) => _jobs(primaryRefs(), paths, quality);

  static List<NewAssetJob> _jobs(List<ArtworkRef> refs, ArtworkPaths paths, PosterQualityOption quality) {
    final jobs = <String, NewAssetJob>{};
    for (final ref in refs) {
      final url = ArtworkSizes.url(ref, quality);
      if (url == null) {
        continue;
      }
      final destPath = paths.relativePath(ref);
      jobs.putIfAbsent(
        destPath,
        () => NewAssetJob(
          mediaType: ref.item.type,
          itemId: ref.item.tmdbId,
          kind: ref.kind.name,
          size: ArtworkSizes.sizeFor(ref.kind, quality),
          sourceUrl: url,
          destPath: destPath,
        ),
      );
    }
    return jobs.values.toList();
  }

  @override
  String toString() =>
      'ArtworkManifest($item, poster: $posterPath, backdrop: $backdropPath, ${seasonPosterPaths.length} season(s), '
      '${stillPaths.length} still(s), ${castProfilePaths.length} cast)';
}
