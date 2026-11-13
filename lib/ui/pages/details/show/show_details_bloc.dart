import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/show_status.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/service/catalog/snapshots.dart';
import 'package:ticketbox/service/catalog/watch_region.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/external_rating/external_rating_service.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/external_rating/imdb_rating.dart';
import 'package:ticketbox/service/library/dropped_shows_service.dart';
import 'package:ticketbox/service/library/favorite_service.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/library/rating_service.dart';
import 'package:ticketbox/service/library/watch_history_write_service.dart';
import 'package:ticketbox/service/people/cast_member.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/poster/poster_model_builder.dart';
import 'package:ticketbox/service/show/show_service.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';
import 'package:ticketbox/ui/pages/details/common/details_action_result.dart';
import 'package:ticketbox/ui/pages/details/common/details_dates.dart';
import 'package:ticketbox/ui/pages/details/common/details_error_copy.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_provider.dart';
import 'package:ticketbox/ui/pages/details/show/show_details_state.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The show page. One pass: the snapshot (stored, for a tracked show; live, discarded, for an
/// untracked one) is parsed once and held, the user's rows and the derived counts are read beside
/// it, and every data-change event re-reads those only. A tracked show whose snapshot is stale is
/// refreshed in the background after the first paint (root and new seasons) and re-emitted when
/// that lands; a failed refresh is invisible. Only an untracked show can fail to load.
class ShowDetailsBloc extends Cubit<ShowDetailsState> {
  static final _log = Logger('ShowDetailsBloc');

  /// The repository changes that can alter what this page shows without touching its own history
  /// rows (which have their own, show-scoped stream). The catalogue is in the set because the
  /// seasons grid reads the season rows, which the backfill fills in behind the page.
  static const _watchedChanges = {
    DataChangeEvent.watchlistRepo,
    DataChangeEvent.showStateRepo,
    DataChangeEvent.userRatingRepo,
    DataChangeEvent.favoriteRepo,
    DataChangeEvent.catalogRepo,
  };

  StreamSubscription<List<HistoryEntity>>? _historySubscription;
  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;
  bool _isProcessing = false;
  bool _needsRerun = false;

  ShowSnapshot? _snapshot;
  ImdbRating? _imdb;
  String? _region;

  ShowDetailsBloc(int providerId) : super(ShowDetailsState.initial(providerId));

