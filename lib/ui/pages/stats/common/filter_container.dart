import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_period.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';
import 'package:ticketbox/ui/pages/stats/stats_bloc.dart';
import 'package:ticketbox/ui/pages/stats/stats_state.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// The collapsible "Filters" panel of the Stats page, shaped like the Up Next one: the period
/// (all time or one year) is staged with a tap and applied with the button, which closes the
/// panel and recomputes the page. Hidden while the page loads and while there is no history and
/// no rating at all - a panel offering only "All time" says nothing.
class StatsFilterContainer extends StatelessWidget {
  const StatsFilterContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StatsBloc, StatsState>(
      buildWhen: (previous, current) =>
          previous.initialLoading != current.initialLoading ||
          previous.filterExpanded != current.filterExpanded ||
          previous.availableYears.isEmpty != current.availableYears.isEmpty,
      builder: (context, state) {
        if (state.initialLoading || state.availableYears.isEmpty) {
          return const SizedBox();
        }
        return ExpansionPanelList(
          animationDuration: const Duration(milliseconds: 500),
          expandedHeaderPadding: GeneralMarginConstants.zeroMargin,
          elevation: 0,
          children: [
            ExpansionPanel(
              isExpanded: state.filterExpanded,
              canTapOnHeader: true,
              backgroundColor: Theme.of(context).canvasColor,
              headerBuilder: (context, isExpanded) {
                return const ListTile(
                  isThreeLine: false,
                  title: Text('Filters', style: TextStyle(color: Colors.grey)),
                );
              },
              body: const Column(children: [_TitleContainer('Period:'), _PeriodContainer(), _ApplyFilterContainer()]),
            ),
          ],
          dividerColor: Colors.grey,
          expansionCallback: (panelIndex, isExpanded) {
            context.read<StatsBloc>().toggleFilterPanel(isExpanded);
          },
        );
      },
    );
  }
}

/// "All time" then every year on offer, newest first, the staged one outlined.
class _PeriodContainer extends StatelessWidget {
  const _PeriodContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StatsBloc, StatsState>(
      buildWhen: (previous, current) =>
          previous.pendingPeriod != current.pendingPeriod || previous.availableYears != current.availableYears,
      builder: (context, state) {
        final periods = [const StatsPeriod.allTime(), for (final year in state.availableYears) StatsPeriod.year(year)];
        return Wrap(
          spacing: 5,
          alignment: WrapAlignment.center,
          children: [
            for (final period in periods)
              FilterButton(
                text: period.label,
                selected: state.pendingPeriod == period,
                onPress: () => context.read<StatsBloc>().stagePeriod(period),
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
    return BlocBuilder<StatsBloc, StatsState>(
      buildWhen: (previous, current) => previous.pendingPeriod != current.pendingPeriod || previous.period != current.period,
      builder: (context, state) {
        final filtersApplied = state.pendingPeriod == state.period;
        return Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: ElevatedButton(
            onPressed: filtersApplied ? null : () => context.read<StatsBloc>().applyPeriod(),
            child: const Text('Apply Filters', maxLines: 1),
          ),
        );
      },
    );
  }
}
