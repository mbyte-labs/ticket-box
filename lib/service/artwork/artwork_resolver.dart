import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/service/artwork/artwork_index.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/artwork/artwork_sizes.dart';

/// Where a widget gets its image from.
sealed class ArtworkSource {
  const ArtworkSource();
}

/// The library's own file.
class LocalFile extends ArtworkSource {
  final File file;

  const LocalFile(this.file);

  @override
  String toString() => 'LocalFile(${file.path})';
}

/// Not on disk: fetch through the browse cache.
class Network extends ArtworkSource {
  final String url;

  const Network(this.url);

  @override
  String toString() => 'Network($url)';
}

/// Nothing to show — no path, an unsafe one, or one TMDB has no file for.
class None extends ArtworkSource {
  const None();

  @override
  String toString() => 'None';
}

/// Turns an [ArtworkRef] into an [ArtworkSource], synchronously, from the in-memory index: the
/// library's file when it is there (a season poster falls back to the show's), the TMDB URL at the
/// current quality otherwise, nothing when TMDB has no such file.
class ArtworkResolver {
  static final _log = Logger('[Service] ArtworkResolver');

  final ArtworkPaths? _paths;
  final ArtworkIndex _index;
  PosterQualityOption _quality;

  ArtworkResolver({ArtworkPaths? paths, required ArtworkIndex index, PosterQualityOption quality = PosterQualityOption.medium})
    : _paths = paths,
      _index = index,
      _quality = quality;

  /// The process-wide resolver over the registered paths (none when the artwork root could not
  /// be resolved — every ref then resolves to the network) and index.
  static ArtworkResolver instance() {
    if (GetIt.I.isRegistered<ArtworkResolver>()) {
      return GetIt.I.get<ArtworkResolver>();
    }
    _log.info('New instance created');
    final resolver = ArtworkResolver(
      paths: GetIt.I.isRegistered<ArtworkPaths>() ? GetIt.I.get<ArtworkPaths>() : null,
      index: ArtworkIndex.instance(),
    );
    GetIt.I.registerSingleton<ArtworkResolver>(resolver);
    return resolver;
  }

  PosterQualityOption get quality => _quality;

  /// The quality the network URLs are built at; the artwork settings page calls this on a change.
  void setQuality(PosterQualityOption quality) {
    _quality = quality;
  }

  /// The files that may stand in for [ref], best first (empty without a root).
  List<String> candidatePaths(ArtworkRef? ref) {
    final paths = _paths;
    if (ref == null || paths == null) {
      return const [];
    }
    return paths.candidatePaths(ref);
  }

  /// [skipLocal] goes straight to the network — for a widget whose local file failed to decode.
  ArtworkSource resolve(ArtworkRef? ref, {bool skipLocal = false}) {
    if (ref == null) {
      return const None();
    }
    final paths = _paths;
    final candidates = candidatePaths(ref);
    if (!skipLocal && paths != null) {
      for (final relativePath in candidates) {
        if (_index.contains(relativePath)) {
          return LocalFile(File(paths.absolutePath(relativePath)));
        }
      }
    }
    final url = ArtworkSizes.url(ref, _quality);
    if (url == null || (candidates.isNotEmpty && _index.isMissing(candidates.first))) {
      return const None();
    }
    return Network(url);
  }
}
