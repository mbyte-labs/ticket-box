import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/up_next_to_watch_order_by.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/up_next_to_watch_properties_key.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model_builder.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/up_next_to_watch_state.dart';

/// The Up Next grid: one derived query over the local catalogue, the log and the show states —
/// never a request. Re-run on every change of the tables it reads.
class UpNextToWatchBloc extends Cubit<UpNextToWatchState> {
  static final _log = Logger('UpNextToWatchBloc');

  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;
  bool _isProcessing = false;
  bool _needsRerun = false;

  UpNextToWatchBloc() : super(UpNextToWatchState.initial()) {
    _log.finest('Bloc created');
  }

  @override
  Future<void> close() async {
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  Future<void> init() async {
    await _restoreFilters();

    _dataChangeSubscription = DataChangeMonitor.instance().changes.listen((events) {
      // The log and the states decide which episode is next; the catalogue brings titles and
      // artwork paths (the backfill); the rest are the pills.
      if (events.contains(DataChangeEvent.historyRepo) ||
          events.contains(DataChangeEvent.showStateRepo) ||
          events.contains(DataChangeEvent.catalogRepo) ||
          events.contains(DataChangeEvent.watchlistRepo) ||
          events.contains(DataChangeEvent.userRatingRepo)) {
        unawaited(_load());
      }
    });

    await _load();
  }

  Future<void> toggleFilterPanel(bool isExpanded) async {
    final newState = state.copyWith.filters(containerExpanded: isExpanded);
    emit(newState);
  }

  Future<void> updateOrderBy(UpNextToWatchOrderBy orderBy) async {
    final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(orderBy: orderBy);
    emit(newState);
  }

  Future<void> updateOrderType(OrderType orderType) async {
    final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(orderType: orderType);
    emit(newState);
  }

  Future<void> updateDisplayAiredOnly(bool displayAiredOnly) async {
    final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(displayAiredOnly: displayAiredOnly);
    emit(newState);
  }

  Future<void> updateOnlyWithReleaseDate(bool onlyWithReleaseDate) async {
    final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(onlyWithReleaseDate: onlyWithReleaseDate);
    emit(newState);
  }

  Future<void> updateFilter() async {
    final newState = state.copyWith(initialLoading: true).copyWith.filters(filtersApplied: true, containerExpanded: false);
    emit(newState);
    unawaited(_saveFilters(newState.filters.filters));
    unawaited(_load());
  }

  /// Restores the filters that were applied the last time the page was used. A stored value that
  /// can no longer be parsed (a renamed enum value, a truncated write) is dropped instead of
  /// breaking the page, which then falls back to the defaults.
  ///
  /// Note: this is not gated on `GeneralPropertiesKeys.rememberFiltersOption` - that setting
  /// defaults to false and has no UI to turn it on yet, so honouring it would mean never
  /// restoring anything. It is the hook to use once that toggle exists.
  Future<void> _restoreFilters() async {
    try {
      final json = await KeyValueStore.instance().getJson(UpNextToWatchPropertiesKeys.filters);
      if (json == null) {
        return;
      }
      final filters = DashboardPageFilterOptions.fromJson(json);
      if (isClosed) return;
      emit(state.copyWith.filters(filters: filters, filtersApplied: true));
    } catch (e, stackTrace) {
      _log.severe('Error restoring the up next to watch filters, falling back to the defaults', e, stackTrace);
      await KeyValueStore.instance().remove(UpNextToWatchPropertiesKeys.filters);
    }
  }

  Future<void> _saveFilters(DashboardPageFilterOptions filters) async {
    try {
      await KeyValueStore.instance().setJson(UpNextToWatchPropertiesKeys.filters, filters.toJson());
    } catch (e, stackTrace) {
      _log.severe('Error saving the up next to watch filters', e, stackTrace);
    }
  }

  /// Runs the Up Next query with the current filters and marks the tiles. Calls arriving while a
  /// load is in flight coalesce into a single extra run.
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
          final mode = await _nextEpisodeMode();
          final rows = await ShowProgressQueries().upNext(
            onlyWithReleaseDate: filters.onlyWithReleaseDate,
            displayAiredOnly: filters.displayAiredOnly,
            orderBy: filters.orderBy,
            orderType: filters.orderType,
            mode: mode,
          );
          final marks = await LibraryMarksService().load(showIdsForPositions: rows.map((row) => row.next.showTmdbId));
          final models = LibraryMarksService.mark(rows.map(PosterModelBuilder.upNext).toList(), marks);
          if (isClosed) return;
          emit(state.copyWith(upNext: models, initialLoading: false, hasError: false));
        } catch (e, stackTrace) {
          _log.severe('Error loading up next to watch episodes', e, stackTrace);
          if (isClosed) return;
          emit(state.copyWith(initialLoading: false, hasError: true, message: e.toString()));
        }
      } while (_needsRerun);
    } finally {
      _isProcessing = false;
    }
  }

  Future<NextEpisodeMode> _nextEpisodeMode() async {
    final basedOnLastActivity = await KeyValueStore.instance().getBoolOrDefault(
      UpNextToWatchPropertiesKeys.nextEpisodeBasedOnLastActivity,
      false,
    );
    return basedOnLastActivity ? NextEpisodeMode.afterMostRecentlyWatched : NextEpisodeMode.afterLatestAiredWatched;
  }
}
