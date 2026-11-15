import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/library/favorite_service.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model_resolver.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_filter.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_state.dart';

/// The user's favorite movies and shows, as a poster grid with a type filter.
///
/// Like the dropped shows there is no paging: the list is a handful of titles and is read whole,
/// filtered in SQL. The tiles come from the local catalogue and the user tables - never a request.
class FavoritesBloc extends Cubit<FavoritesState> {
  static final _log = Logger('FavoritesBloc');

  /// The tables the grid is built from. The favorites decide which titles are listed; the
  /// catalogue brings titles and artwork paths (the backfill); the rest are the pills.
  static const _sources = {
    DataChangeEvent.favoriteRepo,
    DataChangeEvent.catalogRepo,
    DataChangeEvent.historyRepo,
    DataChangeEvent.showStateRepo,
    DataChangeEvent.watchlistRepo,
    DataChangeEvent.userRatingRepo,
  };

  final _favoriteService = FavoriteService();
  final _resolver = PosterModelResolver();
  final _marksService = LibraryMarksService();

  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;

  bool _isProcessing = false;
  bool _reloadRequested = false;

  FavoritesBloc() : super(FavoritesState.initial()) {
    _log.finest('Bloc created');
  }

  @override
  Future<void> close() async {
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  Future<void> init() async {
    _dataChangeSubscription = DataChangeMonitor.instance().changes.listen((events) {
      if (events.any(_sources.contains)) {
        unawaited(_run());
      }
    });

    await _run();
  }

  void toggleFilterPanel(bool isExpanded) {
    emit(state.copyWith(filterPanelExpanded: isExpanded));
  }

  /// Stages a type filter in the Filters panel; nothing reloads until [applyFilter].
  void selectFilter(FavoritesFilter filter) {
    emit(state.copyWith(selectedFilter: filter));
  }

  /// Applies the staged type filter, collapses the panel and reloads. The filter is kept in the
  /// state only, never persisted.
  Future<void> applyFilter() async {
    if (state.selectedFilter == state.filter || isClosed) {
      return;
    }
    emit(state.copyWith(filter: state.selectedFilter, filterPanelExpanded: false));
    await _run();
  }

  /// Runs one load at a time; a request arriving mid-load is replayed once it finishes.
  Future<void> _run() async {
    if (_isProcessing) {
      _reloadRequested = true;
      return;
    }

    _isProcessing = true;
    try {
      do {
        _reloadRequested = false;
        try {
          await _load();
        } catch (e, stackTrace) {
          _log.severe('Error loading the favorites', e, stackTrace);
          if (isClosed) return;
          // models is kept on purpose: a transient failure must not wipe what is on screen.
          emit(state.copyWith(initialLoading: false, hasError: true, message: e.toString()));
        }
      } while (_reloadRequested && !isClosed);
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _load() async {
    final favorites = await _favoriteService.getAll(state.filter.types);
    final models = await _resolver.resolve(favorites.map((row) => row.key));
    final marks = await _marksService.load();
    final marked = LibraryMarksService.mark(models, marks);

    if (isClosed) return;
    emit(state.copyWith(models: marked, initialLoading: false, hasError: false, message: ''));
  }
}
