import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/mark_as_watched_btn.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';
import 'package:ticketbox/ui/pages/details/common/details_watched_status.dart';
import 'package:ticketbox/ui/theme/action_colors.dart';

/// The action row shared by the show, season and episode details pages: one prominent
/// mark-as-watched control plus a watchlist toggle.
///
/// Deliberately only two controls. The third action the pages expose — ignoring the show — is
/// destructive and show-wide, so it lives in the app bar's overflow menu instead of competing
/// with these for attention.
///
/// The mark-as-watched control is a three-state affair driven by [status]: a filled call to
/// action while nothing is watched, an outlined progress readout while partly watched, and an
/// outlined check + date once complete. It stays tappable throughout so a rewatch can be logged.
class DetailsActionBar extends StatelessWidget {
  final DetailsWatchedStatus status;
  final bool watchListed;
  final DetailsPendingAction? pendingAction;
  final VoidCallback onMarkAsWatched;
  final ValueChanged<bool> onWatchListedChanged;

  const DetailsActionBar({
    required this.status,
    required this.watchListed,
    required this.pendingAction,
    required this.onMarkAsWatched,
    required this.onWatchListedChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actions = context.actionColors;
    // Any in-flight action blocks the whole row: both controls write the same local library state,
    // and a reload is already queued behind the one that is running.
    final isBusy = pendingAction != null;
    final toggleSize = ScreenSizeUtil.calculateSize(48);

    return Padding(
      padding: ScreenSizeUtil.fromLTRB(12, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MarkAsWatchedButton(
                  isHollow: !status.isNone,
                  label: status.label,
                  icon: status.isComplete ? Icons.check_circle : null,
                  onPressed: isBusy ? null : onMarkAsWatched,
                ),
                if (status.showProgress)
                  Padding(
                    padding: ScreenSizeUtil.fromLTRB(2, 6, 2, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: status.progress,
                        minHeight: ScreenSizeUtil.calculateSize(4),
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(actions.markWatchedAccent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: ScreenSizeUtil.calculateSize(10)),
          SizedBox(
            width: toggleSize,
            height: toggleSize,
            child: pendingAction == DetailsPendingAction.watchlist
                ? Center(
                    child: SizedBox(
                      width: ScreenSizeUtil.calculateSize(20),
                      height: ScreenSizeUtil.calculateSize(20),
                      // Same blue as the button it replaces, so the busy state still reads as
                      // the watchlist control rather than as generic chrome.
                      child: CircularProgressIndicator(strokeWidth: 2, color: actions.watchlistAccent),
                    ),
                  )
                : IconButton.filled(
                    isSelected: watchListed,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    selectedIcon: const Icon(Icons.bookmark_added),
                    tooltip: watchListed ? 'Remove from Watchlist' : 'Add to Watchlist',
                    // Filled blue once on the watchlist, hollow blue while off it, so the state is
                    // readable without relying on the icon swap alone.
                    style: IconButton.styleFrom(
                      backgroundColor: watchListed ? actions.watchlist : Colors.transparent,
                      foregroundColor: watchListed ? actions.onAction : actions.watchlistAccent,
                      side: BorderSide(color: watchListed ? actions.watchlist : actions.watchlistAccent),
                    ),
                    onPressed: isBusy ? null : () => onWatchListedChanged(!watchListed),
                  ),
          ),
        ],
      ),
    );
  }
}
