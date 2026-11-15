import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';
import 'package:ticketbox/ui/pages/stats/stats_bloc.dart';
import 'package:ticketbox/ui/routes.dart';

/// Shown when there is nothing to compute stats from - nothing at all, or nothing in the
/// selected year - doubling as the error state.
class NoStatsContainer extends StatelessWidget {
  const NoStatsContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final (hasError, year) = context.select((StatsBloc bloc) => (bloc.state.hasError, bloc.state.period.year));

    return SliverList(
      delegate: SliverChildListDelegate([
        const TicketBoxLogoWidget(topMargin: 15, imageSize: 3),
        Container(
          margin: ScreenSizeUtil.fromLTRB(0, 30, 0, 0),
          child: Text(
            hasError
                ? 'Something went wrong while computing your stats'
                : year == null
                ? 'There are no stats to show yet'
                : 'Nothing watched or rated in $year',
            textAlign: TextAlign.center,
          ),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: Text(
            hasError
                ? 'Give it another try, and check the Diagnostics page if it keeps happening.'
                : year == null
                ? 'Watch something and your stats will appear here.'
                : 'Pick another year, or go back to All time.',
            textAlign: TextAlign.center,
          ),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(10, 20, 10, 0),
          child: hasError
              ? FilledButton.tonalIcon(
                  onPressed: () => context.read<StatsBloc>().retry(),
                  label: const Text('Retry'),
                  icon: const Icon(Icons.refresh),
                )
              : FilledButton.tonalIcon(
                  onPressed: () => context.pushNamed(Routes.discover, queryParameters: {'type': 'shows', 'mode': 'trending'}),
                  label: const Text('Trending shows'),
                  icon: const Icon(Icons.movie),
                ),
        ),
      ]),
    );
  }
}
