import 'package:flutter/material.dart';
import 'package:ticketbox/service/person/person_credit.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/details/person/widgets/person_credit_card.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// A titled grid of [PersonCreditCard]s — the "Seen with" and "Filmography" sections of the person
/// page — each tile opening that title's own details page, by TMDB id (the details pages fetch
/// through on a cache miss, so a title needs no local row to be opened).
///
/// Exposed as slivers rather than as a widget, patterned directly on `ShowSeasonsGrid`: a
/// `SliverGrid` cannot nest inside the page's other sections (a `SliverList`), so it has to sit
/// directly in the page's `CustomScrollView.slivers`. That also keeps it viewport-lazy — only the
/// visible rows mount, which is what makes an uncapped filmography affordable.
class PersonCreditGrid {
  const PersonCreditGrid._();

  /// Fixed rather than max-extent based: `SliverGridDelegateWithMaxCrossAxisExtent` derives its
  /// count with a ceiling, so the layout would silently flip between 3 and 4 columns across phone
  /// widths. Pinning the count keeps every phone at 3-up and lets the cell width scale with the
  /// screen instead.
  static const _crossAxisCount = 3;

  /// The section's slivers: the header (with [headerTrailing] on its right, when given) over the
  /// grid, or over [emptyText] when there is nothing to show — a section is never hidden, so the
  /// user can tell "nothing here" from "not loaded".
  static List<Widget> slivers(
    BuildContext context, {
    required String title,
    required List<PersonCredit> credits,
    required String emptyText,
    Widget? headerTrailing,
  }) {
    final gutter = ScreenSizeUtil.fromLTRB(12, 0, 12, 0);

    // Same gutter DetailsSection applies, so the header lines up with the sections above it.
    final header = SliverToBoxAdapter(
      child: Padding(
        padding: ScreenSizeUtil.fromLTRB(12, 18, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: DetailsSectionHeader(title)),
            ?headerTrailing,
          ],
        ),
      ),
    );

    if (credits.isEmpty) {
      return [
        header,
        SliverToBoxAdapter(
          child: Padding(
            padding: gutter,
            child: Text(emptyText, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
      ];
    }

    return [
      header,
      SliverLayoutBuilder(
        builder: (context, constraints) {
          final gutterWidth = ScreenSizeUtil.calculateSize(12) * 2;
          final spacing = ScreenSizeUtil.calculateSize(8);
          // The cell is the 2:3 poster plus the fixed text block, computed from the actual cell
          // width rather than guessed as an aspect ratio, so the text never overflows the tile on
          // a narrow phone and never leaves a gap on a wide one.
          final cellWidth = (constraints.crossAxisExtent - gutterWidth - spacing * (_crossAxisCount - 1)) / _crossAxisCount;
          final cellHeight =
              cellWidth / PosterConstants.aspectRationWhenNoTitle + ScreenSizeUtil.calculateSize(PersonCreditCard.textBlockHeight);

          return SliverPadding(
            padding: gutter,
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _crossAxisCount,
                mainAxisExtent: cellHeight,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
                final credit = credits[index];

                // Keyed by kind and id: a movie and a show can share a TMDB id, and the filter
                // re-parents tiles between renders.
                return PersonCreditCard(
                  key: ValueKey(credit.gridKey),
                  credit: credit,
                  onTap: () => PosterNavigation.navigateToKey(context, credit.key),
                );
              }, childCount: credits.length),
            ),
          );
        },
      ),
    ];
  }
}
