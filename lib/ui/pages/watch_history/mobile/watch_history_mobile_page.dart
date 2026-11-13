import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/check_in/check_in_banner.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/poster/poster_grid_sliver.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/watch_history/common/filter_container.dart';
import 'package:ticketbox/ui/pages/watch_history/common/history_actions/watch_history_actions.dart';
import 'package:ticketbox/ui/pages/watch_history/common/no_watched_items_container.dart';
import 'package:ticketbox/ui/pages/watch_history/common/paging_footer.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_bloc.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_entry.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_state.dart';

class WatchHistoryMobilePage extends StatefulWidget {
  const WatchHistoryMobilePage({super.key});

  @override
  State<WatchHistoryMobilePage> createState() => _WatchHistoryMobilePage();
}

class _WatchHistoryMobilePage extends State<WatchHistoryMobilePage> {
  /// How far ahead of the bottom edge the next page is requested, as a multiple of the viewport
  /// height. One screen of prefetch keeps the grid from ever actually showing its footer spinner.
  static const _prefetchViewports = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WatchHistoryBloc>().init();
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
        child: const Scaffold(
          drawer: CustomNavigationDrawer(),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text('Watch history'),
                floating: true,
                pinned: false,
                bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
              ),
              SliverToBoxAdapter(child: CheckInBanner()),
              SliverToBoxAdapter(child: WatchHistoryFilterContainer()),
              _Body(),
              WatchHistoryPagingFooter(),
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
    unawaited(context.read<WatchHistoryBloc>().loadNextPage());
    return false;
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchHistoryBloc, WatchHistoryState>(
      buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
      builder: (context, state) {
        if (state.initialLoading) {
          return const SliverPageLoading('Loading your watch history');
        } else {
          return const _WatchHistoryPostersBody();
        }
      },
    );
  }
}

class _WatchHistoryPostersBody extends StatelessWidget {
  const _WatchHistoryPostersBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchHistoryBloc, WatchHistoryState>(
      // Only the entry list rebuilds the grid; isLoadingMore rebuilds the footer alone. Because the
      // tiles are keyed by the play's id, a refresh that reorders the list re-parents the existing
      // elements instead of rebuilding them, so there is no flicker and no lost scroll offset.
      buildWhen: (previous, current) => !const ListEquality<WatchHistoryEntry>().equals(previous.entries, current.entries),
      builder: (context, state) {
        final entries = state.entries;
        if (entries.isEmpty) {
          return const WatchHistoryNoItemsContainer();
        }
        final dateFormat = DateFormat.yMMMd();
        return PosterGridSliver(
          models: [for (final entry in entries) entry.model],
          // A rewatched item has one tile per play, all with the same model id.
          tileKeyOf: (index) => ValueKey('play-${entries[index].historyId}'),
          subtitleOf: (index) => dateFormat.format(entries[index].watchedAt.toLocal()),
          onTap: _posterTap,
          onLongPressAt: (context, index) => _posterLongPress(context, entries[index]),
        );
      },
    );
  }

  /// The grid holds movies as well as episodes; [PosterNavigation] dispatches on the tile's type.
  void _posterTap(BuildContext context, PosterModel model) => PosterNavigation.navigate(context, model);

  /// Long press opens the remove-from-history sheet: this one watch, or every watch of the movie /
  /// the episode, its season or its show. Unlike the up next sheet it deliberately offers no "mark
  /// as watched" or "check in", which are meaningless for something already watched.
  void _posterLongPress(BuildContext context, WatchHistoryEntry entry) {
    switch (entry.model.type) {
      case ItemType.movie:
      case ItemType.episode:
        WatchHistoryActionsWidget(entry).buildWidget(context);
      case ItemType.season:
      case ItemType.show:
        // History rows are only ever movies or episodes (see WatchHistoryItemTypeFilter), and a
        // season/show tile would have no removable history scope anyway.
        break;
    }
  }
}
