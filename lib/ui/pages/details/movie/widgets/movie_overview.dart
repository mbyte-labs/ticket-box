import 'package:flutter/material.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';

/// Movie synopsis rendered as a titled section card, with the marketing
/// tagline as an italic lead-in line. Either half hides independently when
/// empty; the whole section hides when both are. The text stays selectable.
class MovieOverview extends StatelessWidget {
  final String? tagLine;
  final String? overview;

  const MovieOverview({required this.tagLine, required this.overview, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tagline = tagLine;
    final text = overview;
    final hasTagline = tagline != null && tagline.isNotEmpty;
    final hasOverview = text != null && text.isNotEmpty;

    if (!hasTagline && !hasOverview) {
      return const SizedBox();
    }

    return DetailsSection(
      title: 'Overview',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasTagline)
              Padding(
                padding: EdgeInsets.only(bottom: hasOverview ? 8 : 0),
                child: SelectableText(
                  tagline,
                  style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                ),
              ),
            if (hasOverview)
              SelectableText(text, style: TextStyle(fontSize: 14, height: 1.45, color: colorScheme.onSurface.withValues(alpha: 0.92))),
          ],
        ),
      ),
    );
  }
}
