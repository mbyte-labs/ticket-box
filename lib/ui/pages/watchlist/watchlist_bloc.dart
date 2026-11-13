import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/filter/page_details.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/watchlist_item_type_filter.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/watchlist_properties_key.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model_resolver.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';
import 'package:ticketbox/ui/pages/watchlist/watchlist_state.dart';

/// The kind of work [WatchlistBloc._run] is asked to do.
enum _PagingOperation {
  /// Load page one and throw away everything already loaded - the first load, or a filter change.
  reload,

  /// Re-read every page already loaded, keeping the list the same length.
  refresh,

  /// Append the page after the last one loaded.
  loadMore,
}

/// The watchlist grid: the listed items, paged, with their tiles built from the local catalogue
/// and marked from the user tables - never a request.
class WatchlistBloc extends Cubit<WatchlistState> {
  static final _log = Logger('WatchlistBloc');

  static const _pageSize = 50;

  /// The tables the grid is built from. The watchlist decides which items are listed; the
  /// catalogue brings titles and artwork paths (the backfill); the rest are the pills.
  static const _sources = {
    DataChangeEvent.watchlistRepo,
    DataChangeEvent.catalogRepo,
    DataChangeEvent.historyRepo,
    DataChangeEvent.showStateRepo,
    DataChangeEvent.userRatingRepo,
    DataChangeEvent.favoriteRepo,
  };

  final _watchlistService = WatchlistService();
  final _resolver = PosterModelResolver();
  final _marksService = LibraryMarksService();

  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;

  bool _isProcessing = false;
  bool _reloadRequested = false;
  bool _loadMoreRequested = false;

  WatchlistBloc() : super(WatchlistState.initial()) {
    _log.finest('Bloc created');
  }

