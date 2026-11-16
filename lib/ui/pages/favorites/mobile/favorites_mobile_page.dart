import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/poster/poster_grid_sliver.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/pages/favorites/common/favorite_item_actions.dart';
import 'package:ticketbox/ui/pages/favorites/common/filter_container.dart';
import 'package:ticketbox/ui/pages/favorites/common/no_favorite_items_container.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_bloc.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_state.dart';

/// Opened from Lists, so there is no drawer: the app bar shows its back arrow instead.
class FavoritesMobilePage extends StatefulWidget {
  const FavoritesMobilePage({super.key});

  @override
  State<FavoritesMobilePage> createState() => _FavoritesMobilePage();
}

class _FavoritesMobilePage extends State<FavoritesMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FavoritesBloc>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text('Favorites'),
            floating: true,
            pinned: false,
            bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
          ),
          SliverToBoxAdapter(child: FavoritesFilterContainer()),
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
    return BlocBuilder<FavoritesBloc, FavoritesState>(
      buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
      builder: (context, state) {
        if (state.initialLoading) {
          return const SliverPageLoading('Loading your favorites');
        } else {
          return const _FavoritesPostersBody();
        }
      },
    );
  }
}

class _FavoritesPostersBody extends StatelessWidget {
  const _FavoritesPostersBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FavoritesBloc, FavoritesState>(
      // Tiles are keyed by the model's id, so a removal re-parents the remaining elements instead
      // of rebuilding them. The filter is part of the condition so an empty result for a new
      // filter still swaps in the right empty-state wording.
      buildWhen: (previous, current) =>
          previous.filter != current.filter || !const ListEquality<PosterModel>().equals(previous.models, current.models),
      builder: (context, state) {
        if (state.models.isEmpty) {
          return NoFavoriteItemsContainer(filter: state.filter);
        }
        return PosterGridSliver(
          models: state.models,
          onTap: (context, model) => PosterNavigation.navigate(context, model),
          onLongPress: _posterLongPress,
        );
      },
    );
  }

  /// Long press opens the remove-from-favorites sheet.
  void _posterLongPress(BuildContext context, PosterModel model) {
    FavoriteItemActionsWidget(model).buildWidget(context);
  }
}
