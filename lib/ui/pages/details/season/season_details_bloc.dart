import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:ticketbox/common/model/episode_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tuple.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/service/catalog/watch_region.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/external_rating/season_score_calculator.dart';
import 'package:ticketbox/service/library/dropped_shows_service.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/library/rating_service.dart';
import 'package:ticketbox/service/library/watch_history_write_service.dart';
import 'package:ticketbox/service/people/cast_member.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
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
import 'package:ticketbox/ui/pages/details/season/season_details_state.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The season page. One pass: the show snapshot and the season document (stored for a tracked
/// show, live and discarded otherwise) are read once and held, the user's rows and the derived
/// counts are read beside them, and every data-change event re-reads those only. The season
/// borrows the show's watch providers and regulars — the snapshot carries both at show level.
class SeasonDetailsBloc extends Cubit<SeasonDetailsState> {
  static final _log = Logger('SeasonDetailsBloc');

  /// The repository changes that can alter what this page shows without touching its own history
  /// rows (which have their own, season-scoped stream).
  static const _watchedChanges = {DataChangeEvent.watchlistRepo, DataChangeEvent.showStateRepo, DataChangeEvent.userRatingRepo};

  StreamSubscription<List<HistoryEntity>>? _historySubscription;
  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;
  bool _isProcessing = false;
  bool _needsRerun = false;

  SeasonView? _view;
  String? _region;

  /// Set once a stale snapshot has been refreshed behind this page, so the reload that follows
  /// does not ask again.
  bool _refreshed = false;

  SeasonDetailsBloc(Tuple2<int, int> providerId) : super(SeasonDetailsState.initial(providerId));

