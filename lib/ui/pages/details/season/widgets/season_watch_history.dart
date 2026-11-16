import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/details/season/season_details_bloc.dart';
import 'package:ticketbox/ui/pages/details/season/season_details_state.dart';

/// Watch history section: one row per time any episode of the season was
/// watched, with the episode number, the date, how the play was recorded
/// (Manual / Checked In / Scrobbled) and a delete button that asks for
/// confirmation before removing the entry from the local store.
class SeasonWatchHistory extends StatelessWidget {
  final int season;
  final List<SeasonWatchEntry> entries;

  const SeasonWatchHistory({required this.season, required this.entries, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DetailsSection(
      title: 'History',
      child: entries.isEmpty
          ? DetailsCard(
              child: Text(
                'You have not watched any episode of this season yet',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
            )
          : DetailsCard(
              padding: ScreenSizeUtil.fromLTRB(6, 2, 6, 2),
              child: Column(
                children: [
                  for (int i = 0; i < entries.length; i++) ...[
                    if (i > 0) Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    _HistoryRow(season: season, entry: entries[i]),
                  ],
                ],
              ),
            ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final int season;
  final SeasonWatchEntry entry;

  const _HistoryRow({required this.season, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: ScreenSizeUtil.fromLTRB(8, 4, 0, 4),
      child: Row(
        children: [
          Icon(_actionIcon(entry.action), size: ScreenSizeUtil.calculateSize(18), color: colorScheme.onSurfaceVariant),
          SizedBox(width: ScreenSizeUtil.calculateSize(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Entries span the whole season, so each row names its episode.
                    Text(
                      _episodeLabel,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colorScheme.primary),
                    ),
                    SizedBox(width: ScreenSizeUtil.calculateSize(8)),
                    Expanded(
                      child: Text(
                        DateFormat.yMMMd().add_jm().format(entry.watchedAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                Text(_actionLabel(entry.action), style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            iconSize: ScreenSizeUtil.calculateSize(20),
            tooltip: 'Delete this watch entry',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  String get _episodeLabel => 'S${season}E${entry.episode}';

  Future<void> _confirmDelete(BuildContext context) async {
    final bloc = context.read<SeasonDetailsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final dateLabel = DateFormat.yMMMd().add_jm().format(entry.watchedAt);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete watch entry?'),
        content: Text('This removes the $_episodeLabel watch from $dateLabel from your history. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final success = await bloc.deleteHistoryEntry(entry.historyId);
    if (!success) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not delete the watch entry. Please try again.')));
    }
  }

  static IconData _actionIcon(HistoryAction action) {
    switch (action) {
      case HistoryAction.checkin:
        return Icons.where_to_vote_outlined;
      case HistoryAction.scrobble:
        return Icons.play_circle_outline;
      case HistoryAction.watch:
        return Icons.edit_calendar_outlined;
    }
  }

  static String _actionLabel(HistoryAction action) {
    switch (action) {
      case HistoryAction.checkin:
        return 'Checked In';
      case HistoryAction.scrobble:
        return 'Scrobbled';
      case HistoryAction.watch:
        return 'Manual';
    }
  }
}
