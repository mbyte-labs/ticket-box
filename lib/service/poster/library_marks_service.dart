import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/library/rating_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';

/// Everything the grids mark their tiles with, read once per page load as whole-table sets —
/// bounded by what the user has done, never a query per tile.
class LibraryMarkSets {
  final Set<int> watchedMovieIds;
  final Set<int> startedShowIds;
  final Set<int> finishedShowIds;
  final Set<int> droppedShowIds;
  final Set<MediaKey> watchlistKeys;
  final Map<MediaKey, int> ratings;
  final Set<MediaKey> favoriteKeys;
  final Set<MediaKey> trackedKeys;

  /// Per show, the `(season, episode)` positions with a play — filled by [LibraryMarksService.load]
  /// only for the shows the caller named.
  final Map<int, Set<(int, int)>> watchedPositions;

  const LibraryMarkSets({
    required this.watchedMovieIds,
    required this.startedShowIds,
    required this.finishedShowIds,
    required this.droppedShowIds,
    required this.watchlistKeys,
    required this.ratings,
    required this.favoriteKeys,
    required this.trackedKeys,
    required this.watchedPositions,
  });

  static const LibraryMarkSets empty = LibraryMarkSets(
    watchedMovieIds: {},
    startedShowIds: {},
    finishedShowIds: {},
    droppedShowIds: {},
    watchlistKeys: {},
    ratings: {},
    favoriteKeys: {},
    trackedKeys: {},
    watchedPositions: {},
  );

  bool isTracked(MediaKey key) => trackedKeys.contains(key.showKey);
}

/// Reads the user tables into [LibraryMarkSets] and stamps [PosterModel]s with them.
class LibraryMarksService {
  final HistoryRepo _historyRepo;
  final ShowStateRepo _stateRepo;
  final WatchlistRepo _watchlistRepo;
  final UserRatingRepo _ratingRepo;
  final FavoriteRepo _favoriteRepo;
  final MovieRepo _movieRepo;
  final ShowRepo _showRepo;

  LibraryMarksService({
    HistoryRepo? historyRepo,
    ShowStateRepo? stateRepo,
    WatchlistRepo? watchlistRepo,
    UserRatingRepo? ratingRepo,
    FavoriteRepo? favoriteRepo,
    MovieRepo? movieRepo,
    ShowRepo? showRepo,
  }) : _historyRepo = historyRepo ?? HistoryRepo(),
       _stateRepo = stateRepo ?? ShowStateRepo(),
       _watchlistRepo = watchlistRepo ?? WatchlistRepo(),
       _ratingRepo = ratingRepo ?? UserRatingRepo(),
       _favoriteRepo = favoriteRepo ?? FavoriteRepo(),
       _movieRepo = movieRepo ?? MovieRepo(),
       _showRepo = showRepo ?? ShowRepo();

  /// The sets; [showIdsForPositions] names the shows whose per-episode plays are needed too
  /// (season and episode tiles).
  Future<LibraryMarkSets> load({Iterable<int> showIdsForPositions = const []}) async {
    final (watchedMovies, startedShows, finishedShows, droppedShows, watchlist) = await (
      _historyRepo.getWatchedMovieIds(),
      _historyRepo.getWatchedShowIds(),
      _stateRepo.getFinishedIds(),
      _stateRepo.getDroppedIds(),
      _watchlistRepo.getAll(),
    ).wait;
    final (ratings, favorites, movieIds, showIds, positions) = await (
      _ratingRepo.getAll(),
      _favoriteRepo.getAll(),
      _movieRepo.getAllIds(),
      _showRepo.getAllIds(),
      _historyRepo.getWatchedPositionsForShows(showIdsForPositions),
    ).wait;
    return LibraryMarkSets(
      watchedMovieIds: watchedMovies,
      startedShowIds: startedShows,
      finishedShowIds: finishedShows,
      droppedShowIds: droppedShows,
      watchlistKeys: {for (final item in watchlist) item.key},
      ratings: {for (final item in ratings) item.key: item.rating},
      favoriteKeys: {for (final item in favorites) MediaKey(type: item.type, tmdbId: item.tmdbId)},
      trackedKeys: {for (final id in movieIds) MediaKey.movie(id), for (final id in showIds) MediaKey.show(id)},
      watchedPositions: positions,
    );
  }

  /// The marks of one key. A show reads as watched when it is *finished* (every aired episode
  /// played) with [showWatchedMeansFinished], or when it has any play otherwise.
  static LibraryMarks marksFor(MediaKey key, LibraryMarkSets sets, {bool showWatchedMeansFinished = false}) {
    final watched = switch (key.type) {
      ItemType.movie => sets.watchedMovieIds.contains(key.tmdbId),
      ItemType.show => showWatchedMeansFinished ? sets.finishedShowIds.contains(key.tmdbId) : sets.startedShowIds.contains(key.tmdbId),
      ItemType.season => (sets.watchedPositions[key.tmdbId] ?? const {}).any((position) => position.$1 == key.season),
      ItemType.episode => (sets.watchedPositions[key.tmdbId] ?? const {}).contains((key.season, key.episode)),
    };
    return LibraryMarks(
      watched: watched,
      watchListed: sets.watchlistKeys.contains(key),
      dropped: key.type != ItemType.movie && sets.droppedShowIds.contains(key.tmdbId),
      favorite: sets.favoriteKeys.contains(key),
      userRating: _userRating(key, sets),
    );
  }

  /// A season's rating is the formatted average of its rated episodes.
  static String? _userRating(MediaKey key, LibraryMarkSets sets) {
    if (key.type != ItemType.season) {
      return sets.ratings[key]?.toString();
    }
    final episodeRatings = [
      for (final entry in sets.ratings.entries)
        if (entry.key.type == ItemType.episode && entry.key.tmdbId == key.tmdbId && entry.key.season == key.season) entry.value,
    ];
    if (episodeRatings.isEmpty) {
      return null;
    }
    return RatingService.formatAverage(episodeRatings.fold<int>(0, (a, b) => a + b) / episodeRatings.length);
  }

  /// [models] stamped with their marks.
  static List<PosterModel> mark(List<PosterModel> models, LibraryMarkSets sets, {bool showWatchedMeansFinished = false}) {
    return [
      for (final model in models)
        model.copyWith(
          marks: marksFor(model.key, sets, showWatchedMeansFinished: showWatchedMeansFinished),
          tracked: model.tracked || sets.isTracked(model.key),
        ),
    ];
  }
}
