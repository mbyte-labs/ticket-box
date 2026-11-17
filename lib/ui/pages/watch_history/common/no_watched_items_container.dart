import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_bloc.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_state.dart';
import 'package:ticketbox/ui/routes.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';

/// The empty state of the watch history grid.
///
/// Distinguishes an empty history from an over-narrow filter selection: telling somebody with
/// hundreds of watched episodes that they have not watched anything would just look broken.
class WatchHistoryNoItemsContainer extends StatelessWidget {
  const WatchHistoryNoItemsContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final isFiltered = context.select((WatchHistoryBloc bloc) => bloc.state.filters.filters != WatchHistoryFilterOptions.initial());

    return SliverList(
      delegate: SliverChildListDelegate([
        const TicketBoxLogoWidget(topMargin: 15, imageSize: 3),
        Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: const Text('Powered by', textAlign: TextAlign.center),
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 30),
          child: const Image(image: AssetImage(AssetsPath.tmdbSmallLogo)),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(0, 30, 0, 0),
          child: Text(
            isFiltered ? 'No watched items match the selected filters' : 'It looks like you have not watched anything yet',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(10, 15, 10, 0),
          child: Text(
            isFiltered
                ? 'Try widening the filters above - selecting more watch actions, or every item type.'
                : 'Once you mark an episode or a movie as watched, check in or scrobble it, it shows up here.',
            textAlign: TextAlign.center,
          ),
        ),
        if (!isFiltered)
          Container(
            margin: ScreenSizeUtil.fromLTRB(10, 20, 10, 0),
            child: Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => context.pushNamed(Routes.upNextToWatch),
                  label: const Text('Up next to watch'),
                  icon: const Icon(Icons.playlist_play_outlined),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
      ]),
    );
  }
}
