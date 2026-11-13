import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:ticketbox/api/omdb/item_details.api.dart';
import 'package:ticketbox/api/omdb/item_details.dart';
import 'package:ticketbox/database/sql_store/cache/cache.dart';
import 'package:ticketbox/database/sql_store/cache/cache_repo.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/service/cache_update_calculator.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/external_rating/imdb_rating.dart';
import 'package:ticketbox/service/external_rating/omdb_value_parser.dart';

/// IMDb community rating of one title via OMDb — the IMDb half of a details page's Ratings
/// card. The TMDB half (vote_average / vote_count) comes from the stored TMDB snapshot, and the
/// bloc joins the two with [ExternalRatings.combine]. Never throws.
///
/// Results live in the generic [InternalCacheRepo] key/value table rather than in a table of
/// their own, for the same reason [WatchProviderService] documents: a dedicated Drift table
/// would mean bumping `schemaVersion`, and that migration is destructive. A ratings row is not
/// worth a fresh-install-grade reset. The keys predate the OMDb-only shape, so a row written by
/// an older build still holds the combined TMDB + IMDb JSON; [_decode] reads its IMDb half.
class ExternalRatingService {
  static final _log = Logger('[Service] ExternalRatingService');

  /// Longer than the 3–6 day item TTLs on purpose: aggregate ratings on established titles
  /// barely move, and OMDb's free key (~1000 requests/day, shared by every install) makes
  /// re-spending an episode-browsing session's worth of calls every few days too expensive.
  static const _ratingsCacheExpireDays = 14;

  final InternalCacheRepo _cacheRepo;
  final OmdbDetailsApi _api;
  final EpisodeRepo _episodeRepo;

  ExternalRatingService({InternalCacheRepo? cacheRepo, OmdbDetailsApi? api, EpisodeRepo? episodeRepo})
    : _cacheRepo = cacheRepo ?? InternalCacheRepo(),
      _api = api ?? OmdbDetailsApi(),
      _episodeRepo = episodeRepo ?? EpisodeRepo();

  /// `null` means "never fetched" (nothing cached and the network was unavailable or skipped);
  /// an [ImdbRating] with null fields is a real answer — IMDb has nothing, or the title has no
  /// IMDb id — and is cached like any other so the page doesn't re-request it on every open.
  Future<ImdbRating?> getForMovie(int tmdbId, String? imdbId, [bool updateCache = true]) {
    return _get('external_ratings_movie_$tmdbId', () => _lookup(imdbId), updateCache);
  }

  /// The show counterpart of [getForMovie], same semantics. The key prefix differs because
  /// TMDB movie and show ids are separate namespaces sharing one cache table.
  Future<ImdbRating?> getForShow(int tmdbId, String? imdbId, [bool updateCache = true]) {
    return _get('external_ratings_show_$tmdbId', () => _lookup(imdbId), updateCache);
  }

  /// TMDB does not carry episode IMDb ids, so an episode is looked up through its show —
  /// OMDb's `?i=<showImdbId>&Season=s&Episode=e`. The answer names the episode's own id, which
  /// is written to `episodes.imdb_id` (the backup export reads it). [episodeImdbId], when already
  /// known, short-circuits to a plain lookup.
  Future<ImdbRating?> getForEpisode(
    int showTmdbId,
    int season,
    int episode, {
    required String? showImdbId,
    String? episodeImdbId,
    bool updateCache = true,
  }) {
    return _get('external_ratings_episode_${showTmdbId}_${season}_$episode', () async {
      if (episodeImdbId != null && episodeImdbId.isNotEmpty) {
        return _lookup(episodeImdbId);
      }
      if (showImdbId == null || showImdbId.isEmpty) {
        return ImdbRating.empty;
      }

      final rating = _fromItem(await _api.getEpisode(showImdbId, season, episode));
      final learnedId = rating.imdbId;
      if (learnedId != null) {
        await _rememberEpisodeImdbId(showTmdbId, season, episode, learnedId);
      }
      return rating;
    }, updateCache);
  }

  /// A plain id lookup. No id is a real "IMDb has nothing" answer, not a failure — cached.
  Future<ImdbRating> _lookup(String? imdbId) async {
    if (imdbId == null || imdbId.isEmpty) {
      return ImdbRating.empty;
    }
    return _fromItem(await _api.get(imdbId));
  }

  /// A null [item] is OMDb's "no such id" answer.
  ImdbRating _fromItem(OmdbItemModel? item) {
    if (item == null) {
      return ImdbRating.empty;
    }
    return ImdbRating(
      rating: OmdbValueParser.parseRating(item.imdbRating),
      votes: OmdbValueParser.parseVotes(item.imdbVotes),
      imdbId: item.imdbId,
    );
  }

  /// A failed write must not cost the rating that was just fetched; the id is learned again on
  /// the next refresh.
  Future<void> _rememberEpisodeImdbId(int showTmdbId, int season, int episode, String imdbId) async {
    try {
      await _episodeRepo.updateImdbId(showTmdbId, season, episode, imdbId);
    } catch (e, stackTrace) {
      _log.warning('Could not store the IMDb id of episode ${season}x$episode of show $showTmdbId: $e', e, stackTrace);
    }
  }

  Future<ImdbRating?> _get(String key, Future<ImdbRating> Function() fetch, bool updateCache) async {
    final CacheEntity? cached = await _cacheRepo.get(key);
    final cachedRating = _decode(key, cached);

    if (!updateCache) {
      return cachedRating;
    }
    // An undecodable row counts as missing here so an updating pass replaces it.
    if (cached != null && cachedRating != null && !CacheNeedsUpdate.generalItem(cached.synchronizedAt, _ratingsCacheExpireDays)) {
      return cachedRating;
    }

    final ImdbRating fresh;
    try {
      fresh = await fetch();
    } catch (e, stackTrace) {
      // Fall back without rewriting the row so synchronizedAt stays put and the next updating
      // pass retries.
      _log.warning('Error loading the IMDb rating for $key, keeping the cached value: $e', e, stackTrace);
      return cachedRating;
    }

    try {
      await _cacheRepo.setJson(key, fresh.toJson());
    } catch (e, stackTrace) {
      _log.warning('Could not cache the IMDb rating for $key: $e', e, stackTrace);
    }
    return fresh;
  }

  /// `null` when nothing is cached for the key — callers use that to tell "never fetched"
  /// apart from a cached all-null answer. A row in the pre-OMDb-only layout (the combined
  /// [ExternalRatings] JSON) still decodes: its IMDb half, with no id.
  ImdbRating? _decode(String key, CacheEntity? cached) {
    if (cached == null || cached.customData.isEmpty) {
      return null;
    }

    try {
      final map = json.decode(cached.customData) as Map<String, dynamic>;
      if (map.containsKey('rating')) {
        return ImdbRating.fromJson(map);
      }
      final combined = ExternalRatings.fromJson(map);
      return ImdbRating(rating: combined.imdbRating, votes: combined.imdbVotes, imdbId: null);
    } catch (e, stackTrace) {
      _log.warning('Could not decode the cached IMDb rating under $key: $e', e, stackTrace);
      return null;
    }
  }
}
