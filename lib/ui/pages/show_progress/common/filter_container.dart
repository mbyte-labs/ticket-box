import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/show_progress_order_by.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_bloc.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_state.dart';
import 'package:ticketbox/ui/theme/constants.dart';

class ShowProgressFilterContainer extends StatelessWidget {
  const ShowProgressFilterContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
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
              body: const Column(
                children: [
                  _TitleContainer('Order By:'),
                  _OrderByContainer(),
                  SizedBox(height: 10),
                  _TitleContainer('Order type:'),
                  _OrderTypeContainer(),
                  SizedBox(height: 10),
                  _TitleContainer('Display options:'),
                  _HideCompletedContainer(),
                  _ApplyFilterContainer(),
                ],
              ),
            ),
          ],
          dividerColor: Colors.grey,
          expansionCallback: (panelIndex, isExpanded) {
            context.read<ShowProgressBloc>().toggleFilterPanel(isExpanded);
          },
        );
      },
    );
  }
}

class _OrderByContainer extends StatelessWidget {
  const _OrderByContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
      buildWhen: (previous, current) => previous.filters.filters.orderBy != current.filters.filters.orderBy,
      builder: (context, state) {
        final type = state.filters.filters.orderBy;
        return Wrap(
          spacing: 5,
          children: [
            FilterButton(
              text: 'Last Watched',
              selected: ShowProgressOrderBy.lastWatched == type,
              onPress: () => context.read<ShowProgressBloc>().updateOrderBy(ShowProgressOrderBy.lastWatched),
            ),
            FilterButton(
              text: 'Show Name',
              selected: ShowProgressOrderBy.showName == type,
              onPress: () => context.read<ShowProgressBloc>().updateOrderBy(ShowProgressOrderBy.showName),
            ),
            FilterButton(
              text: 'Progress',
              selected: ShowProgressOrderBy.progress == type,
              onPress: () => context.read<ShowProgressBloc>().updateOrderBy(ShowProgressOrderBy.progress),
            ),
          ],
        );
      },
    );
  }
}

class _OrderTypeContainer extends StatelessWidget {
  const _OrderTypeContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
      buildWhen: (previous, current) => previous.filters.filters.orderType != current.filters.filters.orderType,
      builder: (context, state) {
        final type = state.filters.filters.orderType;
        return Wrap(
          spacing: 5,
          children: [
            FilterButton(
              text: 'Asc',
              selected: OrderType.ascending == type,
              onPress: () => context.read<ShowProgressBloc>().updateOrderType(OrderType.ascending),
            ),
            FilterButton(
              text: 'Desc',
              selected: OrderType.descending == type,
              onPress: () => context.read<ShowProgressBloc>().updateOrderType(OrderType.descending),
            ),
          ],
        );
      },
    );
  }
}

class _HideCompletedContainer extends StatelessWidget {
  const _HideCompletedContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
      buildWhen: (previous, current) => previous.filters.filters.hideCompleted != current.filters.filters.hideCompleted,
      builder: (context, state) {
        final hideCompleted = state.filters.filters.hideCompleted;
        return CheckboxListTile(
          contentPadding: GeneralMarginConstants.zeroMargin,
          value: hideCompleted,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Hide completed shows'),
          subtitle: const Text('When selected, shows where every aired episode is already watched are hidden.'),
          onChanged: (bool? value) {
            if (value == null) {
              return;
            }
            context.read<ShowProgressBloc>().updateHideCompleted(value);
          },
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
    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
      buildWhen: (previous, current) => previous.filters.filtersApplied != current.filters.filtersApplied,
      builder: (context, state) {
        final filtersApplied = state.filters.filtersApplied;
        return Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: ElevatedButton(
            onPressed: filtersApplied
                ? null
                : () {
                    context.read<ShowProgressBloc>().updateFilter();
                  },
            child: const Text('Apply Filters', maxLines: 1),
          ),
        );
      },
    );
  }
}
