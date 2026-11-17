import 'dart:async';

import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/library/rating_service.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/heart_rating_img.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/details/common/rate_sheet.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The details-page Ratings card, shared by all four detail pages.
///
/// On the movie, show and episode pages it is a single row of scores: the community ratings —
/// TMDB and IMDb, whichever [externalRatings] has — as brand-tinted columns, then the user's own
/// rating as a last column with a heart. That column reads "Rate" until the user has rated and
/// "7/10" afterwards; tapping it opens the rate sheet ([showRateSheet]), where a value is picked
/// and confirmed, and the result goes out through [onRate] or [onRemoveRating].
///
/// On the season page ([RatingsCard.season]) there is nothing to rate: the community row sits
/// above a read-only 10-heart bar showing the average of the user's episode ratings.
///
/// While no external rating has loaded (or none exists) a muted "No ratings yet" placeholder
/// stands in for the community columns. [userRating] is the 1-10 value as a string, null/empty
/// when the user has not rated.
class RatingsCard extends StatelessWidget {
  final String? userRating;
  final ExternalRatings? externalRatings;

  /// True on the season page: the TMDB score is derived (the vote-count-weighted average of
  /// the season's episodes, captioned as such), there is never an IMDb half, because seasons
  /// have no IMDb id, and the heart bar is a read-only [episodeAverage].
  final bool seasonMode;

  /// Season page only: the mean of the user's episode ratings, null while no episode is rated.
  final SeasonRatingAverage? episodeAverage;

  /// Called with the 1-10 value the user confirmed in the rate sheet. Null disables the
  /// "your rating" column while an action is already in flight.
  final void Function(int rating)? onRate;

  /// Called when the user picks Remove rating in the rate sheet. Null hides that button —
  /// nothing rated yet, or the same conditions that disable [onRate].
  final void Function()? onRemoveRating;

  const RatingsCard({
    required this.userRating,
    required this.externalRatings,
    required this.onRate,
    required this.onRemoveRating,
    super.key,
  }) : seasonMode = false,
       episodeAverage = null;

  /// The season page's card: nothing to rate, the hearts display [episodeAverage].
  const RatingsCard.season({required this.externalRatings, required this.episodeAverage, super.key})
    : seasonMode = true,
      userRating = null,
      onRate = null,
      onRemoveRating = null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final external = _externalHalves();
    final halves = [
      if (external.isEmpty) _PlaceholderHalf(colorScheme) else ...external,
      if (!seasonMode) _UserRatingHalf(rating: int.tryParse(userRating ?? '') ?? 0, onRate: onRate, onRemoveRating: onRemoveRating),
    ];

