import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_filter.dart';

/// The empty state of the favorites grid, worded for the active filter.
class NoFavoriteItemsContainer extends StatelessWidget {
  final FavoritesFilter filter;

  const NoFavoriteItemsContainer({required this.filter, super.key});

  @override
  Widget build(BuildContext context) {
    final subject = switch (filter) {
      FavoritesFilter.everything => 'anything',
      FavoritesFilter.movies => 'any movies',
      FavoritesFilter.shows => 'any shows',
    };

    return SliverList(
      delegate: SliverChildListDelegate([
        const TicketBoxLogoWidget(topMargin: 15, imageSize: 3),
        Padding(
          padding: ScreenSizeUtil.fromLTRB(0, 30, 0, 0),
          child: Text(
            "You haven't added $subject to your favorites yet",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        Padding(
          padding: ScreenSizeUtil.fromLTRB(10, 15, 10, 0),
          child: const Text(
            'Add a movie or a show to your favorites from the menu on its page. Everything you favorite is listed here.',
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}
