import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/v3/watch_providers/model.dart';
import 'package:ticketbox/api/tmdb/v3/watch_providers/watch_provider_regions.dart';
import 'package:ticketbox/database/sql_store/cache/cache.dart';
import 'package:ticketbox/database/sql_store/cache/cache_repo.dart';
import 'package:ticketbox/service/cache_update_calculator.dart';

/// The countries TMDB reports watch-provider data for — the Settings page's country picker.
///
/// The *Watch now* rows themselves ride the stored snapshots now (`watch/providers` pruned to the
/// configured country); this is the one provider request left, cached for a month in the generic
/// caches table and degrading to the cached (possibly empty) list on error.
class WatchProviderRegionsService {
  static final _log = Logger('[Service] WatchProviderRegionsService');

  /// TMDB adds a country a few times a year at most.
  static const _regionsCacheExpireDays = 30;

  static const _regionsCacheKey = 'watch_provider_regions';
  static const _regionsKey = 'regions';

  final InternalCacheRepo _cacheRepo;

  WatchProviderRegionsService() : _cacheRepo = InternalCacheRepo();

  /// Every country TMDB reports watch-provider data for, alphabetical by English name.
  Future<List<TmdbAvailableProviderRegion>> getAvailableRegions([bool updateCache = true]) async {
    final CacheEntity? cached = await _cacheRepo.get(_regionsCacheKey);
    final cachedRegions = _decodeRegions(cached);

    if (cached != null && (!updateCache || !CacheNeedsUpdate.generalItem(cached.synchronizedAt, _regionsCacheExpireDays))) {
      return cachedRegions;
    }

    if (!updateCache) {
      return cachedRegions;
    }

    try {
      final regions = await TmdbWatchProviderRegionsApi().getAvailable()
        ..sort((a, b) => a.englishName.compareTo(b.englishName));
      await _cacheRepo.setJson(_regionsCacheKey, {_regionsKey: regions.map((e) => e.toJson()).toList()});
      return regions;
    } catch (e, stackTrace) {
      _log.warning('Error loading watch provider regions: $e', e, stackTrace);
      return cachedRegions;
    }
  }

  List<TmdbAvailableProviderRegion> _decodeRegions(CacheEntity? cached) {
    if (cached == null || cached.customData.isEmpty) {
      return const [];
    }

    try {
      final decoded = json.decode(cached.customData) as Map<String, dynamic>;
      final regions = decoded[_regionsKey];
      if (regions is! List) {
        return const [];
      }
      return regions.whereType<Map<String, dynamic>>().map(TmdbAvailableProviderRegion.fromJson).toList();
    } catch (e, stackTrace) {
      _log.warning('Could not decode cached watch provider regions: $e', e, stackTrace);
      return const [];
    }
  }
}
