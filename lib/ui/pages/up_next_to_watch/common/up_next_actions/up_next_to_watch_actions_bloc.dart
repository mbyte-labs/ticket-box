import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/title_builder.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/up_next_actions/up_next_to_watch_actions_state.dart';

/// The long-press sheet of an Up Next tile. An Up Next row is always a tracked show, so the show
/// and episode rows are local.
class UpNextToWatchActionsBloc extends Cubit<UpNextToWatchActionsState> {
  static final _log = Logger('UpNextToWatchActionsBloc');

  UpNextToWatchActionsBloc(PosterModel details) : super(UpNextToWatchActionsState.initial()) {
    _log.finest('Bloc created');
    _init(details);
  }

  Future<void> _init(PosterModel details) async {
    try {
      _log.finest('Initializing bloc with ${details.key}');
      final newState = await _buildInitialDetails(details);
      if (isClosed) return;
      emit(newState);
    } catch (e, stacktrace) {
      _log.severe('Failed to initialize', e, stacktrace);
    }
  }

  Future<UpNextToWatchActionsState> _buildInitialDetails(PosterModel details) async {
    final key = details.key;
    final show = await ShowRepo().get(key.tmdbId);
    final episode = await EpisodeRepo().get(key.tmdbId, key.season, key.episode);
    if (show == null || episode == null) {
      throw StateError('${details.key} is not in the library');
    }

    return UpNextToWatchActionsState(
      initialLoading: false,
      title: ConfirmationTitleBuilder.episodeTitle(episode.toRef()),
      showTitle: ConfirmationTitleBuilder.showTitle(show.toRef()),
      seasonPremiere: details.seasonPremiere,
      seasonFinale: details.seasonFinale,
      seriesFinale: details.seriesFinale,
      midSeasonFinale: details.midSeasonFinale,
      rating: 0,
      show: show,
      episode: episode,
    );
  }
}
