import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:ticketbox/common/model/tuple.dart';
import 'package:ticketbox/ui/pages/about/about_page.dart';
import 'package:ticketbox/ui/pages/app_init_page/app_init_page.dart';
import 'package:ticketbox/ui/pages/details/episode/episode_details_page.dart';
import 'package:ticketbox/ui/pages/details/movie/movie_details_page.dart';
import 'package:ticketbox/ui/pages/details/person/person_details_page.dart';
import 'package:ticketbox/ui/pages/details/person/person_route_args.dart';
import 'package:ticketbox/ui/pages/details/season/season_details_page.dart';
import 'package:ticketbox/ui/pages/details/show/show_details_page.dart';
import 'package:ticketbox/ui/pages/diagnostics/diagnostics_page.dart';
import 'package:ticketbox/ui/pages/discover/discover_page.dart';
import 'package:ticketbox/ui/pages/discover/discover_route_args.dart';
import 'package:ticketbox/ui/pages/donate/donate_page.dart';
import 'package:ticketbox/ui/pages/dropped_shows/dropped_shows_page.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_page.dart';
import 'package:ticketbox/ui/pages/lists/lists_page.dart';
import 'package:ticketbox/ui/pages/search/search_page.dart';
import 'package:ticketbox/ui/pages/settings/settings_page.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_page.dart';
import 'package:ticketbox/ui/pages/stats/stats_page.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/up_next_to_watch_page.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_page.dart';
import 'package:ticketbox/ui/pages/watchlist/watchlist_page.dart';

/// Every route is reachable without any sign-in: the app has no account.
class Routes {
  static const appInit = 'App Init';
  static const upNextToWatch = 'Up Next To Watch';
  static const history = 'History';
  static const lists = 'Lists';
  static const watchlist = 'Watchlist';
  static const droppedShows = 'Dropped Shows';
  static const favorites = 'Favorites';
  static const discover = 'Discover';
  static const search = 'Search';
  static const showProgress = 'Show Progress';
  static const stats = 'Stats';
  static const movieDetails = 'Movie Details';
  static const personDetails = 'Person Details';
  static const showDetails = 'Show Details';
  static const seasonDetails = 'Season Details';
  static const episodeDetails = 'Episode Details';
  static const settings = 'Settings';
  static const diagnostics = 'Diagnostics';
  static const about = 'About';
  static const donate = 'Buy Me A Coffee';

  static const String defaultPageNamed = appInit;
  static const String _defaultLandingPagePath = '/app-init';

  // GoRouter configuration
  static GoRouter configuration = GoRouter(
    initialLocation: _defaultLandingPagePath,
    //observers: [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
    routes: [
      GoRoute(path: '/', redirect: (context, state) => _defaultLandingPagePath),
      GoRoute(name: appInit, path: '/app-init', builder: (context, state) => const AppInitPage()),

      /// This is the route that handles everything related to the
      /// planning process
      GoRoute(name: upNextToWatch, path: '/up-next-to-watch', builder: (context, state) => const UpNextToWatchPage()),
      GoRoute(name: history, path: '/history', builder: (context, state) => const WatchHistoryPage()),
      // The drawer's Lists page opens the built-in lists below it; they are top-level routes so a
      // stored landing page of Watchlist keeps resolving.
      GoRoute(name: lists, path: '/lists', builder: (context, state) => const ListsPage()),
      GoRoute(name: watchlist, path: '/watchlist', builder: (context, state) => const WatchlistPage()),
      GoRoute(name: droppedShows, path: '/lists/dropped-shows', builder: (context, state) => const DroppedShowsPage()),
      GoRoute(name: favorites, path: '/lists/favorites', builder: (context, state) => const FavoritesPage()),
      GoRoute(
        name: discover,
        path: '/discover',
        // ?type=movies|shows picks the list, ?mode=popular|topRated|trending overrides the saved
        // list for this visit; both optional. See DiscoverRouteArgs.
        builder: (context, state) => DiscoverPage(args: DiscoverRouteArgs.fromQuery(state.uri.queryParameters)),
      ),
      GoRoute(name: search, path: '/search', builder: (context, state) => const SearchPage()),
      GoRoute(name: showProgress, path: '/show-progress', builder: (context, state) => const ShowProgressPage()),
      GoRoute(name: stats, path: '/stats', builder: (context, state) => const StatsPage()),
      GoRoute(name: settings, path: '/settings', builder: (context, state) => const SettingsPage()),

      GoRoute(name: diagnostics, path: '/diagnostics', builder: (context, state) => const DiagnosticsPage()),

      GoRoute(name: about, path: '/about', builder: (context, state) => const AboutPage()),

      GoRoute(name: donate, path: '/donate', builder: (context, state) => const DonatePage()),
      GoRoute(
        name: movieDetails,
        path: '/movie/:tmdbId',
        builder: (context, state) {
          final tmdbId = int.parse(state.pathParameters['tmdbId']!);
          return MovieDetailsPage(tmdbId);
        },
      ),
      GoRoute(
        name: personDetails,
        path: '/person/:personTmdbId',
        builder: (context, state) {
          final personTmdbId = int.parse(state.pathParameters['personTmdbId']!);
          // The cast card's paint-ahead hint; anything else (a deep link carries none) is ignored.
          final extra = state.extra;
          return PersonDetailsPage(personTmdbId, args: extra is PersonRouteArgs ? extra : null);
        },
      ),
      GoRoute(
        name: showDetails,
        path: '/show/:showTmdbId',
        builder: (context, state) {
          final showTmdbId = int.parse(state.pathParameters['showTmdbId']!);
          return ShowDetailsPage(showTmdbId);
        },
      ),
      GoRoute(
        name: seasonDetails,
        path: '/show/:showTmdbId/season/:season',
        builder: (context, state) {
          final showTmdbId = int.parse(state.pathParameters['showTmdbId']!);
          final season = int.parse(state.pathParameters['season']!);
          return SeasonDetailsPage(Tuple2<int, int>(showTmdbId, season));
        },
      ),
      GoRoute(
        name: episodeDetails,
        path: '/show/:showTmdbId/season/:season/episode/:episode',
        builder: (context, state) {
          final showTmdbId = int.parse(state.pathParameters['showTmdbId']!);
          final season = int.parse(state.pathParameters['season']!);
          final episode = int.parse(state.pathParameters['episode']!);
          return EpisodeDetailsPage(Tuple3<int, int, int>(showTmdbId, season, episode));
        },
      ),
    ],
  );

  static void popOrGoDefault(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.replaceNamed(Routes.defaultPageNamed);
    }
  }
}
