import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/backup/backup_restore_repo.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/service/catalog/catalog_refresh_service.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/library/show_state_service.dart';

/// Restores a backup written by `BackupExportService`, replacing the device's history, ratings,
/// watchlist and favorites with the file's.
///
/// Accepts `schemaVersion` 3, 4 and 5 — the TMDB-keyed shapes. Version 3 has no favorites section,
/// so restoring one keeps the current favorites; 4 still calls the section `recommended`. The file is parsed in full before anything
/// is written, and the write is one transaction, so a bad file or a failed write leaves the device's
/// data exactly as it was.
///
/// Entries are keyed the way the user tables are: a movie or show by its own `tmdbId`, a season or
/// episode by `showTmdbId` + `season` (+ `episode`). The season's/episode's own TMDB and IMDb ids in
/// the file are informational and ignored.
class BackupImportService {
  static final _log = Logger('[Service] BackupImportService');

  static const supportedSchemaVersions = {3, 4, 5};

  /// Parses and validates [json]. Throws a [BackupFormatException] with a user-facing message.
  BackupContents parse(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException {
      throw const BackupFormatException('This file is not a Ticket Box backup.');
    }
    if (root is! Map<String, dynamic> || !root.containsKey('schemaVersion') || !root.containsKey('history')) {
      throw const BackupFormatException('This file is not a Ticket Box backup.');
    }

    final version = root['schemaVersion'];
    if (version is! int || !supportedSchemaVersions.contains(version)) {
      throw BackupFormatException('This backup (format $version) was made by a different version of Ticket Box and cannot be restored.');
    }

    try {
      final exportedAt = root['exportedAt'] == null ? null : _timestamp(root['exportedAt']);
      final history = _list(root, 'history').map(_history).toList();
      final ratings = <UserRatingEntity>[];
      for (final entry in _list(root, 'ratings')) {
        final rating = _rating(entry);
        // A season is never rated directly — its score is the average of its episode ratings.
        if (rating.type == ItemType.season) {
          _log.warning('Skipping season rating ${rating.tmdbId}x${rating.season} from the backup');
          continue;
        }
        ratings.add(rating);
      }
      final watchlist = _list(root, 'watchlist').map(_watchlist).toList();
      final favorites = switch (version) {
        3 => null,
        4 => _list(root, 'recommended').map((json) => _favorite(json, timestampKey: 'recommendedAt')).toList(),
        _ => _list(root, 'favorites').map((json) => _favorite(json, timestampKey: 'favoritedAt')).toList(),
      };

      return BackupContents(
        schemaVersion: version,
        exportedAt: exportedAt,
        history: history,
        ratings: ratings,
        watchlist: watchlist,
        favorites: favorites,
      );
    } on _MalformedEntry catch (e) {
      _log.warning('Rejected backup: ${e.detail}');
      throw const BackupFormatException('This backup file is damaged and cannot be restored.');
    }
  }

  /// Replaces the user data with [contents] and starts fetching the snapshots of the titles it
  /// named in the background (the app-bar refresh indicator follows it).
  ///
  /// A restore is not propagated to a connected TMDB account — it is not a per-item user action —
  /// and the pushes still queued refer to the data that was just replaced, so they are dropped.
  /// "Sync now → push" in Settings sends the restored lists over.
  Future<void> restore(BackupContents contents) async {
    _log.info(
      'Restoring backup: ${contents.history.length} play(s), ${contents.ratings.length} rating(s), '
      '${contents.watchlist.length} watchlist item(s), ${contents.favorites?.length ?? 'unchanged'} favorite(s)',
    );
    final now = DateTime.now().toUtc();
    await BackupRestoreRepo().replaceUserData(
      history: contents.history,
      ratings: contents.ratings,
      watchlist: contents.watchlist,
      favorites: contents.favorites,
      now: now,
    );
    await TmdbSyncOutboxRepo().deleteAll();
    // The states of every restored show, from the restored log; the titles the restore left
    // unreferenced go to the deletion sweep; the snapshots of the new stubs are fetched by the
    // catalogue refresh, whose outcome the app-bar indicator shows.
    await ShowStateService().recomputeAll(now: now);
    await LibraryService.instance().enqueueUnreferenced(now: now);
    unawaited(CatalogRefreshService.instance().tick());
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> root, String key) {
    final value = root[key];
    if (value is! List) {
      throw _MalformedEntry('"$key" is not a list');
    }
    return value.map((entry) => entry is Map<String, dynamic> ? entry : throw _MalformedEntry('"$key" holds a non-object entry')).toList();
  }

