import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/show_progress_order_by.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/show_progress_properties_key.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/history/watched_history_item.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_list_item.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/poster/poster_model_builder.dart';
import 'package:ticketbox/service/progress/show_progress_calculator.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_details.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_state.dart';

/// The Show Progress list: one derived query over the local catalogue, the log and the show
/// states — never a request. Re-run on every change of the tables it reads.
class ShowProgressBloc extends Cubit<ShowProgressState> {
  static final _log = Logger('ShowProgressBloc');

  /// Chunk size for the per-show lookups (last watched titles, expanded season data).
  static const _lookupChunkSize = 16;

  /// The tables the rows are built from. The log and the states decide which shows are listed and
  /// how far along they are; the catalogue brings titles, artwork paths and the aired counts; the
  /// rest are the poster's pills.
  static const _sources = {
    DataChangeEvent.historyRepo,
    DataChangeEvent.showStateRepo,
    DataChangeEvent.catalogRepo,
    DataChangeEvent.watchlistRepo,
    DataChangeEvent.userRatingRepo,
    DataChangeEvent.favoriteRepo,
  };

  final _marksService = LibraryMarksService();

  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;
  bool _isProcessing = false;
  bool _needsRerun = false;

  ShowProgressBloc() : super(ShowProgressState.initial()) {
    _log.finest('Bloc created');
  }

  /// The [ShowProgressState.expandedSeasonKeys] entry of one season.
  static String seasonKey(int showId, int season) => '$showId-$season';

