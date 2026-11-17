import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/watchlist_item_type_filter.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';
import 'package:ticketbox/ui/pages/watchlist/watchlist_bloc.dart';
import 'package:ticketbox/ui/pages/watchlist/watchlist_state.dart';
import 'package:ticketbox/ui/theme/constants.dart';

class WatchlistFilterContainer extends StatelessWidget {
  const WatchlistFilterContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchlistBloc, WatchlistState>(
      builder: (context, state) {
        final isLoading = state.initialLoading;
        final isExpanded = state.filters.containerExpanded;

        if (isLoading) {
          return const SizedBox();
        }
        return ExpansionPanelList(
          animationDuration: const Duration(milliseconds: 500),
          expandedHeaderPadding: GeneralMarginConstants.zeroMargin,
          elevation: 0,
          children: [
            ExpansionPanel(
              isExpanded: isExpanded,
              canTapOnHeader: true,
              backgroundColor: Theme.of(context).canvasColor,
              headerBuilder: (context, isExpanded) {
                return const ListTile(
                  isThreeLine: false,
                  title: Text('Filters', style: TextStyle(color: Colors.grey)),
                );
              },
              // No order by: the only date a watchlist row carries is the one it was listed on,
              // so the ordering choice is which end of it comes first.
              body: const Column(
                children: [
                  _TitleContainer('Show:'),
                  _ItemTypeContainer(),
                  SizedBox(height: 10),
                  _TitleContainer('Added:'),
                  _OrderTypeContainer(),
                  _ApplyFilterContainer(),
                ],
              ),
            ),
          ],
          dividerColor: Colors.grey,
          expansionCallback: (panelIndex, isExpanded) {
            context.read<WatchlistBloc>().toggleFilterPanel(isExpanded);
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
    return BlocBuilder<WatchlistBloc, WatchlistState>(
      buildWhen: (previous, current) => previous.filters.filters.itemTypes != current.filters.filters.itemTypes,
      builder: (context, state) {
        final selected = state.filters.filters.itemTypes;
        return Wrap(
          spacing: 5,
          children: WatchlistItemTypeFilter.values
              .map(
                (itemType) => FilterButton(
                  text: itemType.prettyString(),
                  selected: itemType == selected,
                  onPress: () => context.read<WatchlistBloc>().updateItemTypes(itemType),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _OrderTypeContainer extends StatelessWidget {
  const _OrderTypeContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchlistBloc, WatchlistState>(
      buildWhen: (previous, current) => previous.filters.filters.orderType != current.filters.filters.orderType,
      builder: (context, state) {
        final type = state.filters.filters.orderType;
        return Wrap(
          spacing: 5,
          children: [
            FilterButton(
              text: 'Newest first',
              selected: OrderType.descending == type,
              onPress: () => context.read<WatchlistBloc>().updateOrderType(OrderType.descending),
            ),
            FilterButton(
              text: 'Oldest first',
              selected: OrderType.ascending == type,
              onPress: () => context.read<WatchlistBloc>().updateOrderType(OrderType.ascending),
            ),
          ],
        );
      },
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
    return BlocBuilder<WatchlistBloc, WatchlistState>(
      buildWhen: (previous, current) => previous.filters.filtersApplied != current.filters.filtersApplied,
      builder: (context, state) {
        final filtersApplied = state.filters.filtersApplied;
        return Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: ElevatedButton(
            onPressed: filtersApplied
                ? null
                : () {
                    context.read<WatchlistBloc>().updateFilter();
                  },
            child: const Text('Apply Filters', maxLines: 1),
          ),
        );
      },
    );
  }
}
