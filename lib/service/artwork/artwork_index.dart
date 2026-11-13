import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';

/// A file that just landed under the artwork root. [replaced] says an older file was overwritten,
/// so a widget already showing it has to drop its decoded copy.
class ArtworkArrival {
  final String relativePath;
  final bool replaced;

  const ArtworkArrival(this.relativePath, {required this.replaced});

  @override
  String toString() => 'ArtworkArrival($relativePath${replaced ? ', replaced' : ''})';
}

/// The in-memory set of artwork files present on disk, so a tile resolves its image synchronously
/// without a stat per build.
///
/// Loaded once at start-up by walking the root ([load]); kept current by the store (every write
/// and delete goes through it) and shared with the widgets through [arrivals]. A path TMDB
/// answered 404 for is remembered as missing so the tiles stop asking the network for it.
class ArtworkIndex {
  static final _log = Logger('[Service] ArtworkIndex');

  final Set<String> _present = {};
  final Set<String> _missing = {};
  final StreamController<ArtworkArrival> _arrivals = StreamController<ArtworkArrival>.broadcast();
  bool _loaded = false;

  ArtworkIndex();

  static ArtworkIndex instance() {
    if (GetIt.I.isRegistered<ArtworkIndex>()) {
      return GetIt.I.get<ArtworkIndex>();
    }
    _log.info('New instance created');
    final index = ArtworkIndex();
    GetIt.I.registerSingleton<ArtworkIndex>(index);
    return index;
  }

  /// Whether the start-up walk has finished. Until then a file may exist that [contains] denies.
  bool get loaded => _loaded;

  /// Every file that lands, as it lands.
  Stream<ArtworkArrival> get arrivals => _arrivals.stream;

  @visibleForTesting
  int get size => _present.length;

  /// Walks the root once and records every regular file (a `.part` is a download in progress,
  /// not artwork). Never throws: an unreadable root is an empty index.
  Future<void> load(ArtworkPaths paths) async {
    try {
      final root = Directory(paths.assetsRoot);
      if (await root.exists()) {
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          if (entity is File && !entity.path.endsWith('.part')) {
            _present.add(paths.toRelative(entity.path));
          }
        }
      }
      _log.info('Artwork index loaded: ${_present.length} file(s)');
    } catch (e, stackTrace) {
      _log.warning('Could not walk the artwork directory ${paths.assetsRoot}: $e', e, stackTrace);
    } finally {
      _loaded = true;
    }
  }

  bool contains(String relativePath) => _present.contains(relativePath);

  /// Records [relativePath] as present and tells the widgets.
  void add(String relativePath, {bool replaced = false}) {
    _present.add(relativePath);
    _missing.remove(relativePath);
    _arrivals.add(ArtworkArrival(relativePath, replaced: replaced));
  }

  void remove(String relativePath) {
    _present.remove(relativePath);
  }

  /// Forgets every file under [directory] (a relative directory path, with or without the slash).
  void removeWithPrefix(String directory) {
    final prefix = directory.endsWith('/') ? directory : '$directory/';
    _present.removeWhere((path) => path.startsWith(prefix));
    _missing.removeWhere((path) => path.startsWith(prefix));
  }

  /// TMDB has no file for this path; stop asking the network for it.
  void markMissing(String relativePath) {
    _missing.add(relativePath);
  }

  bool isMissing(String relativePath) => _missing.contains(relativePath);
}
