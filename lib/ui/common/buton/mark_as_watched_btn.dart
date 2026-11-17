import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/theme/action_colors.dart';

class MarkAsWatchedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool includeRateTxt;

  /// If hollow is true, then the button is basically an Outlined button
  final bool isHollow;

  /// Overrides the label, for callers that report a state rather than prompt an action — the
  /// details pages' `Watched · <date>` and `12 / 24 watched`. Ignored when null.
  final String? label;

  /// Leading icon, used by the details pages to mark the watched state. Ignored when null.
  final IconData? icon;

  const MarkAsWatchedButton({this.onPressed, this.includeRateTxt = false, this.isHollow = false, this.label, this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    final text = label ?? (includeRateTxt ? 'Rate & Mark as Watched' : 'Mark As Watched');
    final textWidget = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

    final actions = context.actionColors;
    final leading = icon;

    if (isHollow) {
      // The outlined variant draws the violet straight onto the dark surface, so it takes the
      // lighter accent; the filled variant below sits behind white and takes the fill colour.
      final style = OutlinedButton.styleFrom(
        side: BorderSide(color: actions.markWatchedAccent),
        foregroundColor: actions.markWatchedAccent,
      );
      if (leading == null) {
        return OutlinedButton(onPressed: onPressed, style: style, child: textWidget);
      }
      return OutlinedButton.icon(onPressed: onPressed, style: style, icon: Icon(leading, size: 18), label: textWidget);
    }

    final style = ElevatedButton.styleFrom(
      backgroundColor: actions.markWatched,
      foregroundColor: actions.onAction,
      side: BorderSide(color: actions.markWatched),
    );
    if (leading == null) {
      return ElevatedButton(style: style, onPressed: onPressed, child: textWidget);
    }
    return ElevatedButton.icon(style: style, onPressed: onPressed, icon: Icon(leading, size: 18), label: textWidget);
  }
}
