import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/search_item_type_filter.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/debounce.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/search/search_service.dart';
import 'package:ticketbox/ui/pages/search/search_state.dart';

/// The kind of work [SearchBloc._run] is asked to do.
enum _PagingOperation {
  /// Load page one of the current query and throw away everything already loaded.
  reload,

  /// Append the page after the last loaded one.
  loadMore,
}

/// The search page: TMDB's results as in-memory tiles, stamped with the user's marks. Browsing
/// writes nothing - a result gets a catalogue row only once the user tracks it from its page -
/// so the tiles are re-marked from the user tables whenever one of them changes.
class SearchBloc extends Cubit<SearchState> {
  static final _log = Logger('SearchBloc');

  /// How long after the last keystroke the search fires.
  static const _debounceDuration = Duration(milliseconds: 500);

  final _searchService = SearchService();
  final _marksService = LibraryMarksService();

  /// [Debounce]'s registry is static, so the tag is instance scoped to keep two page instances
  /// (or a closed and a fresh one) from cancelling each other's timers.
  late final String _debounceTag = 'search_query_$hashCode';

  /// The latest text the field reported, which the debounce has not necessarily applied yet.
  String _pendingQuery = '';

  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;
  bool _isProcessing = false;
  bool _reloadRequested = false;
  bool _loadMoreRequested = false;

  /// Bumped whenever the result list is rebuilt, so that a page fetched for results that are
  /// no longer on screen is dropped instead of appended to the new ones.
  int _generation = 0;

  SearchBloc() : super(SearchState.initial()) {
    _log.finest('Bloc created');
    _dataChangeSubscription = DataChangeMonitor.instance().changes.listen((events) {
      // The user can mark a result from its details page and come back: the tiles re-read their
      // pills from the user tables. The catalogue decides which tiles count as tracked.
      if (events.contains(DataChangeEvent.historyRepo) ||
          events.contains(DataChangeEvent.showStateRepo) ||
          events.contains(DataChangeEvent.watchlistRepo) ||
          events.contains(DataChangeEvent.userRatingRepo) ||
          events.contains(DataChangeEvent.favoriteRepo) ||
          events.contains(DataChangeEvent.catalogRepo)) {
        unawaited(_remark());
      }
    });
  }

  /// Whether a further page can be appended.
  ///
  /// Checked synchronously before the first await of [loadNextPage] because the scroll listener
  /// calls it on very nearly every scrolled pixel.
  bool get canLoadMore => state.hasQuery && !state.initialLoading && !state.isLoadingMore && !state.hasReachedEnd;

  /// The as-you-type entry point. All text input funnels through here and [submit], so switching
  /// the page to submit-only search would mean deleting one Debounce line.
  void onQueryChanged(String text) {
    _pendingQuery = text;
    Debounce.debounce(_debounceTag, _debounceDuration, () => unawaited(_applyQuery()));
  }

  /// The keyboard's search action: searches immediately, cancelling any pending debounce.
  void submit() {
    Debounce.cancel(_debounceTag);
    unawaited(_applyQuery());
  }

  /// Applies [filter] and rebuilds the results from scratch: pages fetched with the previous
  /// type restriction cannot be appended to.
  Future<void> updateFilter(SearchItemTypeFilter filter) async {
    if (state.filter == filter) {
      return;
    }
    emit(_resetResults(state.copyWith(filter: filter), loading: state.hasQuery));
    if (state.hasQuery) {
      await _run(_PagingOperation.reload);
    }
  }

  Future<void> loadNextPage() async {
    if (!canLoadMore) {
      return;
    }
    await _run(_PagingOperation.loadMore);
  }

  /// Reloads the current query after an error left the list empty.
  Future<void> retry() async {
    await _run(_PagingOperation.reload);
  }

