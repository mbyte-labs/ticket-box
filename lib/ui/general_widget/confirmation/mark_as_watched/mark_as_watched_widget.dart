import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/date_parser.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/watched_at_options.dart';
import 'package:ticketbox/service/library/check_in_service.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/button_wrapper.dart';
import 'package:ticketbox/ui/common/buton/check_in_btn.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';
import 'package:ticketbox/ui/common/buton/mark_as_watched_btn.dart';
import 'package:ticketbox/ui/common/loading/confirmation_loading.dart';
import 'package:ticketbox/ui/general_widget/confirmation/mark_as_watched/mark_as_watched_bloc.dart';
import 'package:ticketbox/ui/general_widget/confirmation/mark_as_watched/mark_as_watched_state.dart';
import 'package:ticketbox/ui/general_widget/confirmation/mark_as_watched/mark_as_watched_worker.dart';
import 'package:ticketbox/ui/general_widget/confirmation/select_rating_widget.dart';
import 'package:ticketbox/ui/general_widget/date_and_time_picker.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/check_in/check_in_bloc.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/check_in/check_in_state.dart';

/// Bottom-sheet confirmation for marking a show, season, episode or movie as watched: pick the
/// watched-at date, optionally rate it, then confirm.
///
/// For the two types that can be checked into — an episode and a movie — the sheet offers a second,
/// mutually exclusive way out: instead of logging a finished play, start a live check-in. It sits
/// below the confirm button because logging a play is the common case, and it disappears while a
/// check-in is already running, since only one can be open at a time.
class MarkAsWatchedWidget {
  const MarkAsWatchedWidget._();

