import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';

/// Builds a personal backup of everything the user has watched, rated, watchlisted and favorited,
/// as a single JSON file suitable for sharing off-device.
///
/// The file is `schemaVersion` [schemaVersion]. An external importer (sofalog) is built against this
/// exact shape, so any change to it - a renamed key, a moved field, a different timestamp format -
/// bumps the version rather than silently changing the payload. Version 3 dropped the ids of the former sync backend:
/// items are identified by TMDB ids only. Version 4 added the `favorites` section (movies and
/// shows only, each with a `favoritedAt`). The rules that hold the shape:
///
/// - every entry opens with `type` and `tmdbId`. For a movie or a show `tmdbId` is the item's own
///   id, which is also the row key of the user tables; for a season or an episode it is TMDB's id
///   for *that season / episode*, looked up in the cached catalogue and `null` when the catalogue
///   does not have it. An entry is never dropped for a missing lookup;
/// - `imdbId` follows on movie, show and episode entries (`null` when not cached). Seasons have no
///   IMDb id, so season entries carry no such key;
/// - the show-scoped keys `showTmdbId`, `season` and `episode` appear only on season- and
///   episode-typed entries, and `episode` only on episode-typed ones;
/// - every timestamp is UTC ISO-8601 with a `Z` suffix. Drift rehydrates its `dateTime` columns in
///   the local zone, so `toIso8601String()` alone would write wall-clock times with no offset.
///
/// The catalogue lookups are batched: one read per show for the seasons and one per
/// `(show, season)` for the episodes, a bounded number in flight at a time - never one query per
/// exported row.
class BackupExportService {
  static final _log = Logger('[Service] BackupExportService');

  /// Bumped on every change to the payload shape - see the class doc.
  static const schemaVersion = 5;

  /// How many catalogue reads run at once.
  static const _lookupChunkSize = 8;

  final _historyRepo = HistoryRepo();
  final _ratingRepo = UserRatingRepo();
  final _watchlistRepo = WatchlistRepo();
  final _favoriteRepo = FavoriteRepo();
  final _movieRepo = MovieRepo();
  final _showRepo = ShowRepo();
  final _seasonRepo = SeasonRepo();
  final _episodeRepo = EpisodeRepo();

  Future<File> buildBackupFile() async {
    final payload = await buildBackupPayload();

    final file = await _targetFile();
    await file.writeAsString(jsonEncode(payload));
    _log.fine(
      'Wrote backup with ${(payload['history'] as List).length} history item(s), ${(payload['ratings'] as List).length} rating(s) '
      '${(payload['watchlist'] as List).length} watchlist item(s) and ${(payload['favorites'] as List).length} favorite(s) '
      'to ${file.path}',
    );
    return file;
  }

