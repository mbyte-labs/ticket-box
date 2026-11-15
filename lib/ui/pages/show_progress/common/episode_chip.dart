import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_details.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// One `✓ 6x1` / `✗ 6x7` chip inside an expanded season - green when watched, red when not.
class EpisodeChip extends StatelessWidget {
  final EpisodeProgressDetails episode;

  const EpisodeChip(this.episode, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = episode.completed ? ThemeColors.success : ThemeColors.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(episode.completed ? Icons.check : Icons.close, size: ScreenSizeUtil.calculateSize(14), color: color),
        SizedBox(width: ScreenSizeUtil.calculateSize(2)),
        Text(episode.label, style: TextStyle(color: color)),
      ],
    );
  }
}
