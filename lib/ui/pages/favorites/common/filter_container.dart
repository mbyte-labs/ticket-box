import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_bloc.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_filter.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_state.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// The collapsible Filters panel of the Favorites page, shaped like the Up next and Watchlist ones:
/// a choice is staged until Apply Filters reloads the grid and collapses the panel.
class FavoritesFilterContainer extends StatelessWidget {
  const FavoritesFilterContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FavoritesBloc, FavoritesState>(
      buildWhen: (previous, current) =>
          previous.initialLoading != current.initialLoading || previous.filterPanelExpanded != current.filterPanelExpanded,
      builder: (context, state) {
        if (state.initialLoading) {
          return const SizedBox();
        }
        return ExpansionPanelList(
          animationDuration: const Duration(milliseconds: 500),
          expandedHeaderPadding: GeneralMarginConstants.zeroMargin,
          elevation: 0,
          children: [
            ExpansionPanel(
              isExpanded: state.filterPanelExpanded,
              canTapOnHeader: true,
              backgroundColor: Theme.of(context).canvasColor,
              headerBuilder: (context, isExpanded) {
                return const ListTile(
                  isThreeLine: false,
                  title: Text('Filters', style: TextStyle(color: Colors.grey)),
                );
              },
              body: const Column(children: [_TitleContainer('Show:'), _ItemTypeContainer(), _ApplyFilterContainer()]),
            ),
          ],
          dividerColor: Colors.grey,
          expansionCallback: (panelIndex, isExpanded) {
            context.read<FavoritesBloc>().toggleFilterPanel(isExpanded);
          },
        );
      },
    );
  }
}

class _ItemTypeContainer extends StatelessWidget {
  const _ItemTypeContainer();

  @override
  Widget build(BuildContext context) {
    final selected = context.select((FavoritesBloc bloc) => bloc.state.selectedFilter);

    return Wrap(
      spacing: 5,
      children: [
        for (final filter in FavoritesFilter.values)
          FilterButton(text: filter.label, selected: filter == selected, onPress: () => context.read<FavoritesBloc>().selectFilter(filter)),
      ],
    );
  }
}

class _TitleContainer extends StatelessWidget {
  final String title;

  const _TitleContainer(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _ApplyFilterContainer extends StatelessWidget {
  const _ApplyFilterContainer();

  @override
  Widget build(BuildContext context) {
    final filterApplied = context.select((FavoritesBloc bloc) => bloc.state.selectedFilter == bloc.state.filter);

    return Padding(
      padding: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
      child: ElevatedButton(
        onPressed: filterApplied ? null : () => context.read<FavoritesBloc>().applyFilter(),
        child: const Text('Apply Filters', maxLines: 1),
      ),
    );
  }
}
