import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/media_ref.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/library/rating_service.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/poster/poster_model_builder.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/service/stats/stats_period.dart';
import 'package:ticketbox/service/stats/stats_service.dart';
import 'package:ticketbox/ui/pages/stats/stats_state.dart';

class StatsBloc extends Cubit<StatsState> {
  static final _log = Logger('StatsBloc');

  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;
  bool _isProcessing = false;
  bool _needsRerun = false;

  /// Bumped on every computed overview, so a titles pass still running for the previous one
  /// drops its result instead of emitting tiles the page no longer names.
  int _overviewGeneration = 0;

  StatsBloc() : super(StatsState.initial()) {
    _log.finest('Bloc created');
  }

  @override
  Future<void> close() async {
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  Future<void> init() async {
    _dataChangeSubscription = DataChangeMonitor.instance().changes.listen((events) {
      // Every number on the page is derived from the local history, ratings and show state
      // tables, so a write to any of them while the page is open recomputes the overview.
      if (events.contains(DataChangeEvent.historyRepo) ||
          events.contains(DataChangeEvent.userRatingRepo) ||
          events.contains(DataChangeEvent.showStateRepo)) {
        unawaited(_load());
        return;
      }
      // The rest only moves the pills on the highest rated tiles (watchlist, favorites) or
      // brings artwork paths with the backfill (the catalogue): re-read the titles, not the
      // numbers.
      if (events.contains(DataChangeEvent.watchlistRepo) ||
          events.contains(DataChangeEvent.favoriteRepo) ||
          events.contains(DataChangeEvent.catalogRepo)) {
        final overview = state.overview;
        if (overview != null) {
          unawaited(_loadTitles(overview, _overviewGeneration));
        }
      }
    });

    // Decided once per visit: later reloads and the Apply button keep whatever is selected.
    final period = await StatsService().defaultPeriod();
    if (isClosed) return;
    emit(state.copyWith(period: period, pendingPeriod: period));
    await _load();
  }

  /// Retry after an error, back through the full-page loading state.
  Future<void> retry() async {
    emit(state.copyWith(initialLoading: true, hasError: false));
    await _load();
  }

  void toggleFilterPanel(bool isExpanded) {
    emit(state.copyWith(filterExpanded: isExpanded));
  }

  /// Picks [period] in the filter panel without applying it.
  void stagePeriod(StatsPeriod period) {
    emit(state.copyWith(pendingPeriod: period));
  }

  /// Applies the staged period (all time or one year) and closes the panel. A real change goes
  /// through the full-page loading state - every section changes at once, so there is nothing
  /// worth keeping on screen.
  Future<void> applyPeriod() async {
    final period = state.pendingPeriod;
    if (period == state.period) {
      emit(state.copyWith(filterExpanded: false));
      return;
    }
    emit(state.copyWith(period: period, filterExpanded: false, initialLoading: true, hasError: false));
    await _load();
  }

  /// Rates a watched movie from the "Waiting for your rating" list. The page recomputes through
  /// the rating table's change event, which moves the next unrated movie up. Returns false when
  /// the write failed.
  Future<bool> rateMovie(UnratedMovie movie, int rating) async {
    final target = MarkAsWatchedTarget.movie(MovieRef(tmdbId: movie.tmdbId, title: movie.title, year: movie.year));
    try {
      await RatingService().addRating(target: target, rating: rating);
      return true;
    } catch (e, stackTrace) {
      _log.severe('Could not rate movie ${movie.tmdbId}', e, stackTrace);
      return false;
    }
  }

  /// Computes the overview over the selected period from the local library. Calls arriving
  /// while a load is in flight coalesce into a single extra run, which picks up the period
  /// selected by then.
  Future<void> _load() async {
    if (_isProcessing) {
      _needsRerun = true;
      return;
    }
    _isProcessing = true;
    try {
      do {
        _needsRerun = false;
        final period = state.period;
        try {
          final (overview, years) = await (StatsService().compute(period: period), StatsService().availableYears()).wait;
          if (isClosed) return;
          if (period != state.period) {
            // Switched while computing: the rerun queued by applyPeriod replaces this result.
            continue;
          }
          emit(state.copyWith(overview: overview, availableYears: years, initialLoading: false, hasError: false));
          unawaited(_loadTitles(overview, ++_overviewGeneration));
        } catch (e, stackTrace) {
          _log.severe('Error loading the stats page', e, stackTrace);
          if (isClosed) return;
          emit(state.copyWith(initialLoading: false, hasError: true, message: e.toString()));
        }
      } while (_needsRerun);
    } finally {
      _isProcessing = false;
    }
  }

  /// Reads the titles the overview names - the artwork of every banner and thumb, and the
  /// highest rated titles as marked poster tiles - without holding up the numbers. All local:
  /// the catalogue rows and the user tables, never a request. Entries of titles that left every
  /// section are dropped with the map; the whole thing is one query per table.
  Future<void> _loadTitles(StatsOverview overview, int generation) async {
    try {
      final (artwork, topRated) = await (StatsService().artwork(_artworkKeys(overview).toList()), _topRatedTiles(overview.topRated)).wait;
      if (isClosed || generation != _overviewGeneration) return;
      emit(state.copyWith(artwork: artwork, topRated: topRated));
    } catch (e, stackTrace) {
      // The numbers are already on screen; the page simply keeps its placeholders.
      _log.severe('Error loading the artwork and the highest rated tiles of the stats page', e, stackTrace);
    }
  }

  /// The highest rated titles as poster tiles, best first, built from their catalogue rows and
  /// marked. A title whose row is missing (not backfilled yet) still gets a tile, from what the
  /// rating row knows about it, so the rating pill and the tap keep working.
  Future<List<PosterModel>> _topRatedTiles(List<TopRatedTitle> topRated) async {
    if (topRated.isEmpty) {
      return const [];
    }
    final movieIds = [
      for (final title in topRated)
        if (title.type == ItemType.movie) title.tmdbId,
    ];
    final showIds = [
      for (final title in topRated)
        if (title.type == ItemType.show) title.tmdbId,
    ];
    final (movies, shows, marks) = await (MovieRepo().getMany(movieIds), ShowRepo().getMany(showIds), LibraryMarksService().load()).wait;
    final models = [
      for (final title in topRated)
        switch (title.type) {
          ItemType.movie when movies[title.tmdbId] != null => PosterModelBuilder.movie(movies[title.tmdbId]!),
          ItemType.show when shows[title.tmdbId] != null => PosterModelBuilder.show(shows[title.tmdbId]!),
          _ => _untrackedTile(title),
        },
    ];
    return LibraryMarksService.mark(models, marks);
  }

  static PosterModel _untrackedTile(TopRatedTitle title) {
    final name = title.title.isEmpty ? PosterModelBuilder.noTitle : title.title;
    return PosterModel(key: title.key, title: name, noPosterText: name, posterPath: null, tracked: false, rating: null);
  }

  /// Every movie and show the page shows a poster or a banner for.
  static Iterable<MediaKey> _artworkKeys(StatsOverview overview) sync* {
    final mostWatched = overview.mostWatchedShow;
    if (mostWatched != null) yield MediaKey.show(mostWatched.tmdbId);
    final crowd = overview.crowdComparison;
    if (crowd != null) {
      for (final gap in crowd.lovedMore.followedBy(crowd.lovedLess)) {
        yield MediaKey(type: gap.type, tmdbId: gap.tmdbId);
      }
    }
    for (final movie in overview.unratedMovies?.recent ?? const <UnratedMovie>[]) {
      yield MediaKey.movie(movie.tmdbId);
    }
    final firstPlay = overview.activity.firstPlay;
    if (firstPlay != null) yield firstPlay.key.showKey;
    final decades = overview.decades;
    if (decades != null) {
      yield MediaKey(type: decades.oldest.type, tmdbId: decades.oldest.tmdbId);
      yield MediaKey(type: decades.newest.type, tmdbId: decades.newest.tmdbId);
    }
    for (final item in overview.topRewatched) {
      yield MediaKey(type: item.type, tmdbId: item.tmdbId);
    }
    for (final show in overview.completion.almostThere) {
      yield MediaKey.show(show.tmdbId);
    }
  }
}
