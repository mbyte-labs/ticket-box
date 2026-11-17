import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/up_next_to_watch_order_by.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/up_next_to_watch_bloc.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/up_next_to_watch_state.dart';
import 'package:ticketbox/ui/theme/constants.dart';

class DashboardPageFilterContainer extends StatelessWidget {
  const DashboardPageFilterContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpNextToWatchBloc, UpNextToWatchState>(
      // buildWhen: (previous, current) =>
      // previous.initialLoading != current.initialLoading,
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
                  _TitleContainer('Release options:'),
                  _WithReleaseDate(),
                  _OnlyAiredEpisodes(),
                  _ApplyFilterContainer(),
                ],
              ),
            ),
          ],
          dividerColor: Colors.grey,
          expansionCallback: (panelIndex, isExpanded) {
            context.read<UpNextToWatchBloc>().toggleFilterPanel(isExpanded);
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
    return BlocBuilder<UpNextToWatchBloc, UpNextToWatchState>(
      buildWhen: (previous, current) => previous.filters.filters.orderBy != current.filters.filters.orderBy,
      builder: (context, state) {
        final type = state.filters.filters.orderBy;
        return Wrap(
          spacing: 5,
          children: [
            FilterButton(
              text: 'Last Watched',
              selected: UpNextToWatchOrderBy.lastWatched == type ? true : false,
              onPress: () => context.read<UpNextToWatchBloc>().updateOrderBy(UpNextToWatchOrderBy.lastWatched),
            ),
            FilterButton(
              text: 'Show Name',
              selected: UpNextToWatchOrderBy.showName == type ? true : false,
              onPress: () => context.read<UpNextToWatchBloc>().updateOrderBy(UpNextToWatchOrderBy.showName),
            ),
            FilterButton(
              text: 'Episode Release Date',
              selected: UpNextToWatchOrderBy.episodeReleaseDate == type ? true : false,
              onPress: () => context.read<UpNextToWatchBloc>().updateOrderBy(UpNextToWatchOrderBy.episodeReleaseDate),
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
    return BlocBuilder<UpNextToWatchBloc, UpNextToWatchState>(
      buildWhen: (previous, current) => previous.filters.filters.orderType != current.filters.filters.orderType,
      builder: (context, state) {
        final type = state.filters.filters.orderType;
        return Wrap(
          spacing: 5,
          children: [
            FilterButton(
              text: 'Asc',
              selected: OrderType.ascending == type ? true : false,
              onPress: () => context.read<UpNextToWatchBloc>().updateOrderType(OrderType.ascending),
            ),
            FilterButton(
              text: 'Desc',
              selected: OrderType.descending == type ? true : false,
              onPress: () => context.read<UpNextToWatchBloc>().updateOrderType(OrderType.descending),
            ),
          ],
        );
      },
    );
  }
}

class _WithReleaseDate extends StatelessWidget {
  const _WithReleaseDate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpNextToWatchBloc, UpNextToWatchState>(
      buildWhen: (previous, current) => previous.filters.filters.onlyWithReleaseDate != current.filters.filters.onlyWithReleaseDate,
      builder: (context, state) {
        final onlyWithReleaseDate = state.filters.filters.onlyWithReleaseDate;
        return CheckboxListTile(
          contentPadding: GeneralMarginConstants.zeroMargin,
          value: onlyWithReleaseDate,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Only episodes with release date'),
          subtitle: const Text(
            'When selected, only episodes that have a release date will be displayed.\nNote that there are situations where an episode might already be released but does not have a release date on TMDB yet.',
          ),
          onChanged: (bool? value) {
            if (value == null) {
              return;
            }
            context.read<UpNextToWatchBloc>().updateOnlyWithReleaseDate(value);
          },
        );
      },
    );
  }
}

class _OnlyAiredEpisodes extends StatelessWidget {
  const _OnlyAiredEpisodes();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpNextToWatchBloc, UpNextToWatchState>(
      buildWhen: (previous, current) => previous.filters.filters.displayAiredOnly != current.filters.filters.displayAiredOnly,
      builder: (context, state) {
        final displayAiredOnly = state.filters.filters.displayAiredOnly;
        return CheckboxListTile(
          contentPadding: GeneralMarginConstants.zeroMargin,
          value: displayAiredOnly,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Only released episodes'),
          subtitle: const Text(
            'When selected, only episodes with a release date of today or earlier are displayed.\nEpisodes without a release date on TMDB are hidden.',
          ),
          onChanged: (bool? value) {
            if (value == null) {
              return;
            }
            context.read<UpNextToWatchBloc>().updateDisplayAiredOnly(value);
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
    return BlocBuilder<UpNextToWatchBloc, UpNextToWatchState>(
      buildWhen: (previous, current) => previous.filters.filtersApplied != current.filters.filtersApplied,
      builder: (context, state) {
        final filtersApplied = state.filters.filtersApplied;
        return Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: ElevatedButton(
            onPressed: filtersApplied
                ? null
                : () {
                    context.read<UpNextToWatchBloc>().updateFilter();
                  },
            child: const Text('Apply Filters', maxLines: 1),
          ),
        );
      },
    );
  }
}
