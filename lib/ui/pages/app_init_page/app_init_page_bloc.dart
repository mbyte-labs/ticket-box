import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/app_resume_handler.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/catalog/catalog_refresh_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_auth_link_handler.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_outbox_service.dart';
import 'package:ticketbox/service/user/user_details_bloc.dart';
import 'package:ticketbox/ui/pages/app_init_page/app_init_page_state.dart';
import 'package:ticketbox/ui/routes.dart';

/// Decides where the app lands after the splash: loads the preferences, binds the resume handler,
/// kicks off the background progress refresh when it is due, and redirects to the landing page —
/// or to Settings when the app was opened by the TMDB approval deep link, so the user sees the login
/// finish where they started it.
///
/// There is no blocking sync: everything the user owns is already on the device. The optional TMDB
/// account only mirrors ratings, watchlist and favorites, through an outbox flushed here and on
/// resume.
class AppInitPageBloc extends Cubit<AppInitPageState> {
  static final _log = Logger('AppInitPageBloc');

  /// The drawer destinations a stored landing-page preference may point at.
  static const Set<String> _landingRoutes = {
    Routes.upNextToWatch,
    Routes.lists,
    // No longer in the drawer (it lives under Lists), but a stored preference may still name it.
    Routes.watchlist,
    Routes.history,
    Routes.discover,
    Routes.search,
    Routes.showProgress,
    Routes.stats,
    Routes.settings,
  };

  /// The route names of the separate Shows / Movies pages that merged into Discover, in case a
  /// stored preference still names one. Defensive only: the preference is currently never loaded
  /// from disk ([UserDetailsBloc.loadFromDisk] starts from the defaults).
  static const Map<String, String> _legacyLandingRoutes = {'Shows': Routes.discover, 'Movies': Routes.discover};

  bool initializedTriggered = false;

  AppInitPageBloc() : super(AppInitPageState.initial()) {
    _log.finest('Bloc created');
    unawaited(_init());
  }

  Future<void> _init() async {
    if (initializedTriggered) {
      return;
    }
    initializedTriggered = true;

    var openedByTmdbLink = false;
    try {
      await UserDetailsBloc.instance().loadFromDisk();
      // we bind the resume initializer here
      await AppResumeHandler().initialize();
      TmdbAuthLinkHandler.listen();
      openedByTmdbLink = await TmdbAuthLinkHandler.handleInitialLink();
      // The catalogue refresh (backfill, stale snapshots, state sweep) when due, and a periodic
      // tick while the app stays open. Never throws; its outcome lands on the job row the app-bar
      // indicator renders.
      unawaited(CatalogRefreshService.instance().tickIfDue());
      CatalogRefreshService.instance().startForegroundTimer();
      // Changes queued for TMDB while offline. Never throws; records nothing the user waits for.
      unawaited(TmdbSyncOutboxService.instance().flushIfPending());
      // Artwork left to download, after the landing page had a moment to paint its own tiles.
      unawaited(ArtworkService.instance().drainIfPending(delay: const Duration(seconds: 2)));
    } catch (e, stackTrace) {
      // Nothing above is essential for browsing; the landing page must still open.
      _log.severe('Start-up work failed, continuing to the landing page', e, stackTrace);
    }

    if (isClosed) {
      return;
    }
    emit(state.copyWith(action: ActionSType.finishedWork, namedRouteRedirect: openedByTmdbLink ? Routes.settings : _landingRoute()));
  }

  String _landingRoute() => resolveLandingRoute(UserDetailsBloc.instance().state.appPreferences.defaultLandingPage);

  /// The drawer destination a stored landing-page [preferred] value points at, or Up Next when it
  /// names nothing the drawer has.
  static String resolveLandingRoute(String? preferred) {
    final route = _legacyLandingRoutes[preferred] ?? preferred;
    return route != null && _landingRoutes.contains(route) ? route : Routes.upNextToWatch;
  }
}
