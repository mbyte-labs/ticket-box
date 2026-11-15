import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/poster/poster_grid_sliver.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/pages/dropped_shows/common/dropped_show_actions.dart';
import 'package:ticketbox/ui/pages/dropped_shows/common/no_dropped_shows_container.dart';
import 'package:ticketbox/ui/pages/dropped_shows/dropped_shows_bloc.dart';
import 'package:ticketbox/ui/pages/dropped_shows/dropped_shows_state.dart';

/// Opened from Lists, so there is no drawer: the app bar shows its back arrow instead.
class DroppedShowsMobilePage extends StatefulWidget {
  const DroppedShowsMobilePage({super.key});

  @override
  State<DroppedShowsMobilePage> createState() => _DroppedShowsMobilePage();
}

class _DroppedShowsMobilePage extends State<DroppedShowsMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DroppedShowsBloc>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text('Dropped Shows'),
            floating: true,
            pinned: false,
            bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
          ),
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
    return BlocBuilder<DroppedShowsBloc, DroppedShowsState>(
      buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
      builder: (context, state) {
        if (state.initialLoading) {
          return const SliverPageLoading('Loading your dropped shows');
        } else {
          return const _DroppedPostersBody();
        }
      },
    );
  }
}

class _DroppedPostersBody extends StatelessWidget {
  const _DroppedPostersBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DroppedShowsBloc, DroppedShowsState>(
      // Tiles are keyed by the model's id, so an un-drop re-parents the remaining elements instead
      // of rebuilding them.
      buildWhen: (previous, current) => !const ListEquality<PosterModel>().equals(previous.models, current.models),
      builder: (context, state) {
        if (state.models.isEmpty) {
          return const NoDroppedShowsContainer();
        }
        return PosterGridSliver(
          models: state.models,
          onTap: (context, model) => PosterNavigation.navigate(context, model),
          onLongPress: _posterLongPress,
        );
      },
    );
  }

  /// Long press opens the un-drop sheet.
  void _posterLongPress(BuildContext context, PosterModel model) {
    DroppedShowActionsWidget(model).buildWidget(context);
  }
}
