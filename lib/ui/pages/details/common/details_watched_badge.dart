import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/action_colors.dart';

/// Purple check badge marking the details page's subject as fully watched.
///
/// Rendered as an app bar action so the cue survives the hero bar collapsing. Matches the
/// poster grids' watched pill, and carries its own drop shadow and border so it stays legible
/// against the banner artwork behind it.
class DetailsWatchedBadge extends StatelessWidget {
  const DetailsWatchedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final size = ScreenSizeUtil.calculateSize(26);
    final color = context.actionColors.markWatched;

    return Tooltip(
      message: 'Watched',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.0),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Icon(Icons.check, color: Colors.white, size: ScreenSizeUtil.calculateSize(16)),
      ),
    );
  }
}
