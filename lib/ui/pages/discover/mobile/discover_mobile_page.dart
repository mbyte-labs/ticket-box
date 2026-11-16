import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/check_in/check_in_banner.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/poster/poster_grid_sliver.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/discover/common/discover_empty_container.dart';
import 'package:ticketbox/ui/pages/discover/common/discover_filter_container.dart';
import 'package:ticketbox/ui/pages/discover/common/discover_paging_footer.dart';
import 'package:ticketbox/ui/pages/discover/common/discover_type_selector.dart';
import 'package:ticketbox/ui/pages/discover/discover_bloc.dart';
import 'package:ticketbox/ui/pages/discover/discover_state.dart';

class DiscoverMobilePage extends StatefulWidget {
  const DiscoverMobilePage({super.key});

  @override
  State<DiscoverMobilePage> createState() => _DiscoverMobilePage();
}

class _DiscoverMobilePage extends State<DiscoverMobilePage> {
  /// How far ahead of the bottom edge the next page is requested, as a multiple of the viewport
  /// height. One screen of prefetch keeps the grid from ever actually showing its footer spinner.
  static const _prefetchViewports = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DiscoverBloc>().init();
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
                title: Text('Discover'),
                floating: true,
                pinned: false,
                bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
              ),
              SliverToBoxAdapter(child: CheckInBanner()),
              SliverToBoxAdapter(child: _TypeSelectorContainer()),
              SliverToBoxAdapter(child: DiscoverFilterContainer()),
              _Body(),
              DiscoverPagingFooter(),
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
    unawaited(context.read<DiscoverBloc>().loadNextPage());
    return false;
  }
}

class _TypeSelectorContainer extends StatelessWidget {
  const _TypeSelectorContainer();

  @override
  Widget build(BuildContext context) {
    final type = context.select((DiscoverBloc bloc) => bloc.state.itemType);
    return DiscoverTypeSelector(selected: type, onChanged: (type) => unawaited(context.read<DiscoverBloc>().switchType(type)));
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      buildWhen: (previous, current) =>
          previous.itemType != current.itemType || previous.active.initialLoading != current.active.initialLoading,
      builder: (context, state) {
        if (state.active.initialLoading) {
          return SliverPageLoading('Loading ${state.itemTypeLabel}');
        } else {
          return const _DiscoverPostersBody();
        }
      },
    );
  }
}

class _DiscoverPostersBody extends StatelessWidget {
  const _DiscoverPostersBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      // Only a type switch or the active tile list rebuilds the grid; isLoadingMore rebuilds the
      // footer alone. Because the tiles are keyed by the model's id, a rebuild re-parents the
      // existing elements instead of rebuilding them, so there is no flicker and no lost scroll
      // offset.
      buildWhen: (previous, current) =>
          previous.itemType != current.itemType || !const ListEquality<PosterModel>().equals(previous.active.models, current.active.models),
      builder: (context, state) {
        if (state.active.models.isEmpty) {
          return const DiscoverEmptyContainer();
        } else {
          // The tiles carry their own type, so the tap needs no dispatch here.
          return PosterGridSliver(models: state.active.models, onTap: (context, model) => PosterNavigation.navigate(context, model));
        }
      },
    );
  }
}