  @override
  Future<void> close() async {
    Debounce.cancel(_debounceTag);
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  /// Makes [_pendingQuery] the searched query. Emits the reset state *before* asking [_run] for
  /// the reload, so a load already in flight sees the query change and discards its stale result.
  Future<void> _applyQuery() async {
    if (isClosed) {
      return;
    }
    final query = _pendingQuery.trim();
    if (query == state.query && !state.hasError) {
      // Nothing actually changed (a trailing-space edit, or blurring the field) - keep the
      // results instead of refetching them. An errored page does get its retry.
      return;
    }
    emit(_resetResults(state.copyWith(query: query), loading: query.isNotEmpty));
    if (query.isEmpty) {
      // The emit above already shows the idle hint; a load still in flight is now stale.
      _generation++;
      return;
    }
    await _run(_PagingOperation.reload);
  }

  /// The state with everything result-shaped thrown away, ready for page one of a new search.
  SearchState _resetResults(SearchState base, {required bool loading}) {
    return base.copyWith(
      initialLoading: loading,
      models: [],
      loadedPage: 0,
      totalPages: -1,
      isLoadingMore: false,
      hasReachedEnd: false,
      hasError: false,
      message: '',
    );
  }

  /// Runs one paging operation at a time.
  ///
  /// A request arriving while one is in flight is remembered and replayed once it finishes. A
  /// queued reload beats a queued append, because the scroll listener will ask for the append
  /// again straight afterwards anyway. The replayed reload reads the query and filter off the
  /// state when it runs, so it always searches the latest values.
  Future<void> _run(_PagingOperation operation) async {
    if (_isProcessing) {
      switch (operation) {
        case _PagingOperation.reload:
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
              await _loadPage(1, reset: true, appending: false);
            case _PagingOperation.loadMore:
              await _loadPage(state.loadedPage + 1, reset: false, appending: true);
          }
        } catch (e, stackTrace) {
          _log.severe('Error loading the search results', e, stackTrace);
          if (isClosed) return;
          // models is kept on purpose: a transient failure must not wipe what is on screen.
          // hasReachedEnd is left alone too, so scrolling again retries.
          emit(state.copyWith(initialLoading: false, isLoadingMore: false, hasError: true, message: e.toString()));
        }

        if (_reloadRequested) {
          current = _PagingOperation.reload;
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

  /// Loads one 1 based [page] of the current query.
  ///
  /// [reset] rebuilds the tile list from scratch and bumps the generation, so a page still in
  /// flight for the previous results is dropped. [appending] drives the footer's spinner.
  Future<void> _loadPage(int page, {required bool reset, required bool appending}) async {
    final generation = reset ? ++_generation : _generation;
    final query = state.query;
    final filter = state.filter;
    if (query.isEmpty) {
      // Cleared while this operation was queued; _applyQuery already emitted the idle state.
      return;
    }

    if (appending) {
      if (isClosed) return;
      emit(state.copyWith(isLoadingMore: true));
    }

    final (response, marks) = await (_searchService.search(query, filter, page), _marksService.load()).wait;
    if (_isStale(generation, query, filter)) return;

    final models = reset ? <PosterModel>[] : [...state.models];
    final seen = <MediaKey>{for (final model in models) model.key};
    final added = <PosterModel>[];
    for (final entry in response.items) {
      // Relevance shifts between page fetches - the same item can come back on two of them. The
      // grid needs unique keys, so the repeat is dropped rather than rendered twice.
      if (!seen.add(entry.key)) {
        continue;
      }
      added.add(entry.toPosterModel());
    }
    models.addAll(LibraryMarksService.mark(added, marks));

    emit(
      state.copyWith(
        models: models,
        loadedPage: page,
        totalPages: response.totalPages,
        initialLoading: false,
        isLoadingMore: false,
        hasReachedEnd: page >= response.totalPages || response.items.isEmpty,
        hasError: false,
        message: '',
      ),
    );
  }

  /// Whether the page being loaded no longer matches what is on screen: the cubit closed, a reset
  /// superseded [generation], or a new query or filter was emitted while the load was in flight
  /// (its own reload is already queued behind this one).
  bool _isStale(int generation, String query, SearchItemTypeFilter filter) {
    return isClosed || generation != _generation || query != state.query || filter != state.filter;
  }

  /// Re-stamps the tiles on screen with the user's current marks. The tracked flag is re-derived
  /// too: a browsed tile is only ever tracked through the catalogue, so one the user just
  /// untracked drops its flag again.
  Future<void> _remark() async {
    if (state.models.isEmpty) {
      return;
    }
    try {
      final generation = _generation;
      final marks = await _marksService.load();
      if (isClosed || generation != _generation || state.models.isEmpty) return;
      emit(state.copyWith(models: _remarked(state.models, marks)));
    } catch (e, stackTrace) {
      _log.severe('Error re-marking the search results', e, stackTrace);
    }
  }

  /// [models] with their marks and tracked flag rebuilt from [marks] alone.
  static List<PosterModel> _remarked(List<PosterModel> models, LibraryMarkSets marks) {
    return LibraryMarksService.mark([for (final model in models) model.copyWith(tracked: false)], marks);
  }
}
