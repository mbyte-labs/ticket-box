import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/button_wrapper.dart';
import 'package:ticketbox/ui/general_widget/confirmation/check_in_remove/check_in_remove_confirmation_bloc.dart';
import 'package:ticketbox/ui/general_widget/confirmation/check_in_remove/check_in_remove_confirmation_state.dart';
import 'package:ticketbox/ui/general_widget/confirmation/check_in_remove/loading_widget.dart';

// TODO: Make the remove check in pop-up more preatty
class CheckInRemoveConfirmationWidget {
  final HistoryEntity historyItem;

  CheckInRemoveConfirmationWidget(this.historyItem);

  void buildWidget(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext modalContext) {
        return BlocProvider(
          lazy: false,
          create: (BuildContext context) => CheckInRemoveConfirmationBloc(historyItem),
          child: SizedBox(
            height: ScreenSizeUtil.calculateSize(230),
            child: Center(
              child: Container(margin: ScreenSizeUtil.fromLTRB(10, 0, 10, 0), child: const _ConfirmationBodyWidget()),
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
    return BlocConsumer<CheckInRemoveConfirmationBloc, CheckInRemoveConfirmationState>(
      listenWhen: (previous, current) => previous.isWorkFinished != current.isWorkFinished,
      listener: (context, state) {
        if (state.isWorkFinished) {
          context.pop();
        }
      },
      buildWhen: (previous, current) => (previous.isInitialized != current.isInitialized) || (previous.isLoading != current.isLoading),
      builder: (context, state) {
        if (!state.isInitialized) {
          return const CheckInRemoveConfirmationLoadingWidget();
        }

        if (state.isLoading) {
          return const CheckInRemoveConfirmationLoadingWidget();
        }

        return const _ConfirmationDetailsWidget();
      },
    );
  }
}

/// The main widget with the rating and the submit button
class _ConfirmationDetailsWidget extends StatelessWidget {
  const _ConfirmationDetailsWidget();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(height: ScreenSizeUtil.calculateSize(20)),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(text: 'Are you sure you want to remove the current check in?', style: TextStyle(fontSize: 18)),
        ),
        const Spacer(),
        const _ConfirmBtnWidget(),
        SizedBox(height: ScreenSizeUtil.calculateSize(20)),
        ConfirmationButtonWrapper.wrapButton(
          ElevatedButton(
            child: const Text('Cancel', maxLines: 1),
            onPressed: () {
              context.pop();
            },
          ),
        ),
        SizedBox(height: ScreenSizeUtil.calculateSize(30)),
      ],
    );
  }
}

class _ConfirmBtnWidget extends StatelessWidget {
  const _ConfirmBtnWidget();

  @override
  Widget build(BuildContext context) {
    return ConfirmationButtonWrapper.wrapButton(
      ElevatedButton(
        child: const Text('Remove Check In', maxLines: 1),
        onPressed: () {
          context.read<CheckInRemoveConfirmationBloc>().remove();
        },
      ),
    );
  }
}
