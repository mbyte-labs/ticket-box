import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/movie_status.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/service/catalog/snapshots.dart';
import 'package:ticketbox/service/catalog/watch_region.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/external_rating/external_rating_service.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/external_rating/imdb_rating.dart';
import 'package:ticketbox/service/library/favorite_service.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/library/rating_service.dart';
import 'package:ticketbox/service/library/watch_history_write_service.dart';
import 'package:ticketbox/service/movie/movie_service.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model_builder.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';
import 'package:ticketbox/ui/pages/details/common/details_action_result.dart';
import 'package:ticketbox/ui/pages/details/common/details_error_copy.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_provider.dart';
import 'package:ticketbox/ui/pages/details/movie/movie_details_state.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The movie page. One pass: the snapshot (stored, for a tracked movie; live, discarded, for an
/// untracked one) is parsed once and held, the user's rows are read beside it, and every
/// data-change event re-reads the user rows only. A tracked movie whose snapshot is stale is
/// refreshed in the background after the first paint and re-emitted when that lands; a failed
/// refresh is invisible — the stale snapshot stays. Only an untracked movie can fail to load.
class MovieDetailsBloc extends Cubit<MovieDetailsState> {
  static final _log = Logger('MovieDetailsBloc');

  /// The repository changes that can alter what this page shows without touching its own history
  /// rows (which have their own, item-scoped stream).
  static const _watchedChanges = {
    DataChangeEvent.watchlistRepo,
    DataChangeEvent.userRatingRepo,
    DataChangeEvent.favoriteRepo,
    DataChangeEvent.showStateRepo,
  };

  StreamSubscription<List<HistoryEntity>>? _historySubscription;
  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;
  bool _isProcessing = false;
  bool _needsRerun = false;

  MovieSnapshot? _snapshot;
  ImdbRating? _imdb;
  String? _region;

  MovieDetailsBloc(int providerId) : super(MovieDetailsState.initial(providerId));

