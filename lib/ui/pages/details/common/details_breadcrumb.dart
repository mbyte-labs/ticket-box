import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// One tappable crumb in a [DetailsBreadcrumb].
class BreadcrumbCrumb {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const BreadcrumbCrumb({required this.icon, required this.label, required this.onTap});
}

/// Breadcrumb-style context header shown right under the app bar on the season and episode details
/// pages: `<show name> › Season N › E<n> · <episode name>`.
///
/// Ancestor pages are tappable crumbs; the current page is the trailing plain text and stays the
/// brightest element in the row, so the crumbs read as context rather than as calls to action. The
/// crumbs borrow the quiet card recipe the rest of the details pages use — a low-alpha
/// [ColorScheme.surfaceContainerHighest] fill with a hairline tinted border, same as
/// [DetailsDroppedNotice] and [CheckInBanner] — and carry the brand accent only on the leading icon,
/// so they sit at the same visual level as the [DetailsCard] sections below them.
///
/// Overflow: laid out with a [Wrap], so every crumb keeps its natural width and an overfull
/// breadcrumb flows onto a second line rather than ellipsizing. A [Row] cannot do this — it splits
/// the leftover space equally between its [Flexible] children and a child wanting less than its
/// share leaves the surplus as trailing empty space instead of donating it, which cut show titles
/// short with a third of the row still empty. Only a single crumb wider than the whole row
/// ellipsizes now. Note [Flexible] is a `Flex`-only ParentDataWidget: as a direct [Wrap] child it
/// throws "Incorrect use of ParentDataWidget", so nothing here may be wrapped in one.
class DetailsBreadcrumb extends StatelessWidget {
  /// Ancestor pages, outermost first. Must not be empty.
  final List<BreadcrumbCrumb> crumbs;

  /// The page the user is on. Rendered as plain emphasized text, not a crumb.
  final String currentLabel;

  const DetailsBreadcrumb({required this.crumbs, required this.currentLabel, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final children = <Widget>[];

    // Sized here rather than inside _Separator: a const widget reading ScreenSizeUtil would be
    // skipped by the identical-widget shortcut in Element.updateChild and keep whatever size the
    // util had on its first build.
    final separator = _Separator(size: ScreenSizeUtil.calculateSize(16), gap: ScreenSizeUtil.calculateSize(2));

    for (final crumb in crumbs) {
      children.add(_Crumb(crumb: crumb));
      children.add(separator);
    }

    children.add(
      Text(
        currentLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colorScheme.onSurface),
      ),
    );

    return Padding(
      padding: ScreenSizeUtil.fromLTRB(12, 12, 12, 0),
      // Centred because the pills are taller than the bare trailing label.
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: ScreenSizeUtil.calculateSize(6), children: children),
    );
  }
}

class _Separator extends StatelessWidget {
  final double size;
  final double gap;

  const _Separator({required this.size, required this.gap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gap),
      child: Icon(Icons.chevron_right, size: size, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
    );
  }
}

class _Crumb extends StatelessWidget {
  final BreadcrumbCrumb crumb;

  const _Crumb({required this.crumb});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(ScreenSizeUtil.calculateSize(20));

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: crumb.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: ScreenSizeUtil.fromLTRB(8, 4, 10, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The brand accent, the same red the buttons use — a dab of it on the icon is the
                // only accent the crumb gets, on purpose.
                Icon(crumb.icon, size: ScreenSizeUtil.calculateSize(14), color: ThemeColors.primary),
                SizedBox(width: ScreenSizeUtil.calculateSize(5)),
                // Legal here (this is a Row, not the outer Wrap) and still needed: a crumb whose
                // label alone exceeds the row width has to ellipsize somewhere.
                Flexible(
                  child: Text(
                    crumb.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
