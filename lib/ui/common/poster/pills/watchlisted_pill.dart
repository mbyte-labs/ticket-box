import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/action_colors.dart';

/// Marks a poster as being on the watchlist. Blue, matching the details page's watchlist toggle.
class WatchlistedPill extends StatelessWidget {
  const WatchlistedPill({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = context.actionColors;

    return Container(
      decoration: BoxDecoration(
        color: actions.watchlist.withValues(alpha: 0.9),
        // borderRadius: const BorderRadius.only(
        //   bottomLeft: Radius.circular(10),
        //   bottomRight: Radius.circular(10),
        // ),
      ),
      padding: ScreenSizeUtil.fromLTRB(2, 0, 2, 2),
      child: Icon(Icons.list_rounded, color: actions.onAction, size: ScreenSizeUtil.calculateSize(20)),
    );
  }
}
