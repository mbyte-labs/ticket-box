import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Heart badge marking the details page's movie or show as one of the user's favorites.
///
/// Lives in the pinned app bar, like [DetailsDroppedBadge] and [DetailsWatchedBadge], so it
/// survives the bar collapsing; same border and drop shadow as those so it stays legible against
/// the banner artwork. Sits furthest from the overflow menu that toggles it.
class DetailsFavoriteBadge extends StatelessWidget {
  const DetailsFavoriteBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final size = ScreenSizeUtil.calculateSize(26);

    return Tooltip(
      message: 'Favorite',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: ThemeColors.favorite,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.0),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Icon(Icons.favorite, color: Colors.white, size: ScreenSizeUtil.calculateSize(16)),
      ),
    );
  }
}
