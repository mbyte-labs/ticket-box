import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tuple.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/service/catalog/watch_region.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/external_rating/external_rating_service.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/external_rating/imdb_rating.dart';
import 'package:ticketbox/service/library/dropped_shows_service.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/library/rating_service.dart';
import 'package:ticketbox/service/library/watch_history_write_service.dart';
import 'package:ticketbox/service/people/cast_member.dart';
import 'package:ticketbox/service/show/show_service.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';
import 'package:ticketbox/ui/pages/details/common/details_action_result.dart';
import 'package:ticketbox/ui/pages/details/common/details_dates.dart';
import 'package:ticketbox/ui/pages/details/common/details_error_copy.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_provider.dart';
import 'package:ticketbox/ui/pages/details/episode/episode_details_state.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The episode page. One pass: the episode is its season document's entry (stored for a tracked
/// show, live and discarded otherwise), read once with the show snapshot and held; the user's
/// rows are read beside it and re-read on every data-change event. The episode borrows the
/// show's watch providers and regulars and adds its own guest stars. Its IMDb id is not in the
/// document: OMDb reveals it with the rating, and the row remembers it.
class EpisodeDetailsBloc extends Cubit<EpisodeDetailsState> {
  static final _log = Logger('EpisodeDetailsBloc');

  /// The repository changes that can alter what this page shows without touching its own history
  /// rows (which have their own, episode-scoped stream).
  static const _watchedChanges = {DataChangeEvent.watchlistRepo, DataChangeEvent.showStateRepo, DataChangeEvent.userRatingRepo};

  StreamSubscription<List<HistoryEntity>>? _historySubscription;
  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;
  bool _isProcessing = false;
  bool _needsRerun = false;

  EpisodeView? _view;
  ImdbRating? _imdb;
  String? _region;
  bool _refreshed = false;

  EpisodeDetailsBloc(Tuple3<int, int, int> providerId) : super(EpisodeDetailsState.initial(providerId));

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
    _historySubscription = HistoryRepo()
        .listenForItem(ItemType.episode, id.item1, season: id.item2, episode: id.item3)
        .skip(1)
        .listen((_) => unawaited(_reloadUserData()));
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

  /// Adds or removes the episode from the user's watchlist.
  Future<DetailsActionResult> setWatchlisted(bool watchlisted) async {
    final id = state.providerId;
    return _runAction(DetailsPendingAction.watchlist, () async {
      final service = WatchlistService();
      if (watchlisted) {
        await service.addEpisode(id.item1, id.item2, id.item3);
      } else {
        await service.removeEpisode(id.item1, id.item2, id.item3);
      }
    });
  }

  /// Marks the parent show as dropped, or clears that. Dropping is show-wide — there is no
  /// episode-level dropped list — so the UI has to say so before calling in.
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

  /// Rates this episode (1-10) from the ratings card. The new value is shown immediately; a
  /// failed write reverts it.
  Future<DetailsActionResult> rate(int rating) async {
    final target = state.markAsWatchedTarget;
    emit(state.copyWith(userRating: rating.toString()));
    return _runAction(DetailsPendingAction.rate, () => RatingService().addRating(target: target, rating: rating));
  }

  /// Removes the user's rating for this episode. The hearts empty immediately; a failed write
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
          final view = await ShowService().getEpisode(id.item1, id.item2, id.item3, region: _region);
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
          _log.severe('Error loading episode details for $id', e, stackTrace);
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
          _log.severe('Error re-reading the user data of episode ${state.providerId}', e, stackTrace);
        }
      } while (_needsRerun);
    } finally {
      _isProcessing = false;
    }
  }

  /// A tracked show older than the view TTL is re-fetched after the first paint, then the page
  /// reloads from the store. Nothing happens when TMDB cannot be reached.
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

  /// The IMDb rating (OMDb through the show's id, cached 14 days, never throws). The answer names
  /// the episode's own IMDb id, which the link row uses; the TMDB half rides the document.
  Future<void> _loadImdb() async {
    final view = _view;
    if (view == null) {
      return;
    }
    final id = state.providerId;
    final imdb = await ExternalRatingService().getForEpisode(
      id.item1,
      id.item2,
      id.item3,
      showImdbId: view.show.imdbId,
      episodeImdbId: state.imdbId,
    );
    if (imdb == null || isClosed) {
      return;
    }
    _imdb = imdb;
    await _reloadUserData();
  }

  Future<EpisodeDetailsState> _assemble(EpisodeView view) async {
    final id = state.providerId;
    final showTmdbId = id.item1;
    final show = view.show.details;
    final episode = view.episode;
    final region = _region;
    final key = MediaKey.episode(showTmdbId, id.item2, id.item3);

    final (historyEntries, watchlistEntry, stateRow, rating, row) = await (
      HistoryRepo().getForEpisode(showTmdbId, id.item2, id.item3),
      WatchlistService().getWatchlistEpisode(showTmdbId, id.item2, id.item3),
      ShowStateRepo().get(showTmdbId),
      UserRatingRepo().getByKey(key),
      EpisodeRepo().get(showTmdbId, id.item2, id.item3),
    ).wait;

    final imdbId = _imdb?.imdbId ?? row?.imdbId ?? state.imdbId;
    final providers = region == null ? null : view.show.providersFor(region);
    final cast = ItemCast.fromCredits(view.show.cast, episode.guestStars);

    return EpisodeDetailsState(
      providerId: id,
      imdbId: imdbId,
      pendingAction: state.pendingAction,
      initialLoading: false,
      loadStatus: DetailsLoadStatus.loaded,
      hasError: false,
      message: '',
      tracked: view.show.tracked || row != null,
      stillPath: episode.stillPath,
      backdropPath: view.show.backdropPath,
      title: episode.name ?? '-Unavailable-',
      showTitle: show.name,
      overview: episode.overview,
      firstAired: DetailsDates.parse(episode.airDate),
      externalRatings: ExternalRatings.combine(tmdbScore: episode.voteAverage, tmdbVotes: episode.voteCount, imdb: _imdb),
      network: show.networks.isEmpty ? null : show.networks.first.name,
      language: show.originalLanguage,
      genres: view.show.genreNames,
      runtime: episode.runtime,
      userRating: rating?.rating.toString(),
      watchListed: watchlistEntry != null,
      dropped: stateRow?.isDropped ?? false,
      actorsRegulars: cast.regulars,
      actorsGuests: cast.guests,
      externalLinks: _buildExternalLinks(showTmdbId, id.item2, id.item3, imdbId),
      watchedHistory: historyEntries
          .map((e) => EpisodeWatchEntry(historyId: e.historyId, watchedAt: e.watchedAt.toLocal(), action: e.action))
          .toList(),
      watchProviderRegionSet: region != null,
      watchProviders: providers == null
          ? const []
          : providers.providers.map((e) => DetailsWatchProvider(name: e.providerName, logoUrl: e.logoPath)).toList(),
      watchProviderLink: providers?.justWatchLink,
    );
  }

  /// The TMDB link is composed from the parent show's id plus the numbering. The IMDb id is the
  /// episode's own, so that link goes straight to the episode's IMDb page.
  List<DetailsExternalLink> _buildExternalLinks(int showTmdbId, int season, int episode, String? imdbId) {
    final links = <DetailsExternalLink>[
      DetailsExternalLink(
        label: 'TMDB',
        url: 'https://www.themoviedb.org/tv/$showTmdbId/season/$season/episode/$episode',
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

    return links;
  }
}