  @override
  Future<void> close() async {
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  Future<void> init() async {
    await _restoreFilters();

    _dataChangeSubscription = DataChangeMonitor.instance().changes.listen((events) {
      if (events.any(_sources.contains)) {
        unawaited(_load());
      }
    });

    await _load();
  }

  Future<void> toggleFilterPanel(bool isExpanded) async {
    final newState = state.copyWith.filters(containerExpanded: isExpanded);
    emit(newState);
  }

  Future<void> updateOrderBy(ShowProgressOrderBy orderBy) async {
    final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(orderBy: orderBy);
    emit(newState);
  }

  Future<void> updateOrderType(OrderType orderType) async {
    final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(orderType: orderType);
    emit(newState);
  }

  Future<void> updateHideCompleted(bool hideCompleted) async {
    final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(hideCompleted: hideCompleted);
    emit(newState);
  }

  Future<void> updateFilter() async {
    final newState = state.copyWith(initialLoading: true).copyWith.filters(filtersApplied: true, containerExpanded: false);
    emit(newState);
    unawaited(_saveFilters(newState.filters.filters));
    unawaited(_load());
  }

  /// Opens or closes the "View more details" section of one show. The first expansion loads the
  /// season/episode data lazily; later ones reuse what is already in the state.
  Future<void> toggleShowDetails(int showId) async {
    final expanded = {...state.expandedShowIds};
    final isExpanding = !expanded.remove(showId);
    if (isExpanding) {
      expanded.add(showId);
    }
    emit(state.copyWith(expandedShowIds: expanded));

    if (isExpanding && !state.seasonData.containsKey(showId)) {
      await _loadSeasonData(showId);
    }
  }

  /// Shows or hides the episode chips of one season. Pure UI - the data was already loaded
  /// together with the show's seasons.
  Future<void> toggleSeason(int showId, int season) async {
    final key = seasonKey(showId, season);
    final expanded = {...state.expandedSeasonKeys};
    if (!expanded.remove(key)) {
      expanded.add(key);
    }
    emit(state.copyWith(expandedSeasonKeys: expanded));
  }

  /// Restores the filters that were applied the last time the page was used. A stored value that
  /// can no longer be parsed (a renamed enum value, a truncated write) is dropped instead of
  /// breaking the page, which then falls back to the defaults.
  Future<void> _restoreFilters() async {
    try {
      final json = await KeyValueStore.instance().getJson(ShowProgressPropertiesKeys.filters);
      if (json == null) {
        return;
      }
      final filters = ShowProgressFilterOptions.fromJson(json);
      if (isClosed) return;
      emit(state.copyWith.filters(filters: filters, filtersApplied: true));
    } catch (e, stackTrace) {
      _log.severe('Error restoring the show progress filters, falling back to the defaults', e, stackTrace);
      await KeyValueStore.instance().remove(ShowProgressPropertiesKeys.filters);
    }
  }

  Future<void> _saveFilters(ShowProgressFilterOptions filters) async {
    try {
      await KeyValueStore.instance().setJson(ShowProgressPropertiesKeys.filters, filters.toJson());
    } catch (e, stackTrace) {
      _log.severe('Error saving the show progress filters', e, stackTrace);
    }
  }

  /// Runs the listing query with the current filters and assembles the rows. Calls arriving while
  /// a load is in flight coalesce into a single extra run.
  Future<void> _load() async {
    if (_isProcessing) {
      _needsRerun = true;
      return;
    }
    _isProcessing = true;
    try {
      do {
        _needsRerun = false;
        try {
          // Re-read the filters every iteration so a coalesced rerun picks up newly applied ones.
          final filters = state.filters.filters;
          final items = await ShowProgressQueries().listing(
            hideCompleted: filters.hideCompleted,
            orderBy: filters.orderBy,
            orderType: filters.orderType,
          );
          final lastWatchedByShow = await HistoryRepo().getLatestEpisodeEntryPerShow();

          final rows = await _assembleRows(items, lastWatchedByShow);
          // A live refresh keeps what the user opened: the expansion sets survive as they are and
          // the already loaded season data is re-read so the chips reflect the new watches.
          final seasonData = await _reloadSeasonData(state.seasonData.keys.toList());
          if (isClosed) return;
          emit(state.copyWith(rows: rows, seasonData: seasonData, initialLoading: false, hasError: false));
        } catch (e, stackTrace) {
          _log.severe('Error loading the show progress page', e, stackTrace);
          if (isClosed) return;
          emit(state.copyWith(initialLoading: false, hasError: true, message: e.toString()));
        }
      } while (_needsRerun);
    } finally {
      _isProcessing = false;
    }
  }

  /// Builds one renderable row per show: the poster tile from the show row (the listing's own
  /// title and path when the row is gone), marked, and the last watched episode's title, resolved
  /// in bounded chunks.
  Future<List<ShowProgressRowDetails>> _assembleRows(
    List<ShowProgressListItem> items,
    Map<int, WatchedHistoryItem> lastWatchedByShow,
  ) async {
    final posters = await _posters(items);
    final lastWatched = await _lastWatched(items, lastWatchedByShow);

    return [
      for (final item in items)
        ShowProgressRowDetails(
          showTmdbId: item.showTmdbId,
          title: item.title,
          poster: posters[item.showTmdbId]!,
          aired: item.aired,
          completed: item.completed,
          lastWatched: lastWatched[item.showTmdbId],
        ),
    ];
  }

  /// The marked poster tile of every listed show, keyed by show id.
  Future<Map<int, PosterModel>> _posters(List<ShowProgressListItem> items) async {
    final showIds = [for (final item in items) item.showTmdbId];
    final shows = await ShowRepo().getMany(showIds);
    final models = [
      for (final item in items)
        switch (shows[item.showTmdbId]) {
          final row? => PosterModelBuilder.show(row),
          null => PosterModel(
            key: MediaKey.show(item.showTmdbId),
            title: item.title.isEmpty ? PosterModelBuilder.noTitle : item.title,
            noPosterText: item.title.isEmpty ? PosterModelBuilder.noTitle : item.title,
            posterPath: item.posterPath,
            tracked: true,
            rating: null,
          ),
        },
    ];
    final marks = await _marksService.load();
    return {for (final model in LibraryMarksService.mark(models, marks)) model.key.tmdbId: model};
  }

  /// The last watched episode of every listed show that has one, with its title from the
  /// catalogue (null when the episode row is not there yet).
  Future<Map<int, LastWatchedEpisode>> _lastWatched(
    List<ShowProgressListItem> items,
    Map<int, WatchedHistoryItem> lastWatchedByShow,
  ) async {
    final entries = [for (final item in items) ?lastWatchedByShow[item.showTmdbId]];
    final episodes = await EpisodeRepo().getMany([for (final entry in entries) (entry.tmdbId, entry.season, entry.episode)]);
    return {
      for (final entry in entries)
        entry.tmdbId: LastWatchedEpisode(
          season: entry.season,
          episode: entry.episode,
          title: episodes[(entry.tmdbId, entry.season, entry.episode)]?.title,
          watchedAt: entry.lastWatchedAt.toLocal(),
        ),
    };
  }

  /// Loads the season/episode details of one show, tracked through
  /// [ShowProgressState.loadingSeasonDataIds] so the row can show a spinner.
  Future<void> _loadSeasonData(int showId) async {
    emit(state.copyWith(loadingSeasonDataIds: {...state.loadingSeasonDataIds, showId}));
    try {
      final details = await _gatherSeasonDetails(showId);
      if (isClosed) return;
      emit(
        state.copyWith(
          seasonData: {...state.seasonData, showId: details},
          loadingSeasonDataIds: {...state.loadingSeasonDataIds}..remove(showId),
        ),
      );
    } catch (e, stackTrace) {
      _log.severe('Error loading the season data for show $showId', e, stackTrace);
      if (isClosed) return;
      emit(state.copyWith(loadingSeasonDataIds: {...state.loadingSeasonDataIds}..remove(showId)));
    }
  }

  /// Re-reads the season data of the given shows, dropping the ones that fail. DB-only, so a
  /// whole-library refresh stays cheap even with several shows expanded.
  Future<Map<int, List<SeasonProgressDetails>>> _reloadSeasonData(List<int> showIds) async {
    final result = <int, List<SeasonProgressDetails>>{};
    for (final chunk in showIds.chunked(_lookupChunkSize)) {
      await Future.wait(
        chunk.map((showId) async {
          try {
            result[showId] = await _gatherSeasonDetails(showId);
          } catch (error, stackTrace) {
            _log.severe('Error reloading the season data for show $showId', error, stackTrace);
          }
        }),
      );
    }
    return result;
  }

  /// One query per table — the show's episode rows and its plays — folded in memory by
  /// [ShowProgressCalculator] into the per-season counts and the per-episode chips. Specials
  /// (season 0) are left out, the way the listing's counts leave them out.
  Future<List<SeasonProgressDetails>> _gatherSeasonDetails(int showId) async {
    final (episodes, plays) = await (EpisodeRepo().getAllForShow(showId), HistoryRepo().getForShow(showId)).wait;
    final result = ShowProgressCalculator.compute(
      catalogue: [for (final row in episodes) CatalogueEpisode(season: row.season, episode: row.episode, firstAired: row.firstAired)],
      watched: [
        for (final play in plays)
          WatchedEpisode(season: play.season, episode: play.episode, watchedAt: play.watchedAt, action: play.action),
      ],
      now: DateTime.now(),
    );

    final episodesBySeason = <int, List<EpisodeProgressDetails>>{};
    for (final episode in result.episodes) {
      episodesBySeason
          .putIfAbsent(episode.season, () => [])
          .add(EpisodeProgressDetails(season: episode.season, episode: episode.episode, completed: episode.completed));
    }
    for (final list in episodesBySeason.values) {
      list.sort((a, b) => a.episode.compareTo(b.episode));
    }

    return [
      for (final season in result.seasons)
        SeasonProgressDetails(
          season: season.season,
          aired: season.aired,
          completed: season.completed,
          episodes: episodesBySeason[season.season] ?? [],
        ),
    ];
  }
}
