import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/debounce.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/check_in/check_in_state.dart';

/// Tracks the check-in the user currently has running, if any.
///
/// A single app-wide instance, provided from `main.dart` — the check-in heads-up
/// banner renders on several pages at once (dashboard, show, season, episode) and
/// they must all read the same state. It is also why this cannot be per-page: the
/// heartbeat below is keyed on the *global* [Debounce] key [_debouncerKey], so two
/// live instances would keep cancelling each other's timer.
class CheckInBloc extends Cubit<CheckInState> {
  static final _log = Logger('CheckInBloc');

  static const String _debouncerKey = 'CheckIn_Heart_Beat';

  StreamSubscription<void>? _stream;

  CheckInBloc._() : super(CheckInState.initial());

  static CheckInBloc instance() {
    if (GetIt.I.isRegistered<CheckInBloc>()) {
      return GetIt.I.get<CheckInBloc>();
    }

    _log.info('New instance created');
    final bloc = CheckInBloc._();
    GetIt.I.registerSingleton<CheckInBloc>(bloc);
    bloc._init();
    return bloc;
  }

  @override
  Future<void> close() async {
    await _stream?.cancel();
    Debounce.cancel(_debouncerKey);
    await super.close();
  }

  void _init() {
    // The stream is only a change signal — the query behind it bakes its
    // `watchedAt > now` bound in at build time, so the rows are re-read fresh on
    // every event instead of being taken from the event itself.
    _stream = HistoryRepo().watchCurrentCheckInItems().listen((_) => _checkInTriggered());
  }

  void _periodicCheck() {
    if (state.checkInItem == null) {
      return;
    }

    unawaited(_userIsWatching());
  }

  Future<void> _checkInTriggered() async {
    final repo = HistoryRepo();
    final items = await repo.getCurrentCheckInItems();
    if (items.isEmpty) {
      _userNotWatching();
      return;
    }
    final checkedInItem = items.first;
    if (state.checkInItem != null && state.checkInItem!.historyId == checkedInItem.historyId) {
      // Same check-in as the one already on screen: nothing to re-resolve, but the
      // heartbeat is re-armed so the progress keeps advancing even if the previous
      // chain was cancelled.
      await _userIsWatching();
      return;
    }

    CheckInState tempState = state.copyWith(isWatching: true, checkInItem: checkedInItem, tmdbId: checkedInItem.tmdbId);

    // A check-in is always on a tracked title, so the rows are local; a missing one (the title
    // was swept meanwhile) only costs the banner its texts.
    if (ItemType.episode == checkedInItem.type) {
      final show = await ShowRepo().get(checkedInItem.tmdbId);
      final details = await EpisodeRepo().get(checkedInItem.tmdbId, checkedInItem.season, checkedInItem.episode);
      final startAt = await _calculateEpisodeStartedAt(details, checkedInItem.watchedAt);
      tempState = tempState.copyWith(
        title: show?.title ?? '-No show title available-',
        subtitle: _episodeSubtitle(checkedInItem.season, checkedInItem.episode, details?.title),
        startedAt: startAt,
        endAt: checkedInItem.watchedAt,
        type: ItemType.episode,
        season: checkedInItem.season,
        episode: checkedInItem.episode,
      );
    } else {
      final movie = await MovieRepo().get(checkedInItem.tmdbId);
      final startAt = await _calculateMovieStartedAt(movie, checkedInItem.watchedAt);
      tempState = tempState.copyWith(
        title: movie?.title ?? '-No movie title available-',
        subtitle: '',
        startedAt: startAt,
        endAt: checkedInItem.watchedAt,
        type: ItemType.movie,
        season: null,
        episode: null,
      );
    }

    if (isClosed) {
      return;
    }
    emit(tempState);
    await _userIsWatching();
  }

  void _userNotWatching() {
    if (!state.isWatching || isClosed) {
      return;
    }

    Debounce.cancel(_debouncerKey);
    emit(
      state.copyWith(
        isWatching: false,
        title: '',
        subtitle: '',
        percentageWatched: 0,
        checkInItem: null,
        tmdbId: null,
        season: null,
        episode: null,
        startedAt: DateTime.now(),
        endAt: DateTime.now(),
      ),
    );
  }

  Future<void> _userIsWatching() async {
    final double watchPercentage = _calculateWatchPercentage(state.startedAt, state.endAt);

    if (watchPercentage == -1 || watchPercentage > 99) {
      // The row stays: once its end instant has passed it is simply a finished play.
      _userNotWatching();
      return;
    }

    Debounce.debounce(_debouncerKey, const Duration(seconds: 10), _periodicCheck);

    if (isClosed) {
      return;
    }
    emit(state.copyWith(isWatching: true, percentageWatched: watchPercentage));
  }

  double _calculateWatchPercentage(DateTime startAt, DateTime endAt) {
    final currentTime = DateTime.now().toUtc().millisecondsSinceEpoch;
    final totalLength = endAt.millisecondsSinceEpoch - startAt.millisecondsSinceEpoch;
    final currentLength = currentTime - startAt.millisecondsSinceEpoch;

    if (currentLength <= 0 || totalLength <= 0) {
      return -1;
    }

    return currentLength * 100 / totalLength;
  }

  /// The banner's second line: `S3xE9 The Rains of Castamere`.
  String _episodeSubtitle(int season, int episode, String? title) {
    final composer = StringBuffer();
    composer.write(_seasonShortTitle(season));
    composer.write('xE');
    composer.write(episode.toString());
    if (title != null && title.isNotEmpty) {
      composer.write(' ');
      composer.write(title);
    }
    return composer.toString();
  }

  String _seasonShortTitle(int season) {
    if (season == 0) {
      return 'Specials';
    } else {
      return 'S$season';
    }
  }

  Future<DateTime> _calculateMovieStartedAt(MovieEntity? movie, DateTime watchedAt) async {
    final int movieRuntime;

    if (movie == null || movie.runtime == null || movie.runtime == 0) {
      movieRuntime = 120;
    } else {
      movieRuntime = movie.runtime!;
    }

    final endsAt = watchedAt;
    final startsAt = endsAt.subtract(Duration(minutes: movieRuntime)).toUtc();
    return startsAt;
  }

  Future<DateTime> _calculateEpisodeStartedAt(EpisodeEntity? episode, DateTime watchedAt) async {
    final int episodeRuntime;

    if (episode == null || episode.runtime == null || episode.runtime == 0) {
      episodeRuntime = 40;
    } else {
      episodeRuntime = episode.runtime!;
    }

    final endsAt = watchedAt;
    final startsAt = endsAt.subtract(Duration(minutes: episodeRuntime)).toUtc();
    return startsAt;
  }
}
