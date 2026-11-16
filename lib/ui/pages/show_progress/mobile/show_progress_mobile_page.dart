import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/common/check_in/check_in_banner.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/show_progress/common/filter_container.dart';
import 'package:ticketbox/ui/pages/show_progress/common/no_tracked_shows_container.dart';
import 'package:ticketbox/ui/pages/show_progress/common/show_progress_row.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_bloc.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_state.dart';

class ShowProgressMobilePage extends StatefulWidget {
  const ShowProgressMobilePage({super.key});

  @override
  State<ShowProgressMobilePage> createState() => _ShowProgressMobilePage();
}

class _ShowProgressMobilePage extends State<ShowProgressMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShowProgressBloc>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      drawer: CustomNavigationDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text('Show Progress'),
            floating: true,
            pinned: false,
            bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
          ),
          SliverToBoxAdapter(child: CheckInBanner()),
          SliverToBoxAdapter(child: ShowProgressFilterContainer()),
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
    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
      buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
      builder: (context, state) {
        if (state.initialLoading) {
          return const SliverPageLoading('Loading your show progress');
        } else {
          return const _ShowProgressList();
        }
      },
    );
  }
}

class _ShowProgressList extends StatelessWidget {
  const _ShowProgressList();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
      buildWhen: (previous, current) => !const ListEquality().equals(previous.rows, current.rows),
      builder: (context, state) {
        if (state.rows.isEmpty) {
          return const NoTrackedShowsContainer();
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
            final row = state.rows[index];
            return ShowProgressRow(row, key: Key('${row.showTmdbId}'));
          }, childCount: state.rows.length),
        );
      },
    );
  }
}
