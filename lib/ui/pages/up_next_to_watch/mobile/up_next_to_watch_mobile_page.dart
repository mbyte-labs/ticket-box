import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/check_in/check_in_banner.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/poster/poster_grid_sliver.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/filter_container.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/no_next_episode_container.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/set_country_banner/set_country_banner.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/set_country_banner/set_country_banner_bloc.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/up_next_actions/up_next_to_watch_actions.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/up_next_to_watch_bloc.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/up_next_to_watch_state.dart';

class UpNextToWatchMobilePage extends StatefulWidget {
  const UpNextToWatchMobilePage({super.key});

  @override
  State<UpNextToWatchMobilePage> createState() => _UpNextToWatchMobilePage();
}

class _UpNextToWatchMobilePage extends State<UpNextToWatchMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UpNextToWatchBloc>().init();
      unawaited(context.read<SetCountryBannerBloc>().refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      drawer: CustomNavigationDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text('Up next to watch'),
            floating: true,
            pinned: false,
            //actions: [ShowsPagePageActions(_id)],
            bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
          ),
          SliverToBoxAdapter(child: SetCountryBanner()),
          SliverToBoxAdapter(child: CheckInBanner()),
          SliverToBoxAdapter(child: DashboardPageFilterContainer()),
          _Body(),
          SliverBottomInset(),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpNextToWatchBloc, UpNextToWatchState>(
      buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
      builder: (context, state) {
        if (state.initialLoading) {
          return const SliverPageLoading('Loading');
        } else {
          return const _DashboardPostersBody();
        }
      },
    );
  }
}

class _DashboardPostersBody extends StatelessWidget {
  const _DashboardPostersBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpNextToWatchBloc, UpNextToWatchState>(
      buildWhen: (previous, current) => !const ListEquality().equals(previous.upNext, current.upNext),
      builder: (context, state) {
        if (state.upNext.isEmpty) {
          return const DashboardPageNoEpisodesContainer();
        }
        return PosterGridSliver(
          models: state.upNext,
          onTap: _posterTap,
          onLongPress: (context, model) => UpNextToWatchActionsWidget(model).buildWidget(context),
        );
      },
    );
  }

  void _posterTap(BuildContext context, PosterModel model) {
    PosterNavigation.navigate(context, model);
  }
}
