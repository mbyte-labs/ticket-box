import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/action_colors.dart';

/// Marks a poster as watched. Shares the violet of the details page's watched badge — it used to
/// be a different purple (`Colors.purple.shade700`) despite claiming otherwise.
class PosterWatchedPill extends StatelessWidget {
  const PosterWatchedPill({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = context.actionColors;

    return Container(
      decoration: BoxDecoration(
        color: actions.markWatched.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
      ),
      padding: ScreenSizeUtil.fromLTRB(2, 0, 2, 2),
      child: Icon(Icons.check, color: actions.onAction, size: ScreenSizeUtil.calculateSize(20)),
    );
  }
}
