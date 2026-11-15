import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/discover_mode.dart';
import 'package:ticketbox/common/model/filter/genres/genre.dart';
import 'package:ticketbox/common/model/filter/genres/genres.dart';
import 'package:ticketbox/common/model/filter/year/year_range.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/discover_properties_keys.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/discover/discover_service.dart';
import 'package:ticketbox/service/genres/genres_service.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/pages/discover/discover_state.dart';

/// The kind of work [DiscoverBloc._run] is asked to do.
///
/// Unlike the watch history there is no refresh operation: discover data is user independent,
/// nothing syncs it underneath the page, so the loaded pages never go stale while it is open.
enum _PagingOperation {
  /// Load page one of the active list and throw away everything it already had.
  reload,

  /// Append the page after the last one the active list loaded.
  loadMore,
}

/// The Discover page: one grid, a Movies / Shows switch that keeps a list per type, and a filter
/// panel (list, minimum votes, rating, years, per-type genres) that applies to both.
///
/// The tiles are built in memory from TMDB's list payload and stamped with the user's marks.
/// Browsing writes nothing - a title gets a catalogue row only once the user tracks it from its
/// page - so the tiles are re-marked from the user tables whenever one of them changes.
class DiscoverBloc extends Cubit<DiscoverState> {
  static final _log = Logger('DiscoverBloc');

  final _discoverService = DiscoverService();
  final _marksService = LibraryMarksService();

  /// The list the route asked for, applied over the persisted one for this visit only.
  final DiscoverMode? _routeMode;

  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;
  bool _isProcessing = false;
  bool _reloadRequested = false;
  bool _loadMoreRequested = false;

  DiscoverBloc({ItemType initialType = ItemType.movie, DiscoverMode? routeMode})
    : _routeMode = routeMode,
      super(DiscoverState.initial(initialType)) {
    _log.finest('Bloc created');
  }