  /// The whole export as a JSON-encodable map - everything but the file write, so it can be
  /// asserted on without a temporary directory.
  Future<Map<String, dynamic>> buildBackupPayload() async {
    final (history, ratings, watchlist, favorites) = await (
      _historyRepo.getAll(),
      _ratingRepo.getAll(),
      _watchlistRepo.getAll(),
      _favoriteRepo.getAll(),
    ).wait;
    final lookups = await _resolve(history: history, ratings: ratings, watchlist: watchlist, favorites: favorites);

    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'history': history.map((item) => _historyToJson(item, lookups)).toList(),
      'ratings': ratings.map((item) => _ratingToJson(item, lookups)).toList(),
      'watchlist': watchlist.map((item) => _watchlistToJson(item, lookups)).toList(),
      'favorites': favorites.map((item) => _favoriteToJson(item, lookups)).toList(),
    };
  }

  Future<_Lookups> _resolve({
    required List<HistoryEntity> history,
    required List<UserRatingEntity> ratings,
    required List<WatchlistEntity> watchlist,
    required List<FavoriteEntity> favorites,
  }) async {
    final movieIds = <int>{};
    final showIds = <int>{};
    // Shows whose cached seasons are needed, and the (show, season) pairs whose episodes are.
    final seasonShowIds = <int>{};
    final episodeSeasons = <(int, int)>{};

    void collect(_Row row) {
      switch (row.type) {
        case ItemType.movie:
          movieIds.add(row.tmdbId);
        case ItemType.show:
          showIds.add(row.tmdbId);
        case ItemType.season:
          seasonShowIds.add(row.tmdbId);
        case ItemType.episode:
          episodeSeasons.add((row.tmdbId, row.season));
      }
    }

    history.map(_historyRow).forEach(collect);
    ratings.map(_ratingRow).forEach(collect);
    watchlist.map(_watchlistRow).forEach(collect);
    favorites.map(_favoriteRow).forEach(collect);

    final (movies, shows) = await (_movieRepo.getMany(movieIds.toList()), _showRepo.getMany(showIds.toList())).wait;

    final seasons = <(int, int), int?>{};
    for (final chunk in seasonShowIds.toList().chunked(_lookupChunkSize)) {
      final results = await Future.wait(chunk.map(_seasonRepo.getAllForShow));
      for (final season in results.expand((rows) => rows)) {
        seasons[(season.showTmdbId, season.season)] = season.tmdbId;
      }
    }

    final episodes = <(int, int, int), ({int? tmdbId, String? imdbId})>{};
    for (final chunk in episodeSeasons.toList().chunked(_lookupChunkSize)) {
      final results = await Future.wait(chunk.map((key) => _episodeRepo.getAllForSeason(key.$1, key.$2)));
      for (final episode in results.expand((rows) => rows)) {
        episodes[(episode.showTmdbId, episode.season, episode.episode)] = (tmdbId: episode.tmdbId, imdbId: episode.imdbId);
      }
    }

    return _Lookups(
      movieImdbIds: {for (final entry in movies.entries) entry.key: entry.value.imdbId},
      showImdbIds: {for (final entry in shows.entries) entry.key: entry.value.imdbId},
      seasonTmdbIds: seasons,
      episodes: episodes,
    );
  }

  /// The keys every entry opens with, in the order the importer documents them: the item's own
  /// identity first, then - for season and episode entries only - the show it belongs to.
  Map<String, dynamic> _itemJson(_Row row, _Lookups lookups) {
    return switch (row.type) {
      ItemType.movie => {'type': row.type.name, 'tmdbId': row.tmdbId, 'imdbId': lookups.movieImdbIds[row.tmdbId]},
      ItemType.show => {'type': row.type.name, 'tmdbId': row.tmdbId, 'imdbId': lookups.showImdbIds[row.tmdbId]},
      ItemType.season => {
        'type': row.type.name,
        'tmdbId': lookups.seasonTmdbIds[(row.tmdbId, row.season)],
        'showTmdbId': row.tmdbId,
        'season': row.season,
      },
      ItemType.episode => {
        'type': row.type.name,
        'tmdbId': lookups.episodes[(row.tmdbId, row.season, row.episode)]?.tmdbId,
        'imdbId': lookups.episodes[(row.tmdbId, row.season, row.episode)]?.imdbId,
        'showTmdbId': row.tmdbId,
        'season': row.season,
        'episode': row.episode,
      },
    };
  }

  Map<String, dynamic> _historyToJson(HistoryEntity item, _Lookups lookups) {
    return _itemJson(_historyRow(item), lookups)
      ..['addedAt'] = _timestamp(item.watchedAt)
      ..['historyType'] = item.action.name;
  }

  Map<String, dynamic> _ratingToJson(UserRatingEntity item, _Lookups lookups) {
    return _itemJson(_ratingRow(item), lookups)
      ..['rating'] = item.rating
      ..['ratedAt'] = _timestamp(item.ratedAt);
  }

  Map<String, dynamic> _watchlistToJson(WatchlistEntity item, _Lookups lookups) {
    return _itemJson(_watchlistRow(item), lookups)..['listedAt'] = _timestamp(item.listedAt);
  }

  Map<String, dynamic> _favoriteToJson(FavoriteEntity item, _Lookups lookups) {
    return _itemJson(_favoriteRow(item), lookups)..['favoritedAt'] = _timestamp(item.favoritedAt);
  }

  /// UTC with a `Z` suffix, always - see the class doc.
  String _timestamp(DateTime instant) => instant.toUtc().toIso8601String();

  _Row _historyRow(HistoryEntity item) => (type: item.type, tmdbId: item.tmdbId, season: item.season, episode: item.episode);

  _Row _ratingRow(UserRatingEntity item) => (type: item.type, tmdbId: item.tmdbId, season: item.season, episode: item.episode);

  _Row _watchlistRow(WatchlistEntity item) => (type: item.type, tmdbId: item.tmdbId, season: item.season, episode: item.episode);

  _Row _favoriteRow(FavoriteEntity item) => (type: item.type, tmdbId: item.tmdbId, season: 0, episode: 0);

  Future<File> _targetFile() async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return File('${dir.path}/ticket_box_backup_$timestamp.json');
  }
}

/// The identity columns the per-user tables share, so one set of mappers serves all of them.
/// `tmdbId` is the movie's own id, or the show's for show, season and episode rows.
typedef _Row = ({ItemType type, int tmdbId, int season, int episode});

/// What the catalogue tables contribute to the export, resolved once for the whole file instead of
/// once per row: IMDb ids by movie/show TMDB id, season TMDB ids by `(showTmdbId, season)` and the
/// episode ids by `(showTmdbId, season, episode)`.
class _Lookups {
  final Map<int, String?> movieImdbIds;
  final Map<int, String?> showImdbIds;
  final Map<(int, int), int?> seasonTmdbIds;
  final Map<(int, int, int), ({int? tmdbId, String? imdbId})> episodes;

  _Lookups({required this.movieImdbIds, required this.showImdbIds, required this.seasonTmdbIds, required this.episodes});
}
