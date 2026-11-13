import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';
import 'package:ticketbox/ui/pages/app_init_page/app_init_page_bloc.dart';
import 'package:ticketbox/ui/pages/app_init_page/app_init_page_state.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';

class AppInitMobilePage extends StatelessWidget {
  const AppInitMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    ScreenSizeUtil.init(MediaQuery.of(context).size);

    return BlocConsumer<AppInitPageBloc, AppInitPageState>(
      listenWhen: (previous, current) {
        // return true/false to determine whether or not
        // to invoke listener with state
        return false;
      },
      listener: (context, state) {
        // do stuff here based on BlocA's state
      },
      buildWhen: (previous, current) {
        return true;
      },
      builder: (context, state) {
        return Scaffold(
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: TicketBoxLogoWidget(topMargin: 15, imageSize: 2.3)),
                SliverToBoxAdapter(
                  child: Container(
                    margin: ScreenSizeUtil.fromLTRB(0, 50, 0, 0),
                    child: const Text('Powered by', textAlign: TextAlign.center),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    constraints: BoxConstraints(maxHeight: ScreenSizeUtil.calculateSize(50)),
                    child: const Image(image: AssetImage(AssetsPath.tmdbSmallLogo)),
                  ),
                ),
                SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    Container(
                      margin: ScreenSizeUtil.fromLTRB(0, 100, 0, 0),
                      child: const LinearProgressIndicator(backgroundColor: Colors.grey),
                    ),
                    const _LoadingMessageContainer(),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadingMessageContainer extends StatelessWidget {
  const _LoadingMessageContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppInitPageBloc, AppInitPageState>(
      buildWhen: (previousState, state) {
        // return true/false to determine whether or not
        // to rebuild the widget with state
        return true;
      },
      builder: (context, state) {
        return Container(
          margin: ScreenSizeUtil.fromLTRB(0, 10, 0, 0),
          child: Text(
            state.message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 14),
          ),
        );
      },
    );
  }
}

// class _FullSyncDisplay extends StatelessWidget {
//   final AppInitPageState state;
//
//   const _FullSyncDisplay(this.state);
//
//   @override
//   Widget build(BuildContext context) {
//     if (ActionSType.fullSyncInProgress == state.action) {
//       return Container(
//         margin: ScreenSizeUtil.fromLTRB(0, 20, 0, 0),
//         child: const Text(
//           'Performing initial/full sync. This might take a bit longer...',
//           textAlign: TextAlign.center,
//           style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
//         ),
//       );
//     }
//     return const SizedBox();
//   }
// }
