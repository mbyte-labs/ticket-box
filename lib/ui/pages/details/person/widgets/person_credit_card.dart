import 'package:flutter/material.dart';
import 'package:ticketbox/service/person/person_credit.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/poster_item_background.dart';
import 'package:ticketbox/ui/common/poster/poster_pills_bottom_right.dart';
import 'package:ticketbox/ui/common/poster/poster_pills_top_left.dart';
import 'package:ticketbox/ui/common/poster/poster_pills_top_right.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// One filmography tile: the title's poster with the library marks over it, and the title, year,
/// character and episode count under it.
///
/// Like every tile this has no bloc and watches no row: everything it shows is already in the
/// [PersonCredit] it was built from, so it is a plain stateless widget that rebuilds only when
/// the page's state does. The poster body and pills are the shared ones, fed a [PosterModel]
/// built from the credit — so the grid looks like every other grid in the app.
class PersonCreditCard extends StatelessWidget {
  final PersonCredit credit;
  final VoidCallback onTap;

  const PersonCreditCard({required this.credit, required this.onTap, super.key});

  /// Height reserved under the poster for the three text lines, so every cell lays out the same
  /// whether or not a line is present. Sized for a ~320 px phone at the default text scale.
  static const textBlockHeight = 58.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final details = _posterModelFor(credit);
    final subtitle = [if (credit.year != null) '${credit.year}', if (credit.character != null) credit.character!].join(' · ');
    final episodes = credit.episodes;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: PosterConstants.aspectRationWhenNoTitle,
          child: GestureDetector(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterItemBackground(details),
                PosterTopLeftPills(details),
                PosterTopRightPills(details),
                PosterBottomRightPills(details),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: ScreenSizeUtil.fromLTRB(3, 0, 0, 3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (credit.inLibrary && !credit.watched) ...[
                          const _KindChip('In library', accent: true),
                          SizedBox(height: ScreenSizeUtil.calculateSize(2)),
                        ],
                        _KindChip(credit.kind.label),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: ScreenSizeUtil.calculateSize(textBlockHeight),
          child: Column(
            children: [
              Container(
                margin: PosterConstants.titleMargin,
                child: Text(
                  credit.title,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle.isNotEmpty)
                Container(
                  margin: PosterConstants.subTitleMargin,
                  child: Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (episodes != null)
                Text(
                  episodes == 1 ? '1 episode' : '$episodes episodes',
                  style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The shared poster widgets take the grids' tile model. This builds one from the credit: the
  /// marks are the credit's own flags, and `tracked` is the credit's in-library flag, so a title
  /// the user has in the library resolves its artwork from disk like any other tile.
  static PosterModel _posterModelFor(PersonCredit credit) {
    return PosterModel(
      key: credit.key,
      title: credit.title,
      noPosterText: credit.title,
      posterPath: credit.posterPath,
      tracked: credit.inLibrary,
      rating: credit.rating?.toStringAsFixed(1),
      marks: LibraryMarks(watched: credit.watched, watchListed: credit.watchlisted, userRating: credit.userRating?.toString()),
    );
  }
}

/// A small label in the poster's bottom-left corner: the title's kind, or "In library" for a
/// title the user has started, listed or rated but not finished (a finished one carries the
/// shared watched pill instead).
class _KindChip extends StatelessWidget {
  final String label;
  final bool accent;

  const _KindChip(this.label, {this.accent = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: (accent ? colorScheme.primary : colorScheme.surfaceContainerHighest).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: ScreenSizeUtil.fromLTRB(4, 1, 4, 1),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: accent ? colorScheme.onPrimary : colorScheme.onSurface),
        ),
      ),
    );
  }
}