  static void modal(BuildContext context, MarkAsWatchedTarget target) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        return BlocProvider(
          lazy: false,
          create: (_) => MarkAsWatchedBloc(target),
          child: SizedBox(
            // The sheet is a fixed height, so the check-in button needs its own room or it starts
            // out below the fold, and a target without the rating selector gives its room back.
            height: ScreenSizeUtil.calculateSize(400 + (target.supportsCheckIn ? 70 : 0) - (target.supportsRating ? 0 : 85)),
            child: Padding(
              padding: ScreenSizeUtil.fromLTRB(15, 20, 15, 0),
              child: Column(
                children: [
                  Text(target.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    target.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                  ),
                  const Expanded(child: _ConfirmationBodyWidget()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConfirmationBodyWidget extends StatelessWidget {
  const _ConfirmationBodyWidget();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MarkAsWatchedBloc, MarkAsWatchedState>(
      buildWhen: (prev, curr) => prev.isInitialized != curr.isInitialized || prev.isLoading != curr.isLoading,
      builder: (context, state) {
        if (!state.isInitialized || state.isLoading) {
          return const Center(child: ConfirmationLoadingWidget());
        }
        return const SingleChildScrollView(child: _ConfirmationDetailsWidget());
      },
    );
  }
}

class _ConfirmationDetailsWidget extends StatelessWidget {
  const _ConfirmationDetailsWidget();

  @override
  Widget build(BuildContext context) {
    // Seasons are not rated directly (their score is the episode average), so no selector there.
    final supportsRating = context.read<MarkAsWatchedBloc>().state.target.supportsRating;

    return Column(
      children: [
        const SizedBox(height: 20),
        const Text('Watched at:', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 10),
        const _SelectWatchedAt(),
        const SizedBox(height: 24),
        if (supportsRating) ...[
          ConfirmationSelectRating(onRatingUpdate: (rating) => context.read<MarkAsWatchedBloc>().setRating(rating)),
          const SizedBox(height: 10),
          BlocBuilder<MarkAsWatchedBloc, MarkAsWatchedState>(
            buildWhen: (prev, curr) => prev.rating != curr.rating,
            builder: (context, state) =>
                Text('Rating: ${state.rating.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
        const _ConfirmBtnWidget(),
        const _CheckInBtnWidget(),
      ],
    );
  }
}

class _SelectWatchedAt extends StatelessWidget {
  const _SelectWatchedAt();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MarkAsWatchedBloc, MarkAsWatchedState>(
      buildWhen: (prev, curr) => prev.selectedDateType != curr.selectedDateType || prev.customWatchTime != curr.customWatchTime,
      builder: (context, state) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            _WatchedAtBtn(type: WatchedConfirmationDateSelect.rightNow, currentState: state),
            // A show's or season's own release date differs from the air dates of the episodes it
            // covers, so both are offered there. For a single episode they are the same thing.
            if (state.target.spansMultipleEpisodes)
              _WatchedAtBtn(type: WatchedConfirmationDateSelect.episodeReleaseDate, currentState: state)
            else
              _WatchedAtBtn(type: WatchedConfirmationDateSelect.releaseDate, currentState: state),
            _WatchedAtBtn(type: WatchedConfirmationDateSelect.custom, currentState: state),
          ],
        );
      },
    );
  }
}

class _WatchedAtBtn extends StatelessWidget {
  final WatchedConfirmationDateSelect type;
  final MarkAsWatchedState currentState;

  const _WatchedAtBtn({required this.type, required this.currentState});

  @override
  Widget build(BuildContext context) {
    final isSelected = currentState.selectedDateType == type;
    final bloc = context.read<MarkAsWatchedBloc>();

    final buttonConfig = _getButtonConfig(context, bloc);
    return FilterButton(text: buttonConfig.text, selected: isSelected, onPress: buttonConfig.onPress);
  }

  _ButtonConfig _getButtonConfig(BuildContext context, MarkAsWatchedBloc bloc) {
    switch (type) {
      case WatchedConfirmationDateSelect.rightNow:
        return _ButtonConfig(text: 'Right Now', onPress: () => bloc.setWatchedType(type, null));
      case WatchedConfirmationDateSelect.releaseDate:
        return _ButtonConfig(text: 'Release Date', onPress: () => bloc.setWatchedType(type, null));
      case WatchedConfirmationDateSelect.seasonReleaseDate:
        return _ButtonConfig(text: 'Season Release Date', onPress: () => bloc.setWatchedType(type, null));
      case WatchedConfirmationDateSelect.episodeReleaseDate:
        return _ButtonConfig(text: 'Episode Release Dates', onPress: () => bloc.setWatchedType(type, null));
      case WatchedConfirmationDateSelect.custom:
        return _ButtonConfig(
          text: _getCustomDateText(MediaQuery.alwaysUse24HourFormatOf(context), currentState.customWatchTime),
          onPress: () => _pickDateTime(context, bloc),
        );
    }
  }

  String _getCustomDateText(bool use24H, DateTime? customTime) {
    if (customTime == null) return 'Custom Date';
    final dateStyle = DateParser.getPreferedDateOrder('dd', 'MM', 'yyyy');
    final hourStyle = DateParser.getHourFormat(use24H);
    return DateParser.dateToString(customTime, '$hourStyle ${dateStyle.item1}/${dateStyle.item2}/${dateStyle.item3}');
  }

  Future<void> _pickDateTime(BuildContext context, MarkAsWatchedBloc bloc) async {
    final picked = await DateAndTimePicker().dateAndTimePicker(context, currentState.customWatchTime);
    if (picked != null) {
      await bloc.setWatchedType(WatchedConfirmationDateSelect.custom, picked);
    }
  }
}

class _ConfirmBtnWidget extends StatelessWidget {
  const _ConfirmBtnWidget();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MarkAsWatchedBloc, MarkAsWatchedState>(
      buildWhen: (prev, curr) => prev.rating != curr.rating,
      builder: (context, state) {
        return ConfirmationButtonWrapper.wrapButton(
          MarkAsWatchedButton(
            includeRateTxt: state.rating > 0,
            isHollow: state.rating == 0,
            onPressed: () {
              final bloc = context.read<MarkAsWatchedBloc>();
              final messenger = ScaffoldMessenger.maybeOf(context);
              context.pop();
              unawaited(
                bloc.markAsWatched().then((outcome) {
                  final message = switch (outcome) {
                    MarkAsWatchedOutcome.done => null,
                    MarkAsWatchedOutcome.needsConnection => 'Needs a connection to add this title to your library',
                    MarkAsWatchedOutcome.gone => 'This title no longer exists on TMDB',
                    MarkAsWatchedOutcome.failed => 'Could not mark it as watched',
                  };
                  if (message != null) {
                    messenger?.showSnackBar(SnackBar(content: Text(message)));
                  }
                }),
              );
            },
          ),
        );
      },
    );
  }
}

/// The check-in escape hatch, rendered only for the types that support it.
///
/// Hidden outright — rather than disabled — while another check-in is running: only one
/// check-in can be open at a time, and the check-in banner on the page behind this sheet is already
/// showing the user the one they have.
class _CheckInBtnWidget extends StatelessWidget {
  const _CheckInBtnWidget();

  @override
  Widget build(BuildContext context) {
    if (!context.read<MarkAsWatchedBloc>().state.target.supportsCheckIn) return const SizedBox.shrink();

    return BlocBuilder<CheckInBloc, CheckInState>(
      buildWhen: (prev, curr) => prev.isWatching != curr.isWatching,
      builder: (context, checkInState) {
        if (checkInState.isWatching) return const SizedBox.shrink();

        return Padding(
          padding: ScreenSizeUtil.fromLTRB(0, 12, 0, 0),
          child: ConfirmationButtonWrapper.wrapButton(
            CheckInButton(
              onPressed: () {
                final bloc = context.read<MarkAsWatchedBloc>();
                final messenger = ScaffoldMessenger.maybeOf(context);
                context.pop();
                unawaited(
                  bloc.checkIn().then((outcome) {
                    final message = switch (outcome) {
                      null => 'Needs a connection to add this title to your library',
                      CheckInOutcome.alreadyActive => 'Another check-in is already running',
                      CheckInOutcome.started || CheckInOutcome.unsupportedType => null,
                    };
                    if (message != null) {
                      messenger?.showSnackBar(SnackBar(content: Text(message)));
                    }
                  }),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ButtonConfig {
  final String text;
  final VoidCallback onPress;

  const _ButtonConfig({required this.text, required this.onPress});
}
