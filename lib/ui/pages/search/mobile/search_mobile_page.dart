import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/check_in/check_in_banner.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/poster/poster_grid_sliver.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/search/common/search_empty_container.dart';
import 'package:ticketbox/ui/pages/search/common/search_filter_container.dart';
import 'package:ticketbox/ui/pages/search/common/search_paging_footer.dart';
import 'package:ticketbox/ui/pages/search/search_bloc.dart';
import 'package:ticketbox/ui/pages/search/search_state.dart';

class SearchMobilePage extends StatefulWidget {
  const SearchMobilePage({super.key});

  @override
  State<SearchMobilePage> createState() => _SearchMobilePage();
}

class _SearchMobilePage extends State<SearchMobilePage> {
  /// How far ahead of the bottom edge the next page is requested, as a multiple of the viewport
  /// height. One screen of prefetch keeps the grid from ever actually showing its footer spinner.
  static const _prefetchViewports = 1.0;

  // No init() in initState: unlike the discover pages there is nothing to load until the user
  // types something.

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
                title: Text('Search'),
                floating: true,
                pinned: false,
                bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
              ),
              SliverToBoxAdapter(child: CheckInBanner()),
              SliverToBoxAdapter(child: _SearchFieldContainer()),
              SliverToBoxAdapter(child: SearchFilterContainer()),
              _Body(),
              SearchPagingFooter(),
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
    unawaited(context.read<SearchBloc>().loadNextPage());
    return false;
  }
}

/// The query field. The controller is the single source of truth for in-flight text; the bloc
/// only ever holds the text a search actually ran for, so nothing feeds back into the field.
class _SearchFieldContainer extends StatefulWidget {
  const _SearchFieldContainer();

  @override
  State<_SearchFieldContainer> createState() => _SearchFieldContainerState();
}

class _SearchFieldContainerState extends State<_SearchFieldContainer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ScreenSizeUtil.fromLTRB(10, 10, 10, 0),
      child: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search movies and shows',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              if (value.text.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(icon: const Icon(Icons.clear), onPressed: _clear);
            },
          ),
        ),
        onChanged: (text) => context.read<SearchBloc>().onQueryChanged(text),
        onSubmitted: (_) => context.read<SearchBloc>().submit(),
      ),
    );
  }

  void _clear() {
    _controller.clear();
    context.read<SearchBloc>().onQueryChanged('');
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
      builder: (context, state) {
        if (state.initialLoading) {
          return const SliverPageLoading('Searching');
        } else {
          return const _SearchPostersBody();
        }
      },
    );
  }
}

class _SearchPostersBody extends StatelessWidget {
  const _SearchPostersBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      // Only the tile list rebuilds the grid; isLoadingMore rebuilds the footer alone. Because
      // the tiles are keyed by the model's id, a rebuild re-parents the existing elements instead
      // of rebuilding them, so there is no flicker and no lost scroll offset.
      buildWhen: (previous, current) =>
          previous.hasQuery != current.hasQuery ||
          previous.hasError != current.hasError ||
          !const ListEquality<PosterModel>().equals(previous.models, current.models),
      builder: (context, state) {
        if (state.models.isEmpty) {
          return const SearchEmptyContainer();
        } else {
          return PosterGridSliver(models: state.models, onTap: _posterTap);
        }
      },
    );
  }

  /// The grid mixes movies and shows; [PosterNavigation] dispatches on the tile's type.
  void _posterTap(BuildContext context, PosterModel model) => PosterNavigation.navigate(context, model);
}
