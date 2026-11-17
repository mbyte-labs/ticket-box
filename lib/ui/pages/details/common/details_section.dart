import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';

/// Shared layout primitives for the details pages (episode, season, ...) so every
/// page uses one gutter, one header style and one card style.

/// A titled page section: small-caps header + content, with the standard
/// page gutter applied.
class DetailsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const DetailsSection({required this.title, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ScreenSizeUtil.fromLTRB(12, 18, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [DetailsSectionHeader(title), child]),
    );
  }
}

/// The small-caps header of a [DetailsSection], on its own so a section whose
/// content has to be a sliver (and therefore cannot sit inside [DetailsSection])
/// can still render an identical header. Does not apply the page gutter — the
/// caller supplies it.
class DetailsSectionHeader extends StatelessWidget {
  final String title;

  const DetailsSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: ScreenSizeUtil.fromLTRB(2, 0, 2, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Soft rounded container used as the background of section content.
class DetailsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const DetailsCard({required this.child, this.padding, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: padding ?? ScreenSizeUtil.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
