import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';

/// The "you dropped this show" heads-up, with a one-tap way back.
///
/// Dropping is otherwise invisible — before this the only cue was the overflow menu item flipping
/// its label — so every details page carries this strip whenever its show is marked dropped
/// locally. It states the consequence rather than just the state, because that is what the user
/// actually needs reminding of.
///
/// Renders nothing when the show is not dropped, so callers can drop it into a section list
/// unconditionally the way [CheckInBanner] is. Borrows that banner's card recipe (neutral surface,
/// tinted border, rounded) instead of a filled error block, which would read as something having
/// gone wrong rather than a state the user chose.
class DetailsDroppedNotice extends StatelessWidget {
  /// Whether the page's show is dropped. When false the widget collapses to nothing.
  final bool dropped;

  final DetailsPendingAction? pendingAction;

  /// Clears the dropped state. Un-dropping is reversible, so unlike dropping it goes through
  /// without a confirmation prompt — same call the overflow menu makes.
  final VoidCallback onUndo;

  /// What being dropped means here. The season and episode pages override it to name the show,
  /// since dropping is always show-wide.
  final String subtitle;

  const DetailsDroppedNotice({
    required this.dropped,
    required this.pendingAction,
    required this.onUndo,
    this.subtitle = 'Hidden from your progress and Up Next lists.',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!dropped) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(ScreenSizeUtil.calculateSize(16));

    return Padding(
      padding: ScreenSizeUtil.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: colorScheme.error.withValues(alpha: 0.45)),
          ),
          child: Padding(
            padding: ScreenSizeUtil.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                const _DroppedIcon(),
                SizedBox(width: ScreenSizeUtil.calculateSize(10)),
                Expanded(child: _Labels(subtitle: subtitle)),
                SizedBox(width: ScreenSizeUtil.calculateSize(8)),
                // Swapped for the spinner while the write is in flight, so this and the overflow
                // menu never look independently actionable.
                if (pendingAction == DetailsPendingAction.ignore)
                  Padding(
                    padding: ScreenSizeUtil.fromLTRB(8, 0, 8, 0),
                    child: SizedBox(
                      width: ScreenSizeUtil.calculateSize(20),
                      height: ScreenSizeUtil.calculateSize(20),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  TextButton(onPressed: onUndo, child: const Text('Stop ignoring')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DroppedIcon extends StatelessWidget {
  const _DroppedIcon();

  @override
  Widget build(BuildContext context) {
    final size = ScreenSizeUtil.calculateSize(32);
    final color = Theme.of(context).colorScheme.error;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(Icons.visibility_off_outlined, size: ScreenSizeUtil.calculateSize(20), color: color),
    );
  }
}

class _Labels extends StatelessWidget {
  final String subtitle;

  const _Labels({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'DROPPED',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: colorScheme.error),
        ),
        SizedBox(height: ScreenSizeUtil.calculateSize(2)),
        Text(
          subtitle,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
        ),
      ],
    );
  }
}
