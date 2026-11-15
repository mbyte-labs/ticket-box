import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';

/// Red eye-off badge marking the details page's show as dropped.
///
/// The persistent half of the dropped cue: the [DetailsDroppedNotice] strip below the hero bar
/// explains the state and offers the way out, but scrolls away, so this survives in the pinned app
/// bar. Sits left of the watched badge, furthest from the overflow menu. Carries the same border and
/// drop shadow as [DetailsWatchedBadge] so it stays legible against the banner artwork behind it,
/// and takes the scheme's error colour to match the destructive framing [DetailsOverflowMenu] gives
/// ignoring.
class DetailsDroppedBadge extends StatelessWidget {
  const DetailsDroppedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final size = ScreenSizeUtil.calculateSize(26);

    return Tooltip(
      message: 'Dropped',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.0),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Icon(Icons.visibility_off_outlined, color: Colors.white, size: ScreenSizeUtil.calculateSize(16)),
      ),
    );
  }
}