  @override
  Future<void> close() async {
    await _historySubscription?.cancel();
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  Future<void> init() async {
    final id = state.providerId;

    // Drift's watch() emits the current rows as soon as the stream is listened to (the repo's
    // fireImmediately flag is not honored — see HistoryRepo.listenForShow), so skip that initial
    // emission; the _load below already covers it.
    _historySubscription = HistoryRepo().listenForShow(id).skip(1).listen((_) => unawaited(_reloadUserData()));
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

  /// Adds or removes the show from the user's watchlist.
  Future<DetailsActionResult> setWatchlisted(bool watchlisted) async {
    final id = state.providerId;
    return _runAction(DetailsPendingAction.watchlist, () async {
      final service = WatchlistService();
      if (watchlisted) {
        await service.addShow(id);
      } else {
        await service.removeShow(id);
      }
    });
  }

  /// Marks the show as dropped, or clears that.
  Future<DetailsActionResult> setIgnored(bool ignored) async {
    final id = state.providerId;
    return _runAction(DetailsPendingAction.ignore, () async {
      final service = DroppedShowsService();
      if (ignored) {
        await service.drop(id);
      } else {
        await service.undrop(id);
      }
    });
  }

  /// Adds the show to the user's favorites, or removes it.
  Future<DetailsActionResult> setFavorite(bool favorite) async {
    final id = state.providerId;
    return _runAction(DetailsPendingAction.favorite, () async {
      final service = FavoriteService();
      if (favorite) {
        await service.favorite(ItemType.show, id);
      } else {
        await service.unfavorite(ItemType.show, id);
      }
    });
  }

  /// Rates this show (1-10) from the ratings card. The new value is shown immediately; a failed
  /// write reverts it.
  Future<DetailsActionResult> rate(int rating) async {
    final target = state.markAsWatchedTarget;
    emit(state.copyWith(userRating: rating.toString()));
    return _runAction(DetailsPendingAction.rate, () => RatingService().addRating(target: target, rating: rating));
  }

  /// Removes the user's rating for this show. The hearts empty immediately; a failed write
  /// reverts them.
  Future<DetailsActionResult> removeRating() async {
    final target = state.markAsWatchedTarget;
    emit(state.copyWith(userRating: null));
    return _runAction(DetailsPendingAction.rate, () => RatingService().removeRating(target: target));
  }

  /// Runs an action-bar write with the spinner shown on [action], then re-reads the page so it
  /// reflects the change. A write on an untracked show adds it to the library first, which is
  /// the one case that can need TMDB.
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
        // The write may have added the show to the library: re-read the snapshot too.
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
          final snapshot = await ShowService().getDetails(id, region: _region);
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
          _log.severe('Error loading show details for $id', e, stackTrace);
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

  /// A data-change rerun: the parsed snapshot is kept, only the rows beside it are re-read.
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
          _log.severe('Error re-reading the user data of show ${state.providerId}', e, stackTrace);
        }
      } while (_needsRerun);
    } finally {
      _isProcessing = false;
    }
  }

  /// A tracked show older than the view TTL is re-fetched after the first paint; the fresh
  /// snapshot replaces the held one. Nothing happens when TMDB cannot be reached.
  Future<void> _refreshIfStale() async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.tracked || !snapshot.isStale && snapshot.providersRegion == _region) {
      return;
    }
    final fresh = await ShowService().refreshIfStale(state.providerId, region: _region);
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
    final imdb = await ExternalRatingService().getForShow(state.providerId, snapshot.imdbId);
    if (imdb == null || isClosed) {
      return;
    }
    _imdb = imdb;
    await _reloadUserData();
  }

  Future<ShowDetailsState> _assemble(ShowSnapshot snapshot) async {
    final id = state.providerId;
    final details = snapshot.details;
    final key = MediaKey.show(id);
    final region = _region;

    final (historyEntries, counts, watchlistEntry, stateRow, favoriteEntry, rating, marks, seasonRows) = await (
      HistoryRepo().getForShow(id),
      ShowProgressQueries().showCounts(id),
      WatchlistService().getWatchlistShow(id),
      ShowStateRepo().get(id),
      FavoriteRepo().get(ItemType.show, id),
      UserRatingRepo().getByKey(key),
      LibraryMarksService().load(showIdsForPositions: [id]),
      snapshot.tracked ? SeasonRepo().getAllForShow(id) : Future.value(const <SeasonEntity>[]),
    ).wait;

    final title = details.name;
    final posterPath = snapshot.posterPath;
    // The season rows once the show is materialised; the document's season stubs before that
    // (and for a live view), so the grid never waits for the backfill.
    final seasonModels = seasonRows.isNotEmpty
        ? seasonRows.map((row) => PosterModelBuilder.season(row, showTitle: title, showPosterPath: posterPath)).toList()
        : snapshot.seasons
              .map(
                (stub) => PosterModelBuilder.seasonStub(id, stub, showTitle: title, showPosterPath: posterPath, tracked: snapshot.tracked),
              )
              .toList();
    seasonModels.sort((a, b) => (a.key.season ?? 0).compareTo(b.key.season ?? 0));

    final providers = region == null ? null : snapshot.providersFor(region);
    final cast = ItemCast.fromCredits(snapshot.cast);
    final homepage = details.homepage;
    final trailer = snapshot.trailerUrl;

    return ShowDetailsState(
      providerId: id,
      imdbId: snapshot.imdbId,
      pendingAction: state.pendingAction,
      initialLoading: false,
      loadStatus: DetailsLoadStatus.loaded,
      hasError: false,
      message: '',
      tracked: snapshot.tracked || marks.isTracked(key),
      posterPath: posterPath,
      backdropPath: snapshot.backdropPath,
      title: title,
      year: DetailsDates.year(details.firstAirDate),
      overview: details.overview,
      firstAired: DetailsDates.parse(details.firstAirDate),
      popularity: details.popularity,
      voteCount: details.voteCount,
      externalRatings: ExternalRatings.combine(tmdbScore: details.voteAverage, tmdbVotes: details.voteCount, imdb: _imdb),
      network: details.networks.isEmpty ? null : details.networks.first.name,
      country: details.originCountry.isEmpty ? null : details.originCountry.first,
      certification: snapshot.certification('US'),
      status: ShowStatus.fromTmdb(details.status),
      language: details.originalLanguage,
      genres: snapshot.genreNames,
      runtime: details.episodeRunTime.isNotEmpty ? details.episodeRunTime.first : details.lastEpisodeToAir?.runtime,
      // The local episode rows count aired episodes, which is the same number the watched count
      // is measured against; TMDB's episode total is the fallback for a show without rows yet.
      airedEpisodes: counts.total > 0 ? counts.aired : details.numberOfEpisodes,
      nextEpisodeAirDate: DetailsDates.parse(details.nextEpisodeToAir?.airDate),
      trailer: trailer,
      homepage: (homepage == null || homepage.trim().isEmpty) ? null : homepage,
      watchedEpisodes: counts.watchedAired,
      lastWatchedAt: counts.lastWatchedAt?.toLocal(),
      userRating: rating?.rating.toString(),
      watchListed: watchlistEntry != null,
      dropped: stateRow?.isDropped ?? false,
      favorite: favoriteEntry != null,
      seasons: LibraryMarksService.mark(seasonModels, marks),
      actorsRegulars: cast.regulars,
      actorsGuests: cast.guests,
      externalLinks: _buildExternalLinks(id, snapshot.imdbId, trailer, homepage),
      watchedHistory: historyEntries
          .map(
            (e) => ShowWatchEntry(
              historyId: e.historyId,
              season: e.season,
              episode: e.episode,
              watchedAt: e.watchedAt.toLocal(),
              action: e.action,
            ),
          )
          .toList(),
      related: _related(snapshot, marks),
      watchProviderRegionSet: region != null,
      watchProviders: providers == null
          ? const []
          : providers.providers.map((e) => DetailsWatchProvider(name: e.providerName, logoUrl: e.logoPath)).toList(),
      watchProviderLink: providers?.justWatchLink,
    );
  }

  static List<PosterModel> _related(ShowSnapshot snapshot, LibraryMarkSets marks) {
    return LibraryMarksService.mark(snapshot.related.map(PosterModelBuilder.showListItem).toList(), marks);
  }

  /// TMDB always resolves from the page's own id; IMDb, the trailer and the homepage are skipped
  /// when TMDB did not return them, so the row degrades gracefully.
  List<DetailsExternalLink> _buildExternalLinks(int tmdbId, String? imdbId, String? trailer, String? homepage) {
    final links = <DetailsExternalLink>[
      DetailsExternalLink(
        label: 'TMDB',
        url: 'https://www.themoviedb.org/tv/$tmdbId',
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
