import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ticketbox/api/http/image_download_client.dart';

/// The bounded cache for browsed, untracked images — Discover, search, the person page, cast
/// cards, watch-provider logos — behind every `CachedNetworkImage` in the app.
///
/// It lives under the temporary directory, where flutter_cache_manager keeps it by [cacheKey], and
/// the manager prunes it by age and count on its own. It is wholly separate from the library's
/// permanent artwork under the app support directory: this class never learns where that root is,
/// makes no directories and removes no files itself — eviction and [clear] are the manager's.
/// The download worker reads it ([lookup]) to promote an already-browsed image into the library
/// without a second download.
class ArtworkCache {
  static final _log = Logger('[Service] ArtworkCache');

  static const String cacheKey = 'tbBrowseImages';
  static const Duration stalePeriod = Duration(days: 14);
  static const int maxObjects = 600;

  static BaseCacheManager? _manager;

  static BaseCacheManager get manager => _manager ??= CacheManager(
    Config(
      cacheKey,
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: maxObjects,
      fileService: HttpFileService(httpClient: ImageDownloadClient.instance),
    ),
  );

  @visibleForTesting
  static void forTesting(BaseCacheManager manager) {
    _manager = manager;
  }

  @visibleForTesting
  static void resetForTesting() {
    _manager = null;
  }

  /// The cached file for [url], without downloading; null when it is not cached (or the cache
  /// cannot be read — a browse cache is never worth failing over).
  static Future<File?> lookup(String url) async {
    try {
      return (await manager.getFileFromCache(url))?.file;
    } catch (e, stackTrace) {
      _log.warning('Browse cache lookup failed for $url: $e', e, stackTrace);
      return null;
    }
  }

  static Future<void> clear() => manager.emptyCache();

  /// The bytes under the cache's own directory (`<temp>/tbBrowseImages`), for the Settings page.
  static Future<int> sizeBytes() async {
    final temporary = await getTemporaryDirectory();
    await for (final entry in temporary.list(followLinks: false)) {
      if (entry is! Directory || p.basename(entry.path) != cacheKey) {
        continue;
      }
      var total = 0;
      await for (final entity in entry.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    }
    return 0;
  }
}
