import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/stats/mobile/stats_mobile_page.dart';
import 'package:ticketbox/ui/pages/stats/stats_bloc.dart';

/// Page that shows statistics about the account: headline totals, rating habits, watch
/// activity over time, rewatches, show completion and top genres.
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => StatsBloc(),
      child: const AdaptiveLayoutBuilder.single(child: StatsMobilePage()),
    );
  }
}