    return DetailsSection(
      title: 'Ratings',
      child: DetailsCard(
        padding: ScreenSizeUtil.fromLTRB(10, 14, 10, 14),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < halves.length; i++) ...[
                    if (i > 0) VerticalDivider(width: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    Expanded(child: halves[i]),
                  ],
                ],
              ),
            ),
            if (seasonMode) ...[_horizontalDivider(colorScheme), _episodeAverageRow(colorScheme)],
          ],
        ),
      ),
    );
  }

  Widget _horizontalDivider(ColorScheme colorScheme) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ScreenSizeUtil.calculateSize(12)),
      child: Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
    );
  }

  /// The season page's read-only row: 10 hearts filled to the episode average, rounded to the
  /// nearest half heart, with the exact value and the episode count in the caption.
  Widget _episodeAverageRow(ColorScheme colorScheme) {
    final average = episodeAverage;
    final String caption;
    if (average == null) {
      caption = 'Rate episodes to see your season average';
    } else {
      final episodes = average.count == 1 ? 'episode' : 'episodes';
      caption = '${RatingService.formatAverage(average.average)}/10 · Average of your ${average.count} rated $episodes';
    }

    return Column(
      children: [
        RatingBar(
          initialRating: average == null ? 0 : (average.average * 2).round() / 2,
          allowHalfRating: true,
          itemCount: 10,
          itemSize: ScreenSizeUtil.calculateSize(26),
          itemPadding: EdgeInsets.symmetric(horizontal: ScreenSizeUtil.calculateSize(2)),
          ignoreGestures: true,
          ratingWidget: RatingWidget(
            full: HeartWidgetUtil.fullImage(ThemeColors.primary, 26, 26),
            half: HeartWidgetUtil.halfImage(ThemeColors.primary, 26, 26),
            empty: HeartWidgetUtil.emptyImage(ThemeColors.primary.withValues(alpha: 0.45), 26, 26),
          ),
          onRatingUpdate: (_) {},
        ),
        SizedBox(height: ScreenSizeUtil.calculateSize(6)),
        Text(caption, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }

  /// The visible external halves, in display order: TMDB then IMDb.
  List<Widget> _externalHalves() {
    final ratings = externalRatings;
    if (ratings == null || !ratings.hasAnyRating) {
      return const [];
    }

    final halves = <Widget>[];
    final tmdbScore = ratings.tmdbScore;
    if (tmdbScore != null && (ratings.tmdbVotes ?? 0) > 0) {
      final tmdbVotes = NumberFormat.compact().format(ratings.tmdbVotes);
      halves.add(
        _RatingHalf(
          icon: const Icon(SimpleIcons.themoviedatabase, size: 28, color: ThemeColors.brandTmdb),
          value: '${(tmdbScore * 10).truncate()}%',
          caption: seasonMode ? '$tmdbVotes votes · episode avg' : '$tmdbVotes votes',
        ),
      );
    }

    final imdbRating = ratings.imdbRating;
    if (!seasonMode && imdbRating != null) {
      halves.add(
        _RatingHalf(
          icon: const Icon(SimpleIcons.imdb, size: 28, color: ThemeColors.brandImdb),
          value: imdbRating.toStringAsFixed(1),
          caption: ratings.imdbVotes == null ? 'IMDb rating' : '${NumberFormat.compact().format(ratings.imdbVotes)} votes',
        ),
      );
    }

    return halves;
  }
}

/// The row's stand-in for the community columns while there is nothing to show, so the card
/// keeps its height and shape when a rating does arrive.
class _PlaceholderHalf extends StatelessWidget {
  final ColorScheme colorScheme;

  const _PlaceholderHalf(this.colorScheme);

  @override
  Widget build(BuildContext context) {
    return _HalfLayout(
      icon: Icon(Icons.star_border_rounded, size: 28, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
      child: Text(
        'No ratings yet',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _RatingHalf extends StatelessWidget {
  final Widget icon;
  final String value;
  final String caption;

  const _RatingHalf({required this.icon, required this.value, required this.caption});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _HalfLayout(
      icon: icon,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text(caption, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// The user's own rating as the row's last column: a heart, then "7/10" (or "Rate" while
/// unrated) over a "Your rating" caption. Tapping opens the rate sheet and forwards what the
/// user confirmed there; a null [onRate] makes the column inert.
class _UserRatingHalf extends StatelessWidget {
  /// The 1-10 rating, 0 while unrated.
  final int rating;
  final void Function(int rating)? onRate;
  final void Function()? onRemoveRating;

  const _UserRatingHalf({required this.rating, required this.onRate, required this.onRemoveRating});

  bool get _rated => rating > 0;

  Future<void> _openSheet(BuildContext context) async {
    final result = await showRateSheet(context, currentRating: _rated ? rating : null, canRemove: _rated && onRemoveRating != null);
    switch (result) {
      case RateSheetRated(rating: final picked):
        onRate?.call(picked);
      case RateSheetRemoved():
        onRemoveRating?.call();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final captionStyle = TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant);

    return Semantics(
      button: true,
      label: _rated ? 'Your rating, $rating out of 10. Change' : 'Rate',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onRate == null ? null : () => unawaited(_openSheet(context)),
          child: _HalfLayout(
            icon: _rated ? HeartWidgetUtil.fullImage(ThemeColors.primary, 28, 28) : HeartWidgetUtil.emptyImage(ThemeColors.primary, 28, 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_rated)
                  Text.rich(
                    TextSpan(
                      text: '$rating',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      children: [
                        TextSpan(
                          text: '/10',
                          style: captionStyle.copyWith(fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  )
                else
                  const Text('Rate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text('Your rating', style: captionStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One column of the scores row: [icon], a gap, then [child], centred and scaled down as a
/// whole when three columns leave it less room than it wants.
class _HalfLayout extends StatelessWidget {
  final Widget icon;
  final Widget child;

  const _HalfLayout({required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ScreenSizeUtil.calculateSize(4)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            SizedBox(width: ScreenSizeUtil.calculateSize(8)),
            child,
          ],
        ),
      ),
    );
  }
}