  @override
  Future<void> close() async {
    await _historySubscription?.cancel();
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  Future<void> init() async {
    final id = state.providerId;

    // Drift's watch() emits the current rows as soon as the stream is listened to (the repo's
    // fireImmediately flag is not honored — see HistoryRepo.listenForItem), so skip that initial
    // emission; the _load below already covers it.
    _historySubscription = HistoryRepo().listenForItem(ItemType.movie, id).skip(1).listen((_) => unawaited(_reloadUserData()));
    _dataChangeSubscription = DataChangeMonitor.instance().changes
        .where((events) => events.any(_watchedChanges.contains))
        .listen((_) => unawaited(_reloadUserData()));

    await _load();
  }

  /// Removes a watch-history entry from the local store. Returns false when the removal failed.
  Future<bool> deleteHistoryEntry(int historyId) async {
    try {
      await WatchHistoryWriteService().removeByHistoryId(historyId);
      unawaited(_reloadUserData());
      return true;
    } catch (e, stackTrace) {
      _log.severe('Error removing history entry $historyId', e, stackTrace);
      return false;
    }
  }

  /// Adds or removes the movie from the user's watchlist.
  Future<DetailsActionResult> setWatchlisted(bool watchlisted) async {
    final id = state.providerId;
    return _runAction(DetailsPendingAction.watchlist, () async {
      final service = WatchlistService();
      if (watchlisted) {
        await service.addMovie(id);
      } else {
        await service.removeMovie(id);
      }
    });
  }

  /// Adds the movie to the user's favorites, or removes it.
  Future<DetailsActionResult> setFavorite(bool favorite) async {
    final id = state.providerId;
    return _runAction(DetailsPendingAction.favorite, () async {
      final service = FavoriteService();
      if (favorite) {
        await service.favorite(ItemType.movie, id);
      } else {
        await service.unfavorite(ItemType.movie, id);
      }
    });
  }

  /// Rates this movie (1-10) from the ratings card. The new value is shown immediately; a failed
  /// write reverts it.
  Future<DetailsActionResult> rate(int rating) async {
    final target = state.markAsWatchedTarget;
    // Optimistic: flips the hearts/caption now, and gives the rating bar a prop change to
    // revert on when the reload below re-reads the old value after a failure.
    emit(state.copyWith(userRating: rating.toString()));
    return _runAction(DetailsPendingAction.rate, () => RatingService().addRating(target: target, rating: rating));
  }

  /// Removes the user's rating for this movie. The hearts empty immediately; a failed write
  /// reverts them.
  Future<DetailsActionResult> removeRating() async {
    final target = state.markAsWatchedTarget;
    emit(state.copyWith(userRating: null));
    return _runAction(DetailsPendingAction.rate, () => RatingService().removeRating(target: target));
  }

  /// Runs an action-bar write with the spinner shown on [action], then re-reads the user rows so
  /// the page reflects the change. A write on an untracked movie adds it to the library first,
  /// which is the one case that can need TMDB.
  Future<DetailsActionResult> _runAction(DetailsPendingAction action, Future<void> Function() work) async {
    if (isClosed) return DetailsActionResult.failed;
    emit(state.copyWith(pendingAction: action));

    try {
      await work();
      return DetailsActionResult.done;
    } catch (e, stackTrace) {
      if (e is TrackingUnavailableException || e is ItemGoneException) {
        _log.warning('Could not run $action for ${state.providerId}: $e');
      } else {
        _log.severe('Error running $action for ${state.providerId}', e, stackTrace);
      }
      return DetailsActionResult.forError(e);
    } finally {
      if (!isClosed) {
        emit(state.copyWith(pendingAction: null));
        // The write may have added the movie to the library: re-read the snapshot too.
        unawaited(_load());
      }
    }
  }

  /// The snapshot (stored or live), then the user's rows beside it.
  Future<void> _load() async {
    if (_isProcessing) {
      _needsRerun = true;
      return;
    }
    _isProcessing = true;
    try {
      do {
        _needsRerun = false;
        final id = state.providerId;
        _region = await WatchRegion.configured();
        try {
          final snapshot = await MovieService().getDetails(id, region: _region);
          _snapshot = snapshot;
          if (isClosed) return;
          emit(await _assemble(snapshot));
        } on ItemGoneException {
          if (isClosed) return;
          emit(
            state.copyWith(
              initialLoading: false,
              loadStatus: DetailsLoadStatus.notFound,
              hasError: true,
              message: DetailsErrorCopy.notFound,
            ),
          );
          continue;
        } catch (e, stackTrace) {
          _log.severe('Error loading movie details for $id', e, stackTrace);
          if (isClosed) return;
          emit(
            state.copyWith(
              initialLoading: false,
              loadStatus: DetailsLoadStatus.unreachable,
              hasError: true,
              message: DetailsErrorCopy.forError(e),
            ),
          );
          continue;
        }
        unawaited(_refreshIfStale());
        unawaited(_loadImdb());
      } while (_needsRerun);
    } finally {
      _isProcessing = false;
    }
  }

  /// A data-change rerun: the parsed snapshot is kept, only the user rows are re-read.
  Future<void> _reloadUserData() async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return _load();
    }
    if (_isProcessing) {
      _needsRerun = true;
      return;
    }
    _isProcessing = true;
    try {
      do {
        _needsRerun = false;
        try {
          final next = await _assemble(snapshot);
          if (isClosed) return;
          emit(next);
        } catch (e, stackTrace) {
          _log.severe('Error re-reading the user data of movie ${state.providerId}', e, stackTrace);
        }
      } while (_needsRerun);
    } finally {
      _isProcessing = false;
    }
  }

  /// A tracked movie older than the view TTL is re-fetched after the first paint; the fresh
  /// snapshot replaces the held one. Nothing happens when TMDB cannot be reached.
  Future<void> _refreshIfStale() async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.tracked || !snapshot.isStale && snapshot.providersRegion == _region) {
      return;
    }
    final fresh = await MovieService().refreshIfStale(state.providerId, region: _region);
    if (fresh == null || isClosed) {
      return;
    }
    _snapshot = fresh;
    await _reloadUserData();
  }

  /// The IMDb rating (OMDb, cached 14 days, never throws); the TMDB half rides the snapshot.
  Future<void> _loadImdb() async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    final imdb = await ExternalRatingService().getForMovie(state.providerId, snapshot.imdbId);
    if (imdb == null || isClosed) {
      return;
    }
    _imdb = imdb;
    await _reloadUserData();
  }

  Future<MovieDetailsState> _assemble(MovieSnapshot snapshot) async {
    final id = state.providerId;
    final details = snapshot.details;
    final key = MediaKey.movie(id);
    final region = _region;

    final (historyEntries, watchlistEntry, favoriteEntry, rating, marks) = await (
      HistoryRepo().getForMovie(id),
      WatchlistService().getWatchlistMovie(id),
      FavoriteRepo().get(ItemType.movie, id),
      UserRatingRepo().getByKey(key),
      LibraryMarksService().load(),
    ).wait;

    final providers = region == null ? null : snapshot.providersFor(region);
    final related = LibraryMarksService.mark(snapshot.related.map(PosterModelBuilder.movieListItem).toList(), marks);
    final tagline = details.tagline;
    final homepage = details.homepage;

    return MovieDetailsState(
      providerId: id,
      imdbId: snapshot.imdbId,
      pendingAction: state.pendingAction,
      initialLoading: false,
      loadStatus: DetailsLoadStatus.loaded,
      hasError: false,
      message: '',
      tracked: snapshot.tracked || marks.isTracked(key),
      posterPath: snapshot.posterPath,
      backdropPath: snapshot.backdropPath,
      title: details.title,
      year: _year(details.releaseDate),
      tagLine: (tagline == null || tagline.trim().isEmpty) ? null : tagline,
      overview: details.overview,
      released: _date(details.releaseDate),
      popularity: details.popularity,
      voteCount: details.voteCount,
      externalRatings: ExternalRatings.combine(tmdbScore: details.voteAverage, tmdbVotes: details.voteCount, imdb: _imdb),
      country: details.productionCountries.isEmpty ? null : details.productionCountries.first.iso3166_1,
      certification: snapshot.certification('US'),
      status: MovieStatus.fromTmdb(details.status),
      language: details.originalLanguage,
      genres: snapshot.genreNames,
      runtime: (details.runtime == null || details.runtime == 0) ? null : details.runtime,
      trailer: snapshot.trailerUrl,
      homepage: (homepage == null || homepage.trim().isEmpty) ? null : homepage,
      userPlays: historyEntries.length,
      // getForMovie orders by watchedAt descending, so the first entry is the latest play.
      lastWatchedAt: historyEntries.isEmpty ? null : historyEntries.first.watchedAt.toLocal(),
      userRating: rating?.rating.toString(),
      watchListed: watchlistEntry != null,
      favorite: favoriteEntry != null,
      actors: snapshot.cast
          .map((e) => MovieActorData(name: e.name, characterName: e.character ?? '', profilePath: e.profilePath, personTmdbId: e.id))
          .toList(),
      externalLinks: _buildExternalLinks(id, snapshot.imdbId, snapshot.trailerUrl, homepage),
      watchedHistory: historyEntries
          .map((e) => MovieWatchEntry(historyId: e.historyId, watchedAt: e.watchedAt.toLocal(), action: e.action))
          .toList(),
      related: related,
      watchProviderRegionSet: region != null,
      watchProviders: providers == null
          ? const []
          : providers.providers.map((e) => DetailsWatchProvider(name: e.providerName, logoUrl: e.logoPath)).toList(),
      watchProviderLink: providers?.justWatchLink,
    );
  }

  static DateTime? _date(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static int? _year(String? value) => _date(value)?.year;

  /// TMDB always resolves from the page's own id; IMDb, the trailer and the homepage are skipped
  /// when TMDB did not return them, so the row degrades gracefully.
  List<DetailsExternalLink> _buildExternalLinks(int tmdbId, String? imdbId, String? trailer, String? homepage) {
    final links = <DetailsExternalLink>[
      DetailsExternalLink(
        label: 'TMDB',
        url: 'https://www.themoviedb.org/movie/$tmdbId',
        icon: SimpleIcons.themoviedatabase,
        iconColor: ThemeColors.brandTmdb,
      ),
    ];

    if (imdbId != null && imdbId.isNotEmpty) {
      links.add(
        DetailsExternalLink(
          label: 'IMDb',
          url: 'https://www.imdb.com/title/$imdbId',
          icon: SimpleIcons.imdb,
          iconColor: ThemeColors.brandImdb,
        ),
      );
    }

    if (trailer != null && trailer.isNotEmpty) {
      links.add(DetailsExternalLink(label: 'Trailer', url: trailer, icon: SimpleIcons.youtube, iconColor: ThemeColors.brandYoutube));
    }

    if (homepage != null && homepage.trim().isNotEmpty) {
      links.add(DetailsExternalLink(label: 'Website', url: homepage, icon: Icons.public));
    }

    return links;
  }
}