  NewHistoryEntry _history(Map<String, dynamic> json) {
    final key = _key(json);
    // A play is always of a movie or an episode: marking a show or season expands to its episodes.
    if (key.type != ItemType.movie && key.type != ItemType.episode) {
      throw _MalformedEntry('history ${key.type.name} entry');
    }
    return NewHistoryEntry(
      type: key.type,
      tmdbId: key.tmdbId,
      season: key.season,
      episode: key.episode,
      action: _enum(HistoryAction.values, json['historyType'], 'historyType'),
      watchedAt: _timestamp(json['addedAt']),
    );
  }

  UserRatingEntity _rating(Map<String, dynamic> json) {
    final key = _key(json);
    final rating = _int(json['rating'], 'rating');
    if (rating < 1 || rating > 10) {
      throw _MalformedEntry('rating $rating is out of range');
    }
    return UserRatingEntity.build(
      type: key.type,
      tmdbId: key.tmdbId,
      season: key.season,
      episode: key.episode,
      rating: rating,
      ratedAt: _timestamp(json['ratedAt']),
    );
  }

  WatchlistEntity _watchlist(Map<String, dynamic> json) {
    final key = _key(json);
    return WatchlistEntity.build(
      type: key.type,
      tmdbId: key.tmdbId,
      season: key.season,
      episode: key.episode,
      listedAt: _timestamp(json['listedAt']),
    );
  }

  FavoriteEntity _favorite(Map<String, dynamic> json, {required String timestampKey}) {
    final key = _key(json);
    if (key.type != ItemType.movie && key.type != ItemType.show) {
      throw _MalformedEntry('favorite ${key.type.name} entry');
    }
    return FavoriteEntity.build(type: key.type, tmdbId: key.tmdbId, favoritedAt: _timestamp(json[timestampKey]));
  }

  /// The user-table key of an entry: the inverse of the export's `_itemJson`.
  ({ItemType type, int tmdbId, int season, int episode}) _key(Map<String, dynamic> json) {
    final type = _enum(ItemType.values, json['type'], 'type');
    return switch (type) {
      ItemType.movie || ItemType.show => (type: type, tmdbId: _int(json['tmdbId'], 'tmdbId'), season: 0, episode: 0),
      ItemType.season => (type: type, tmdbId: _int(json['showTmdbId'], 'showTmdbId'), season: _int(json['season'], 'season'), episode: 0),
      ItemType.episode => (
        type: type,
        tmdbId: _int(json['showTmdbId'], 'showTmdbId'),
        season: _int(json['season'], 'season'),
        episode: _int(json['episode'], 'episode'),
      ),
    };
  }

  T _enum<T extends Enum>(List<T> values, Object? value, String key) {
    for (final candidate in values) {
      if (candidate.name == value) {
        return candidate;
      }
    }
    throw _MalformedEntry('unknown $key "$value"');
  }

  int _int(Object? value, String key) => value is int ? value : throw _MalformedEntry('"$key" is not an integer: $value');

  DateTime _timestamp(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw _MalformedEntry('bad timestamp "$value"');
    }
    return parsed.toUtc();
  }
}

/// A parsed, validated backup, ready for [BackupImportService.restore].
class BackupContents {
  final int schemaVersion;
  final DateTime? exportedAt;
  final List<NewHistoryEntry> history;
  final List<UserRatingEntity> ratings;
  final List<WatchlistEntity> watchlist;

  /// `null` for a version 3 backup, which predates the section: the current list is kept.
  final List<FavoriteEntity>? favorites;

  const BackupContents({
    required this.schemaVersion,
    required this.exportedAt,
    required this.history,
    required this.ratings,
    required this.watchlist,
    required this.favorites,
  });
}

/// A file that cannot be restored. [message] is meant for the user.
class BackupFormatException implements Exception {
  final String message;

  const BackupFormatException(this.message);

  @override
  String toString() => 'BackupFormatException: $message';
}

/// Internal: one entry failed validation. Surfaces as a [BackupFormatException].
class _MalformedEntry implements Exception {
  final String detail;

  _MalformedEntry(this.detail);
}
