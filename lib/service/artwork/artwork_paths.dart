import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_kind.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';

/// Where the library's artwork lives on disk and how one [ArtworkRef] maps to a file there.
///
/// Every path handed around (the queue's `dest_path`, the index, the arrivals) is *relative* to
/// [assetsRoot] and `/`-separated, so a reinstall that lands the app in another directory still
/// matches its rows to its files. The layout:
///
///     video/movies/<id>/poster.jpg
///     video/movies/<id>/backdrop.jpg
///     video/movies/<id>/cast/<profile basename>
///     video/shows/<id>/poster.jpg
///     video/shows/<id>/backdrop.jpg
///     video/shows/<id>/seasons/<n>/poster.jpg
///     video/shows/<id>/episodes/<s>-<e>/still.jpg
///     video/shows/<id>/cast/<profile basename>
///
/// Numbers are positional and unpadded; the file names are fixed per kind whatever extension TMDB
/// serves (a `.png` poster is still stored as `poster.jpg` — decoders sniff the bytes). Cast
/// headshots keep TMDB's basename because several people share the one directory.
class ArtworkPaths {
  final String assetsRoot;

  const ArtworkPaths(this.assetsRoot);

  /// `<app support dir>/assets` — the permanent, app-private directory (Android `files/`).
  static Future<ArtworkPaths> resolve() async => ArtworkPaths(p.join((await getApplicationSupportDirectory()).path, 'assets'));

  static final RegExp _safeTmdbPath = RegExp(r'^/[A-Za-z0-9_-]{1,120}\.(jpe?g|png|webp)$', caseSensitive: false);

  /// Whether [path] is a TMDB image path the app will put in a URL or a file name: one segment of
  /// plain characters with an image extension. Rejects null, traversal and anything exotic.
  static bool isSafeTmdbPath(String? path) => path != null && _safeTmdbPath.hasMatch(path);

  /// `video/movies/<id>` or `video/shows/<id>` — a season's or episode's key resolves to its show.
  String itemDirectory(MediaKey item) {
    final owner = item.showKey;
    return owner.type == ItemType.movie ? 'video/movies/${owner.tmdbId}' : 'video/shows/${owner.tmdbId}';
  }

  /// The file [ref] is stored at, relative to [assetsRoot]. A cast ref needs a safe profile path
  /// (the basename is the file name) and throws an [ArgumentError] otherwise.
  String relativePath(ArtworkRef ref) {
    final directory = itemDirectory(ref.item);
    switch (ref.kind) {
      case ArtworkKind.poster:
        return '$directory/poster.jpg';
      case ArtworkKind.backdrop:
        return '$directory/backdrop.jpg';
      case ArtworkKind.seasonPoster:
        return '$directory/seasons/${ref.season}/poster.jpg';
      case ArtworkKind.still:
        return '$directory/episodes/${ref.season}-${ref.episode}/still.jpg';
      case ArtworkKind.cast:
        final path = ref.tmdbPath;
        if (!isSafeTmdbPath(path)) {
          throw ArgumentError.value(path, 'tmdbPath', 'a cast headshot needs a safe TMDB profile path');
        }
        return '$directory/cast/${path!.substring(1)}';
    }
  }

  String absolutePath(String relative) => p.join(assetsRoot, relative);

  /// [absolute], a file under [assetsRoot], as the `/`-separated relative path everything is keyed by.
  String toRelative(String absolute) => p.posix.joinAll(p.split(p.relative(absolute, from: assetsRoot)));

  /// The files that may stand in for [ref], best first: a season poster falls back to the show's;
  /// everything else has only its own file. A cast ref without a safe path has no candidates.
  List<String> candidatePaths(ArtworkRef ref) => switch (ref.kind) {
    ArtworkKind.seasonPoster => [relativePath(ref), relativePath(ArtworkRef.poster(ref.item, null))],
    ArtworkKind.cast => isSafeTmdbPath(ref.tmdbPath) ? [relativePath(ref)] : const [],
    ArtworkKind.poster || ArtworkKind.backdrop || ArtworkKind.still => [relativePath(ref)],
  };
}
