import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/v3/discover/discover_api.dart';
import 'package:ticketbox/api/tmdb/v3/discover/discover_params.dart';
import 'package:ticketbox/api/tmdb/v3/discover/trending_api.dart';
import 'package:ticketbox/common/model/discover_mode.dart';
import 'package:ticketbox/common/model/filter/genres/genres.dart';
import 'package:ticketbox/common/model/filter/rating/rating_range.dart';
import 'package:ticketbox/common/model/filter/year/year_range.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/cache/cache.dart';
import 'package:ticketbox/database/sql_store/cache/cache_repo.dart';
import 'package:ticketbox/service/browse/browse_entry.dart';
import 'package:ticketbox/service/cache_update_calculator.dart';
import 'package:ticketbox/service/discover/discover_params_mapper.dart';

/// TMDB's discover lists for movies and shows - what the Discover page's grid pages through.
///
/// [DiscoverMode.popular] is `/discover/{movie|tv}` sorted by popularity and [DiscoverMode.topRated]
/// the same endpoint sorted by vote average with a minimum vote count; `/discover` is also the only
/// endpoint that accepts the genre, year and rating filters. [DiscoverMode.trending] is
/// `/trending/{movie|tv}/week`, which **has no filters**: as soon as any filter is active the
/// trending grid falls back to the filtered discover list, so the filters keep working at the cost
/// of the "trending" flavour.
///
/// Live on every view and never written to the catalogue — browsing writes nothing. Only the
/// first page of each list is cached, as [BrowseEntry] rows in the generic caches table: it is
/// what paints the page on entry (and keeps it usable offline), while the deeper pages are only
/// ever reached by scrolling, which implies a working connection anyway. Pages are TMDB's fixed
/// 20 rows.
class DiscoverService {
  static final _log = Logger('[Service] DiscoverService');

  /// TMDB's own default for its top rated lists.
  static const defaultMinVoteCount = 300;

  /// Popular and trending shift daily.
  static const _cacheExpireDays = 1;

  static const _itemsKey = 'items';
  static const _totalPagesKey = 'totalPages';

  final InternalCacheRepo _cacheRepo;

  DiscoverService() : _cacheRepo = InternalCacheRepo();

  /// One 1-based [page] of the [mode] list of [type] (movies or shows only), in TMDB's order, plus
  /// the total page count the response reported.
  ///
  /// Page one answers from the cache while it is fresh, and falls back to the stale cache when
  /// the fetch fails - a day-old grid beats an error page. The error propagates only when there
  /// is nothing cached to show instead, and always for the deeper, network-only pages.
  ///
  /// A page with any active filter skips the cache entirely: the cache key is per type and mode
  /// only, and keying it per filter combination would leak a row for every combination ever
  /// applied, since [InternalCacheRepo] never evicts. A top rated list with a vote floor other
  /// than [defaultMinVoteCount] counts as filtered for the same reason.
  Future<DiscoverPage> getPage(
    ItemType type,
    DiscoverMode mode,
    int page, {
    FilterRatingRange? ratingRange,
    FilterYearRange? yearRange,
    FilterGenres? genres,
    int minVoteCount = defaultMinVoteCount,
  }) async {
    final params = DiscoverParamsMapper.toParams(
      mode: mode,
      minVoteCount: minVoteCount,
      ratingRange: ratingRange,
      yearRange: yearRange,
      genres: genres,
    );

    final cacheable = page == 1 && params.isEmpty && (mode != DiscoverMode.topRated || minVoteCount == defaultMinVoteCount);
    if (!cacheable) {
      return _fetch(type, mode, page, params);
    }

    final key = _cacheKey(type, mode);
    final cached = await _cacheRepo.get(key);
    final cachedPage = _decode(cached);
    if (cached != null && cachedPage != null && !CacheNeedsUpdate.generalItem(cached.synchronizedAt, _cacheExpireDays, 0)) {
      return cachedPage;
    }

    try {
      final fresh = await _fetch(type, mode, page, params);
      await _cacheRepo.setJson(key, {_itemsKey: fresh.items.map((e) => e.toJson()).toList(), _totalPagesKey: fresh.totalPages});
      return fresh;
    } catch (e, stackTrace) {
      if (cachedPage != null && cachedPage.items.isNotEmpty) {
        _log.warning('Error refreshing $key, falling back to the stale cache: $e', e, stackTrace);
        return cachedPage;
      }
      rethrow;
    }
  }

  Future<DiscoverPage> _fetch(ItemType type, DiscoverMode mode, int page, TmdbDiscoverParams params) async {
    // Trending accepts no filters, so a filtered trending request becomes a discover one.
    final useTrending = mode == DiscoverMode.trending && params.isEmpty;

    switch (type) {
      case ItemType.movie:
        final response = useTrending ? await TmdbTrendingApi().movies(page) : await TmdbDiscoverApi().movies(page, params);
        return DiscoverPage(response.totalPages, response.results.map(BrowseEntry.movie).toList());
      case ItemType.show:
        final response = useTrending ? await TmdbTrendingApi().shows(page) : await TmdbDiscoverApi().shows(page, params);
        return DiscoverPage(response.totalPages, response.results.map(BrowseEntry.show).toList());
      case ItemType.season:
      case ItemType.episode:
        throw ArgumentError.value(type, 'type', 'Discover lists exist for movies and shows only');
    }
  }

  /// A cache row that cannot be decoded (including one in the pre-v10 ids-only layout) is treated
  /// as absent instead of breaking the page.
  DiscoverPage? _decode(CacheEntity? cached) {
    if (cached == null || cached.customData.isEmpty) {
      return null;
    }

    try {
      final decoded = json.decode(cached.customData) as Map<String, dynamic>;
      final items = decoded[_itemsKey];
      final totalPages = decoded[_totalPagesKey];
      if (items is! List || totalPages is! int) {
        return null;
      }
      return DiscoverPage(totalPages, items.whereType<Map<String, dynamic>>().map(BrowseEntry.fromJson).toList());
    } catch (e, stackTrace) {
      _log.warning('Could not decode a cached discover page: $e', e, stackTrace);
      return null;
    }
  }

  /// Keeps the spelling the two former per-type services used, so their rows stay valid.
  String _cacheKey(ItemType type, DiscoverMode mode) => 'discover_${type == ItemType.movie ? 'movies' : 'shows'}_${mode.name}';
}

class DiscoverPage {
  final int totalPages;
  final List<BrowseEntry> items;

  const DiscoverPage(this.totalPages, this.items);
}
