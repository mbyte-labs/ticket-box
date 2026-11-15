import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/poster/poster_grid_sliver.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/watchlist/common/filter_container.dart';
import 'package:ticketbox/ui/pages/watchlist/common/no_watchlist_items_container.dart';
import 'package:ticketbox/ui/pages/watchlist/common/paging_footer.dart';
import 'package:ticketbox/ui/pages/watchlist/common/watchlist_actions/watchlist_actions.dart';
import 'package:ticketbox/ui/pages/watchlist/watchlist_bloc.dart';
import 'package:ticketbox/ui/pages/watchlist/watchlist_state.dart';

class WatchlistMobilePage extends StatefulWidget {
  const WatchlistMobilePage({super.key});

  @override
  State<WatchlistMobilePage> createState() => _WatchlistMobilePage();
}

class _WatchlistMobilePage extends State<WatchlistMobilePage> {
  /// How far ahead of the bottom edge the next page is requested, as a multiple of the viewport
  /// height. One screen of prefetch keeps the grid from ever actually showing its footer spinner.
  static const _prefetchViewports = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WatchlistBloc>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Two listeners on purpose. ScrollNotification covers "the user scrolled near the end";
    // ScrollMetricsNotification covers "the content changed and the end is now near without
    // anybody scrolling" - a short first page, or a poster size change - which is the case a plain
    // scroll listener silently stalls on. The metrics notification is dispatched from a microtask
    // outside the build and layout phase, so asking the cubit to emit from here is safe.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => _onMetrics(notification.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => _onMetrics(notification.metrics),
        child: Scaffold(
          // Watchlist is not a drawer destination any more: it is opened from Lists, which leaves a
          // page to go back to, or it is the landing page, which does not. A null drawer lets the
          // app bar show its back arrow in the first case.
          drawer: context.canPop() ? null : const CustomNavigationDrawer(),
          body: const CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text('Watchlist'),
                floating: true,
                pinned: false,
                bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
              ),
              SliverToBoxAdapter(child: WatchlistFilterContainer()),
              _Body(),
              WatchlistPagingFooter(),
              SliverBottomInset(),
            ],
          ),
        ),
      ),
    );
  }

  /// Always returns false so the notification keeps bubbling up to anything above this page.
  bool _onMetrics(ScrollMetrics metrics) {
    if (metrics.extentAfter > metrics.viewportDimension * _prefetchViewports) {
      return false;
    }
    // This fires on very nearly every scrolled pixel, which is affordable only because
    // loadNextPage's guard is synchronous.
    unawaited(context.read<WatchlistBloc>().loadNextPage());
    return false;
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchlistBloc, WatchlistState>(
      buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
      builder: (context, state) {
        if (state.initialLoading) {
          return const SliverPageLoading('Loading your watchlist');
        } else {
          return const _WatchlistPostersBody();
        }
      },
    );
  }
}

class _WatchlistPostersBody extends StatelessWidget {
  const _WatchlistPostersBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchlistBloc, WatchlistState>(
      // Only the tile list rebuilds the grid; isLoadingMore rebuilds the footer alone. Because the
      // tiles are keyed by the model's id, a refresh that reorders the list re-parents the
      // existing elements instead of rebuilding them, so there is no flicker and no lost scroll
      // offset.
      buildWhen: (previous, current) => !const ListEquality<PosterModel>().equals(previous.models, current.models),
      builder: (context, state) {
        if (state.models.isEmpty) {
          return const WatchlistNoItemsContainer();
        }
        return PosterGridSliver(models: state.models, onTap: _posterTap, onLongPress: _posterLongPress);
      },
    );
  }

  /// All four item types can be watchlisted; [PosterNavigation] dispatches on the tile's type.
  void _posterTap(BuildContext context, PosterModel model) => PosterNavigation.navigate(context, model);

  /// Long press opens the remove-from-watchlist sheet, which handles every item type.
  void _posterLongPress(BuildContext context, PosterModel model) {
    WatchlistActionsWidget(model).buildWidget(context);
  }
}