  @override
  Future<void> close() async {
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  /// Whether a further page can be appended to the active list.
  ///
  /// Checked synchronously before the first await of [loadNextPage] because the scroll listener
  /// calls it on very nearly every scrolled pixel.
  bool get canLoadMore => !state.active.initialLoading && !state.active.isLoadingMore && !state.active.hasReachedEnd;

  Future<void> init() async {
    _dataChangeSubscription = DataChangeMonitor.instance().changes.listen((events) {
      // The user can mark a title from its details page and come back: the tiles re-read their
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

    await _restoreFilters();
    if (_routeMode != null) {
      // Not saved: a "trending shows" link must not rewrite the list the user chose for next time.
      if (isClosed) return;
      emit(state.copyWith.filters.filters(mode: _routeMode));
    }
    await _loadAvailableGenres();
    await _run(_PagingOperation.reload);
  }

  Future<void> loadNextPage() async {
    if (!canLoadMore) {
      return;
    }
    await _run(_PagingOperation.loadMore);
  }

  /// Shows [type]'s list, loading its first page if it has never been loaded. A list that already
  /// has pages is shown as it was - these lists do not move fast enough for a re-fetch per toggle
  /// to buy anything.
  Future<void> switchType(ItemType type) async {
    if (state.itemType == type) {
      return;
    }
    emit(state.copyWith(itemType: type));
    if (state.active.loadedPage == 0) {
      await _run(_PagingOperation.reload);
    }
  }

  /// Reloads the active list after an error left it empty.
  Future<void> retry() async {
    await _run(_PagingOperation.reload);
  }

  Future<void> toggleFilterPanel(bool isExpanded) async {
    emit(state.copyWith.filters(containerExpanded: isExpanded));
    // A fresh install can open the panel before the genres have been fetched; retrying on every
    // expand makes them show up as soon as TMDB answers, without an app restart.
    if (isExpanded && (state.filters.availableMovieGenres.isEmpty || state.filters.availableShowGenres.isEmpty)) {
      await _loadAvailableGenres();
    }
  }

  void updateMode(DiscoverMode mode) {
    emit(state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(mode: mode));
  }

  void updateMinVoteCount(int minVoteCount) {
    emit(state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(minVoteCount: minVoteCount));
  }

  void updateRatingRange(double minRating, double maxRating) {
    final range = state.filters.filters.ratingRange.copyWith(minRange: minRating, maxRange: maxRating);
    emit(state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(ratingRange: range));
  }

  void updateYearRange(int minYear, int maxYear) {
    final range = state.filters.filters.yearRange.copyWith(minYear: minYear, maxYear: maxYear);
    emit(state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(yearRange: range));
  }

  /// Toggles [genre] in the active type's selection; the other type's selection is untouched.
  void toggleGenre(Genre genre) {
    final type = state.itemType;
    final selected = [...state.filters.filters.selectedGenresFor(type)];
    if (selected.any((g) => g.id == genre.id)) {
      selected.removeWhere((g) => g.id == genre.id);
    } else {
      selected.add(genre);
    }
    emit(state.copyWith.filters(filtersApplied: false, filters: state.filters.filters.withSelectedGenres(type, selected)));
  }

  /// Applies the panel's options: both lists are rebuilt from scratch, because pages fetched with
  /// the previous options cannot be appended to. The inactive list ends up at page 0, which is
  /// exactly what makes [switchType] fetch it - with the new options - on the next toggle.
  Future<void> updateFilter() async {
    final newState = state
        .copyWith(movies: DiscoverListState.initial(), shows: DiscoverListState.initial())
        .copyWith
        .filters(filtersApplied: true, containerExpanded: false);
    emit(newState);
    unawaited(_saveFilters(newState.filters.filters));
    await _run(_PagingOperation.reload);
  }

  /// Restores the filters that were applied the last time the page was used. A stored value that
  /// can no longer be parsed is dropped instead of breaking the page, which then falls back to
  /// the defaults.
  Future<void> _restoreFilters() async {
    try {
      final json = await KeyValueStore.instance().getJson(DiscoverPropertiesKeys.filters);
      if (json == null) {
        return;
      }
      final restored = DiscoverFilterOptions.fromJson(json);
      // The stored allowed year bounds were frozen when the filters were saved; a save from last
      // year would cap the slider below the current upper bound. Rebase them and keep the picked
      // range inside.
      final freshYearBounds = FilterYearRange.initial();
      final yearRange = restored.yearRange.copyWith(
        minAllowedYear: freshYearBounds.minAllowedYear,
        maxAllowedYear: freshYearBounds.maxAllowedYear,
        minYear: restored.yearRange.minYear.clamp(freshYearBounds.minAllowedYear, freshYearBounds.maxAllowedYear),
        maxYear: restored.yearRange.maxYear.clamp(freshYearBounds.minAllowedYear, freshYearBounds.maxAllowedYear),
      );
      if (isClosed) return;
      emit(state.copyWith.filters(filtersApplied: true, filters: restored.copyWith(yearRange: yearRange)));
    } catch (e, stackTrace) {
      _log.severe('Error restoring the discover filters, falling back to the defaults', e, stackTrace);
      await KeyValueStore.instance().remove(DiscoverPropertiesKeys.filters);
    }
  }

  Future<void> _saveFilters(DiscoverFilterOptions filters) async {
    try {
      await KeyValueStore.instance().setJson(DiscoverPropertiesKeys.filters, filters.toJson());
    } catch (e, stackTrace) {
      _log.severe('Error saving the discover filters', e, stackTrace);
    }
  }

  /// Fills the panel's genre catalogues from the local database. A failure only costs that type's
  /// genre section, so the page keeps working with an empty catalogue.
  Future<void> _loadAvailableGenres() async {
    final catalogues = await Future.wait([_genresOf(ItemType.movie), _genresOf(ItemType.show)]);
    if (isClosed) return;
    emit(state.copyWith.filters(availableMovieGenres: catalogues[0], availableShowGenres: catalogues[1]));
  }

  Future<List<Genre>> _genresOf(ItemType type) async {
    try {
      final entities = await GenresService().getByType(type);
      return entities.map((e) => Genre(id: e.id, name: e.name)).toList()..sort((a, b) => a.name.compareTo(b.name));
    } catch (e, stackTrace) {
      _log.severe('Error loading the ${type.name} genres for the filter panel', e, stackTrace);
      return const [];
    }
  }

  /// Runs one paging operation at a time.
  ///
  /// A request arriving while one is in flight is remembered and replayed once it finishes. A
  /// queued reload beats a queued append, because the scroll listener will ask for the append
  /// again straight afterwards anyway. Every operation targets the type that is active when it
  /// starts, so a mid-load toggle cannot write one list's pages into the other.
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
        final type = state.itemType;
        try {
          switch (current) {
            case _PagingOperation.reload:
              await _loadPage(type, 1, reset: true, appending: false);
            case _PagingOperation.loadMore:
              final nextPage = state.listFor(type).loadedPage + 1;
              await _loadPage(type, nextPage, reset: false, appending: true);
          }
        } catch (e, stackTrace) {
          _log.severe('Error loading the discover ${type.name}s', e, stackTrace);
          if (isClosed) return;
          // models is kept on purpose: a transient failure must not wipe what is on screen.
          // hasReachedEnd is left alone too, so scrolling again retries.
          _emitList(type, state.listFor(type).copyWith(initialLoading: false, isLoadingMore: false, hasError: true, message: e.toString()));
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

  /// Loads one 1 based [page] of [type]'s list, with the options the panel last applied.
  ///
  /// [reset] rebuilds the tile list from scratch; [appending] drives the footer's spinner.
  Future<void> _loadPage(ItemType type, int page, {required bool reset, required bool appending}) async {
    if (appending) {
      if (isClosed) return;
      _emitList(type, state.listFor(type).copyWith(isLoadingMore: true));
    }

    final options = state.filters.filters;
    final (response, marks) = await (
      _discoverService.getPage(
        type,
        options.mode,
        page,
        minVoteCount: options.minVoteCount,
        ratingRange: options.ratingRange,
        yearRange: options.yearRange,
        genres: FilterGenres(availableGenres: const [], selectedGenres: options.selectedGenresFor(type)),
      ),
      _marksService.load(),
    ).wait;
    if (isClosed) return;

    final current = state.listFor(type);
    final models = reset ? <PosterModel>[] : [...current.models];
    final seen = <MediaKey>{for (final model in models) model.key};
    final added = <PosterModel>[];
    for (final entry in response.items) {
      // The lists shift between page fetches - a title climbing the ranks comes back on two of
      // them. The grid needs unique keys, so the repeat is dropped rather than rendered twice.
      if (!seen.add(entry.key)) {
        continue;
      }
      added.add(entry.toPosterModel());
    }
    models.addAll(LibraryMarksService.mark(added, marks));

    _emitList(
      type,
      current.copyWith(
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

  /// Re-stamps both lists' tiles with the user's current marks. The tracked flag is re-derived
  /// too: a browsed tile is only ever tracked through the catalogue, so one the user just
  /// untracked drops its flag again.
  Future<void> _remark() async {
    if (state.movies.models.isEmpty && state.shows.models.isEmpty) {
      return;
    }
    try {
      final marks = await _marksService.load();
      if (isClosed) return;
      emit(
        state.copyWith(
          movies: state.movies.copyWith(models: _remarked(state.movies.models, marks)),
          shows: state.shows.copyWith(models: _remarked(state.shows.models, marks)),
        ),
      );
    } catch (e, stackTrace) {
      _log.severe('Error re-marking the discover lists', e, stackTrace);
    }
  }

  /// [models] with their marks and tracked flag rebuilt from [marks] alone.
  static List<PosterModel> _remarked(List<PosterModel> models, LibraryMarkSets marks) {
    return LibraryMarksService.mark([for (final model in models) model.copyWith(tracked: false)], marks);
  }

  void _emitList(ItemType type, DiscoverListState list) {
    if (isClosed) return;
    emit(type == ItemType.movie ? state.copyWith(movies: list) : state.copyWith(shows: list));
  }
}
