import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/ui/navigation_drawer/local_stats_bloc.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Compact library statistics shown under the drawer header. Stats load asynchronously; until
/// they arrive the row is rendered invisible rather than collapsed, because it must keep a
/// constant height: the NavigationDrawer selection pill is an Ink feature painted onto the
/// drawer's Material, so if content above the destinations changes height after first paint the
/// pill is left behind — one row above the selected destination.
class DrawerStatsRow extends StatelessWidget {
  const DrawerStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocalStatsBloc, HeadlineStats?>(
      builder: (context, stats) {
        return Opacity(
          opacity: stats == null ? 0 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _StatCell(value: stats?.moviesWatched ?? 0, label: 'Movies'),
                _StatCell(value: stats?.episodesWatched ?? 0, label: 'Episodes'),
                _StatCell(value: stats?.hoursWatched ?? 0, label: 'Hours'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatCell extends StatelessWidget {
  final int value;
  final String label;

  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(_compactFormat(value), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale500)),
        ],
      ),
    );
  }

  static String _compactFormat(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 10000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toString();
  }
}