  @override
  Future<void> close() async {
    await _historySubscription?.cancel();
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  Future<void> init() async {
    final id = state.providerId;

    // Drift's watch() emits the current rows as soon as the stream is listened to (the repo's
    // fireImmediately flag is not honored — see HistoryRepo.listenForSeason), so skip that
    // initial emission; the _load below already covers it.
    _historySubscription = HistoryRepo().listenForSeason(id.item1, id.item2).skip(1).listen((_) => unawaited(_reloadUserData()));
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

  /// Adds or removes the season from the user's watchlist.
  Future<DetailsActionResult> setWatchlisted(bool watchlisted) async {
    final id = state.providerId;
    return _runAction(DetailsPendingAction.watchlist, () async {
      final service = WatchlistService();
      if (watchlisted) {
        await service.addSeason(id.item1, id.item2);
      } else {
        await service.removeSeason(id.item1, id.item2);
      }
    });
  }

  /// Marks the parent show as dropped, or clears that. Dropping is show-wide — there is no
  /// season-level dropped list — so the UI has to say so before calling in.
  Future<DetailsActionResult> setIgnored(bool ignored) async {
    final showTmdbId = state.providerId.item1;
    return _runAction(DetailsPendingAction.ignore, () async {
      final service = DroppedShowsService();
      if (ignored) {
        await service.drop(showTmdbId);
      } else {
        await service.undrop(showTmdbId);
      }
    });
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
        unawaited(_load());
      }
    }
  }

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
          final view = await ShowService().getSeason(id.item1, id.item2, region: _region);
          _view = view;
          if (isClosed) return;
          emit(await _assemble(view));
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
          _log.severe('Error loading season details for $id', e, stackTrace);
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
      } while (_needsRerun);
    } finally {
      _isProcessing = false;
    }
  }

  /// A data-change rerun: the held documents are kept, only the rows beside them are re-read.
  Future<void> _reloadUserData() async {
    final view = _view;
    if (view == null) {
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
          final next = await _assemble(view);
          if (isClosed) return;
          emit(next);
        } catch (e, stackTrace) {
          _log.severe('Error re-reading the user data of season ${state.providerId}', e, stackTrace);
        }
      } while (_needsRerun);
    } finally {
      _isProcessing = false;
    }
  }

  /// A tracked show older than the view TTL is re-fetched after the first paint (root and new
  /// seasons; an existing season document is never re-fetched by a view), then the page reloads
  /// from the store. Nothing happens when TMDB cannot be reached.
  Future<void> _refreshIfStale() async {
    final view = _view;
    if (_refreshed || view == null || !view.show.tracked || !view.show.isStale && view.show.providersRegion == _region) {
      return;
    }
    _refreshed = true;
    final fresh = await ShowService().refreshIfStale(state.providerId.item1, region: _region);
    if (fresh == null || isClosed) {
      return;
    }
    await _load();
  }

  Future<SeasonDetailsState> _assemble(SeasonView view) async {
    final id = state.providerId;
    final showTmdbId = id.item1;
    final seasonNumber = id.item2;
    final show = view.show.details;
    final season = view.season.details;
    final region = _region;

    final (historyEntries, seasonCounts, watchlistEntry, stateRow, ratingAverage, marks) = await (
      HistoryRepo().getForSeason(showTmdbId, seasonNumber),
      ShowProgressQueries().seasonCounts(showTmdbId),
      WatchlistService().getWatchlistSeason(showTmdbId, seasonNumber),
      ShowStateRepo().get(showTmdbId),
      RatingService().seasonAverage(showTmdbId, seasonNumber),
      LibraryMarksService().load(showIdsForPositions: [showTmdbId]),
    ).wait;

    final counts = seasonCounts[seasonNumber];
    final today = DetailsDates.today();
    final episodes = view.season.episodes;
    final airedInDocument = episodes.where((e) => e.airDate != null && e.airDate!.isNotEmpty && e.airDate!.compareTo(today) <= 0).length;
    final tracked = view.show.tracked || marks.isTracked(MediaKey.show(showTmdbId));
    final seasonPosterPath = view.season.posterPath ?? view.show.posterPath;
    final tiles = episodes
        .map(
          (e) => PosterModelBuilder.episodeEntry(
            showTmdbId,
            e,
            type: EpisodeType.fromWireValue(e.episodeType),
            showTitle: show.name,
            seasonPosterPath: seasonPosterPath,
            tracked: tracked,
          ),
        )
        .toList();
    final tmdbScore = SeasonScoreCalculator.weightedAverage(episodes);
    final providers = region == null ? null : view.show.providersFor(region);
    final cast = ItemCast.fromCredits(view.show.cast);

    return SeasonDetailsState(
      providerId: id,
      pendingAction: state.pendingAction,
      initialLoading: false,
      loadStatus: DetailsLoadStatus.loaded,
      hasError: false,
      message: '',
      tracked: tracked,
      posterPath: seasonPosterPath,
      backdropPath: view.show.backdropPath,
      title: season.name,
      showTitle: show.name,
      overview: season.overview,
      firstAired: DetailsDates.parse(season.airDate),
      externalRatings: ExternalRatings.combine(tmdbScore: tmdbScore.score, tmdbVotes: tmdbScore.votes),
      network: show.networks.isEmpty ? null : show.networks.first.name,
      language: show.originalLanguage,
      genres: view.show.genreNames,
      episodeCount: episodes.length,
      // The episode rows count aired episodes, the same number the watched count is measured
      // against; the document's dates are the fallback while the rows are not there yet.
      airedEpisodes: counts?.aired ?? airedInDocument,
      watchedEpisodes: counts?.watchedAired ?? 0,
      episodeRatingAverage: ratingAverage?.average,
      ratedEpisodes: ratingAverage?.count ?? 0,
      watchListed: watchlistEntry != null,
      dropped: stateRow?.isDropped ?? false,
      episodes: LibraryMarksService.mark(tiles, marks),
      actorsRegulars: cast.regulars,
      actorsGuests: cast.guests,
      externalLinks: _buildExternalLinks(showTmdbId, seasonNumber),
      watchedHistory: historyEntries
          .map((e) => SeasonWatchEntry(historyId: e.historyId, episode: e.episode, watchedAt: e.watchedAt.toLocal(), action: e.action))
          .toList(),
      watchProviderRegionSet: region != null,
      watchProviders: providers == null
          ? const []
          : providers.providers.map((e) => DetailsWatchProvider(name: e.providerName, logoUrl: e.logoPath)).toList(),
      watchProviderLink: providers?.justWatchLink,
    );
  }

  /// A season has no IMDb id, trailer or homepage of its own, so the only link is its TMDB page,
  /// composed from the parent show's id plus the season number.
  List<DetailsExternalLink> _buildExternalLinks(int showTmdbId, int season) {
    return [
      DetailsExternalLink(
        label: 'TMDB',
        url: 'https://www.themoviedb.org/tv/$showTmdbId/season/$season',
        icon: SimpleIcons.themoviedatabase,
        iconColor: ThemeColors.brandTmdb,
      ),
    ];
  }
}
