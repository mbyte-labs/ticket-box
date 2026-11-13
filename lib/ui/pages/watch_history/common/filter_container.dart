import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/watch_history_item_type_filter.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_bloc.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_state.dart';
import 'package:ticketbox/ui/theme/constants.dart';

class WatchHistoryFilterContainer extends StatelessWidget {
  const WatchHistoryFilterContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchHistoryBloc, WatchHistoryState>(
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
              // No order by or order type: the history is always most recently watched first.
              body: const Column(
                children: [
                  _TitleContainer('Show:'),
                  _ItemTypeContainer(),
                  SizedBox(height: 10),
                  _TitleContainer('Watch action:'),
                  _ActionsContainer(),
                  _ApplyFilterContainer(),
                ],
              ),
            ),
          ],
          dividerColor: Colors.grey,
          expansionCallback: (panelIndex, isExpanded) {
            context.read<WatchHistoryBloc>().toggleFilterPanel(isExpanded);
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
    return BlocBuilder<WatchHistoryBloc, WatchHistoryState>(
      buildWhen: (previous, current) => previous.filters.filters.itemTypes != current.filters.filters.itemTypes,
      builder: (context, state) {
        final selected = state.filters.filters.itemTypes;
        return Wrap(
          spacing: 5,
          children: WatchHistoryItemTypeFilter.values
              .map(
                (itemType) => FilterButton(
                  text: itemType.prettyString(),
                  selected: itemType == selected,
                  onPress: () => context.read<WatchHistoryBloc>().updateItemTypes(itemType),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ActionsContainer extends StatelessWidget {
  const _ActionsContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WatchHistoryBloc, WatchHistoryState>(
      buildWhen: (previous, current) =>
          !const ListEquality<HistoryAction>().equals(previous.filters.filters.actions, current.filters.filters.actions),
      builder: (context, state) {
        final selected = state.filters.filters.actions;
        return Column(
          children: [
            Wrap(
              spacing: 5,
              children: HistoryAction.values
                  .map(
                    (action) => FilterButton(
                      text: action.prettyString(),
                      selected: selected.contains(action),
                      onPress: () => context.read<WatchHistoryBloc>().toggleAction(action),
                    ),
                  )
                  .toList(),
            ),
            if (selected.isEmpty)
              Container(
                margin: ScreenSizeUtil.fromLTRB(0, 5, 0, 0),
                child: Text(
                  'Keep at least one watch action selected.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
    return BlocBuilder<WatchHistoryBloc, WatchHistoryState>(
      buildWhen: (previous, current) =>
          previous.filters.filtersApplied != current.filters.filtersApplied ||
          previous.filters.filters.actions.isEmpty != current.filters.filters.actions.isEmpty,
      builder: (context, state) {
        final filtersApplied = state.filters.filtersApplied;
        // An empty action list would render as an invalid `IN ()`, so applying it is blocked here
        // rather than handled further down.
        final canApply = !filtersApplied && state.filters.filters.actions.isNotEmpty;
        return Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: ElevatedButton(
            onPressed: canApply
                ? () {
                    context.read<WatchHistoryBloc>().updateFilter();
                  }
                : null,
            child: const Text('Apply Filters', maxLines: 1),
          ),
        );
      },
    );
  }
}
