import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';
import 'package:ticketbox/ui/pages/watchlist/watchlist_bloc.dart';
import 'package:ticketbox/ui/pages/watchlist/watchlist_state.dart';
import 'package:ticketbox/ui/routes.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';

/// The empty state of the watchlist grid.
///
/// Distinguishes an empty watchlist from an over-narrow filter selection: telling somebody with a
/// hundred bookmarked shows that they have not added anything would just look broken.
class WatchlistNoItemsContainer extends StatelessWidget {
  const WatchlistNoItemsContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final isFiltered = context.select((WatchlistBloc bloc) => bloc.state.filters.filters != WatchlistFilterOptions.initial());

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
            isFiltered ? 'Nothing on your watchlist matches the selected filters' : 'Your watchlist is empty',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(10, 15, 10, 0),
          child: Text(
            isFiltered
                ? 'Try widening the filters above - selecting every item type.'
                : 'Tap the bookmark on any show, season, episode or movie to add it here.',
            textAlign: TextAlign.center,
          ),
        ),
        if (!isFiltered)
          Container(
            margin: ScreenSizeUtil.fromLTRB(10, 20, 10, 0),
            child: Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => context.pushNamed(Routes.search),
                  label: const Text('Search'),
                  icon: const Icon(Icons.search_outlined),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
      ]),
    );
  }
}