  @override
  Future<void> close() async {
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  /// Whether a further page can be appended.
  ///
  /// Checked synchronously before the first await of [loadNextPage] because the scroll listener
  /// calls it on very nearly every scrolled pixel.
  bool get canLoadMore => !state.initialLoading && !state.isLoadingMore && !state.hasReachedEnd;

  Future<void> init() async {
    await _restoreFilters();

    _dataChangeSubscription = DataChangeMonitor.instance().changes.listen((events) {
      if (events.any(_sources.contains)) {
        // A refresh rather than a reload: the pages the user scrolled through stay valid, and an
        // item added or removed elsewhere only shifts rows. Reloading would collapse the list out
        // from under them on every write.
        unawaited(_run(_PagingOperation.refresh));
      }
    });

    await _run(_PagingOperation.reload);
  }

  Future<void> loadNextPage() async {
    if (!canLoadMore) {
      return;
    }
    await _run(_PagingOperation.loadMore);
  }

  Future<void> toggleFilterPanel(bool isExpanded) async {
    final newState = state.copyWith.filters(containerExpanded: isExpanded);
    emit(newState);
  }

  Future<void> updateItemTypes(WatchlistItemTypeFilter itemTypes) async {
    final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(itemTypes: itemTypes);
    emit(newState);
  }

  Future<void> updateOrderType(OrderType orderType) async {
    final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(orderType: orderType);
    emit(newState);
  }

  Future<void> updateFilter() async {
    final newState = state
        .copyWith(initialLoading: true, models: [], loadedPage: 0, totalPages: -1, hasReachedEnd: false)
        .copyWith
        .filters(filtersApplied: true, containerExpanded: false);
    emit(newState);
    unawaited(_saveFilters(newState.filters.filters));
    unawaited(_run(_PagingOperation.reload));
  }

  /// Restores the filters that were applied the last time the page was used. A stored value that
  /// can no longer be parsed (a renamed enum value, a truncated write) is dropped instead of
  /// breaking the page, which then falls back to the defaults.
  Future<void> _restoreFilters() async {
    try {
      final json = await KeyValueStore.instance().getJson(WatchlistPropertiesKeys.filters);
      if (json == null) {
        return;
      }
      final filters = WatchlistFilterOptions.fromJson(json);
      if (isClosed) return;
      emit(state.copyWith.filters(filters: filters, filtersApplied: true));
    } catch (e, stackTrace) {
      _log.severe('Error restoring the watchlist filters, falling back to the defaults', e, stackTrace);
      await KeyValueStore.instance().remove(WatchlistPropertiesKeys.filters);
    }
  }

  Future<void> _saveFilters(WatchlistFilterOptions filters) async {
    try {
      await KeyValueStore.instance().setJson(WatchlistPropertiesKeys.filters, filters.toJson());
    } catch (e, stackTrace) {
      _log.severe('Error saving the watchlist filters', e, stackTrace);
    }
  }

  /// Runs one paging operation at a time.
  ///
  /// A request arriving while one is in flight is remembered and replayed once it finishes. A
  /// queued reload or refresh beats a queued append, because it re-reads every page the user
  /// already has and the scroll listener will ask for the append again straight afterwards.
  Future<void> _run(_PagingOperation operation) async {
    if (_isProcessing) {
      switch (operation) {
        case _PagingOperation.reload:
        case _PagingOperation.refresh:
          _reloadRequested = true;
        case _PagingOperation.loadMore:
          _loadMoreRequested = true;
      }
      return;
    }

    _isProcessing = true;
    try {
      _PagingOperation? current = operation;
      while (current != null) {
        _reloadRequested = false;
        _loadMoreRequested = false;
        try {
          switch (current) {
            case _PagingOperation.reload:
              await _loadPages(1, 1, reset: true, appending: false);
            case _PagingOperation.refresh:
              await _loadPages(1, max(1, state.loadedPage), reset: true, appending: false);
            case _PagingOperation.loadMore:
              final nextPage = state.loadedPage + 1;
              await _loadPages(nextPage, nextPage, reset: false, appending: true);
          }
        } catch (e, stackTrace) {
          _log.severe('Error loading the watchlist', e, stackTrace);
          if (isClosed) return;
          // models is kept on purpose: a transient failure must not wipe what is on screen.
          // hasReachedEnd is left alone too, so scrolling again retries.
          emit(state.copyWith(initialLoading: false, isLoadingMore: false, hasError: true, message: e.toString()));
        }

        if (_reloadRequested) {
          // Whatever was queued, the pages already on screen are worth keeping.
          current = _PagingOperation.refresh;
        } else if (_loadMoreRequested && canLoadMore) {
          current = _PagingOperation.loadMore;
        } else {
          current = null;
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Loads pages [fromPage] to [toPage], 1 based and inclusive.
  ///
  /// [reset] rebuilds the list from scratch (a reload or a refresh); otherwise the new page is
  /// appended to what is already loaded. [appending] drives the footer's spinner. The whole list
  /// is re-marked on every call, so a refresh also picks up a pill change on an older page.
  Future<void> _loadPages(int fromPage, int toPage, {required bool reset, required bool appending}) async {
    final filters = state.filters.filters;

    if (appending) {
      if (isClosed) return;
      emit(state.copyWith(isLoadingMore: true));
    }

    final keys = reset ? <MediaKey>[] : [for (final model in state.models) model.key];
    final seen = keys.toSet();

    var loadedPage = reset ? 0 : state.loadedPage;
    var totalPages = state.totalPages;
    var reachedEnd = false;

    for (var page = fromPage; page <= toPage; page++) {
      final response = await _watchlistService.get(
        filters.itemTypes.types,
        filters.orderType,
        PageDetails(page: page, pageSize: _pageSize),
      );
      totalPages = response.totalPages;

      for (final item in response.data) {
        // Offset paging over a table a write can grow underneath us shifts rows between pages, so
        // the same item can come back on two of them. The grid needs unique keys, so the repeat
        // is dropped rather than rendered twice.
        if (seen.add(item.key)) {
          keys.add(item.key);
        }
      }

      loadedPage = page;
      if (response.data.length < _pageSize || page >= response.totalPages) {
        reachedEnd = true;
        break;
      }
    }

    final models = await _resolver.resolve(keys);
    final marks = await _marksService.load(
      showIdsForPositions: {
        for (final key in keys)
          if (key.type == ItemType.season || key.type == ItemType.episode) key.tmdbId,
      },
    );
    final marked = LibraryMarksService.mark(models, marks);

    if (isClosed) return;
    emit(
      state.copyWith(
        models: marked,
        loadedPage: loadedPage,
        totalPages: totalPages,
        initialLoading: false,
        isLoadingMore: false,
        hasReachedEnd: reachedEnd,
        hasError: false,
        message: '',
      ),
    );
  }
}
