import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// A thin horizontal meter: a dark track with [fraction] of it filled in [color]. Deliberately
/// not a [LinearProgressIndicator]: this is watched data, not loading, so it never wears the
/// theme's loading pink.
class StatsMeter extends StatelessWidget {
  final double fraction;
  final Color color;

  /// Height in logical (unscaled) pixels.
  final double height;

  const StatsMeter({required this.fraction, required this.color, this.height = 8, super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: ScreenSizeUtil.calculateSize(height),
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: ThemeColors.dark4)),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.clamp(0.0, 1.0),
                child: ColoredBox(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
