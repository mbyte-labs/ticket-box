import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/user/user_details_bloc.dart';
import 'package:ticketbox/ui/navigation_drawer/drawer_stats_row.dart';
import 'package:ticketbox/ui/navigation_drawer/local_stats_bloc.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_footer.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_header.dart';
import 'package:ticketbox/ui/routes.dart';

typedef _Destination = ({String route, String label, IconData icon, IconData selectedIcon});

/// Indices map 1:1 onto the [NavigationDrawerDestination]s rendered below — interleaved
/// non-destination widgets (header, labels, dividers) don't count.
const List<_Destination> _destinations = [
  (route: Routes.upNextToWatch, label: 'Up next to watch', icon: Icons.play_circle_outline, selectedIcon: Icons.play_circle),
  // The user's own lists (Watchlist, Dropped Shows, Favorites). Sits next to "Up next to watch": the
  // watchlist is the other "still to watch" list, and it is reached through here now.
  (route: Routes.lists, label: 'Lists', icon: Icons.list_alt_outlined, selectedIcon: Icons.list_alt),
  // The old "Calendar" tile is deliberately gone: Routes.calendar was never registered in the
  // router, so tapping it crashed with a GoRouter "no routes for name" assertion.
  (route: Routes.history, label: 'History', icon: Icons.history, selectedIcon: Icons.history),
  // One entry for both TMDB catalogues: the page itself switches between movies and shows.
  (route: Routes.discover, label: 'Discover', icon: Icons.explore_outlined, selectedIcon: Icons.explore),
  (route: Routes.search, label: 'Search', icon: Icons.search_outlined, selectedIcon: Icons.search),
  (route: Routes.showProgress, label: 'Show Progress', icon: Icons.playlist_add_check_outlined, selectedIcon: Icons.playlist_add_check),
  (route: Routes.stats, label: 'Stats', icon: Icons.query_stats_outlined, selectedIcon: Icons.query_stats),
  (route: Routes.settings, label: 'Settings', icon: Icons.settings_outlined, selectedIcon: Icons.settings),
  // Diagnostics is deliberately absent: it lives under Settings now.
];

/// Pages opened from a destination rather than from the drawer itself, mapped to the destination
/// that should stay highlighted while they are on screen.
const Map<String, String> _parentDestination = {
  Routes.watchlist: Routes.lists,
  Routes.droppedShows: Routes.lists,
  Routes.favorites: Routes.lists,
};

/// App navigation drawer: logo header with library stats, followed by the page destinations, with
/// the app version and on-device note pinned at the bottom.
class CustomNavigationDrawer extends StatelessWidget {
  const CustomNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final routeName = GoRouterState.of(context).name;
    final highlightedRoute = _parentDestination[routeName] ?? routeName;
    final selectedIndex = _destinations.indexWhere((destination) => destination.route == highlightedRoute);

    // Drawer/NavigationDrawer add no inset of their own, and the pages no longer wrap their
    // Scaffold in a SafeArea, so without this the account header slides under the status bar.
    // Bottom is left to the drawer's own scrolling, which already reaches the screen edge.
    return SafeArea(
      bottom: false,
      child: NavigationDrawer(
        // -1 (drawer opened from a details page) must become null, otherwise a random pill shows.
        selectedIndex: selectedIndex == -1 ? null : selectedIndex,
        onDestinationSelected: (selectedIndex) => _goToPage(context, _destinations[selectedIndex].route),
        footer: const NavigationDrawerFooter(),
        children: <Widget>[
          const _HeaderWidget(),
          for (final destination in _destinations)
            NavigationDrawerDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: Text(destination.label),
            ),
        ],
      ),
    );
  }

  void _goToPage(BuildContext context, String pageName) {
    final userDetails = context.read<UserDetailsBloc>().state;
    String defaultPageRoute = userDetails.appPreferences.defaultLandingPage;
    final routeState = GoRouterState.of(context);
    final routeName = routeState.name;
    if (routeName == pageName) {
      context.pop();
      return;
    }
    if (defaultPageRoute == pageName) {
      while (context.canPop()) {
        context.pop();
      }
      context.pushReplacementNamed(pageName);
    } else {
      context.pop();
      context.pushNamed(pageName);
    }
  }
}

/// The logo header plus the library's headline numbers.
class _HeaderWidget extends StatelessWidget {
  const _HeaderWidget();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LocalStatsBloc>(
      create: (context) => LocalStatsBloc()..load(),
      child: const Column(children: [NavigationDrawerHeader(), DrawerStatsRow()]),
    );
  }
}
