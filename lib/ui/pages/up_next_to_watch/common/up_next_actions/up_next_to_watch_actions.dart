import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/service/library/check_in_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/button_wrapper.dart';
import 'package:ticketbox/ui/common/buton/check_in_btn.dart';
import 'package:ticketbox/ui/common/buton/mark_as_watched_btn.dart';
import 'package:ticketbox/ui/general_widget/confirmation/mark_as_watched/mark_as_watched_widget.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/up_next_actions/up_next_to_watch_actions_bloc.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/up_next_actions/up_next_to_watch_actions_state.dart';

class UpNextToWatchActionsWidget {
  final PosterModel details;

  UpNextToWatchActionsWidget(this.details);

  void buildWidget(BuildContext mainContext) {
    showModalBottomSheet(
      context: mainContext,
      enableDrag: true,
      isDismissible: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) {
        return BlocProvider(
          lazy: false,
          create: (BuildContext context) => UpNextToWatchActionsBloc(details),
          child: BlocBuilder<UpNextToWatchActionsBloc, UpNextToWatchActionsState>(
            buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
            builder: (context, state) {
              if (state.initialLoading) {
                return const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 20),
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Center(child: Text('Loading...')),
                    SizedBox(height: 10),
                    SizedBox(height: 40),
                  ],
                );
              } else {
                return _UpNextToWatchActionsWidget(mainContext);
              }
            },
          ),
        );
      },
    );
  }
}

class _UpNextToWatchActionsWidget extends StatelessWidget {
  static final _log = Logger('UpNextToWatchActionsWidget');

  final BuildContext mainContext;

  const _UpNextToWatchActionsWidget(this.mainContext);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpNextToWatchActionsBloc, UpNextToWatchActionsState>(
      buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
      builder: (context, state) {
        return Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: ScreenSizeUtil.fromLTRB(5, 0, 5, 0),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    text: state.showTitle,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                margin: ScreenSizeUtil.fromLTRB(5, 0, 5, 0),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    text: state.title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ConfirmationButtonWrapper.wrapButton(MarkAsWatchedButton(onPressed: () => _markAsWatched(context))),
              const SizedBox(height: 20),
              ConfirmationButtonWrapper.wrapButton(CheckInButton(onPressed: () => _checkIn(context))),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Future<void> _markAsWatched(BuildContext context) async {
    final state = context.read<UpNextToWatchActionsBloc>().state;
    context.pop();
    MarkAsWatchedWidget.modal(context, MarkAsWatchedTarget.episode(state.show!.toRef(), state.episode!.toRef()));
  }

  Future<void> _checkIn(BuildContext context) async {
    final state = context.read<UpNextToWatchActionsBloc>().state;
    context.pop();
    final outcome = await CheckInService().checkIn(MarkAsWatchedTarget.episode(state.show!.toRef(), state.episode!.toRef()));
    if (outcome == CheckInOutcome.alreadyActive) {
      _log.info('Check-in refused: another check-in is already running');
      if (mainContext.mounted) {
        ScaffoldMessenger.of(mainContext).showSnackBar(const SnackBar(content: Text('Another check-in is already running')));
      }
    }
  }
}
