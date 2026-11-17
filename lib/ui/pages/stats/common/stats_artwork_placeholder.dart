import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// What a stats banner or poster shows while its image loads, or when the title has none.
class StatsArtworkPlaceholder extends StatelessWidget {
  final ItemType type;

  /// Icon size in logical (unscaled) pixels.
  final double iconSize;

  const StatsArtworkPlaceholder(this.type, {this.iconSize = 48, super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Align(
        alignment: const Alignment(0, -0.3),
        child: Icon(
          type == ItemType.movie ? Icons.movie_outlined : Icons.tv_outlined,
          size: ScreenSizeUtil.calculateSize(iconSize),
          color: ThemeColors.greyScale500.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
