import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/library/rating_service.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/heart_rating_img.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The details-page Ratings card, shared by all four detail pages.
///
/// Two parts: the community ratings on top — TMDB and IMDb, whichever [externalRatings] has —
/// as brand-tinted columns sharing a single row, and a full-width 10-heart bar for the user's own
/// rating at the bottom. On the movie, show and episode pages the bar is interactive: tapping or
/// dragging a heart submits the new value through [onRate]; the caption beneath reads
/// "7/10 · Your rating" once rated — with a Remove link firing [onRemoveRating] — and invites a
/// first rating otherwise. On the season page ([RatingsCard.season]) the bar is read-only and
/// shows the average of the user's episode ratings instead, since seasons are not rated directly.
///
/// While no external rating has loaded (or none exists) the top row is a single muted
/// "No ratings yet" placeholder, so the user-rating bar keeps its card instead of floating
/// alone under the header. [userRating] is the 1-10 value as a string, null/empty when the user
/// has not rated.
class RatingsCard extends StatelessWidget {
  final String? userRating;
  final ExternalRatings? externalRatings;

  /// True on the season page: the TMDB score is derived (the vote-count-weighted average of
  /// the season's episodes, captioned as such), there is never an IMDb half, because seasons
  /// have no IMDb id, and the heart bar is a read-only [episodeAverage].
  final bool seasonMode;

  /// Season page only: the mean of the user's episode ratings, null while no episode is rated.
  final SeasonRatingAverage? episodeAverage;

  /// Called with the 1-10 value when the user sets a rating from the heart bar. Null disables
  /// the bar while an action is already in flight.
  final void Function(int rating)? onRate;

  /// Called when the user taps the caption's Remove link. Null hides the link — nothing rated
  /// yet, or the same conditions that disable [onRate].
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
    final halves = external.isEmpty ? [_PlaceholderHalf(colorScheme)] : external;

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
            _horizontalDivider(colorScheme),
            if (seasonMode) _episodeAverageRow(colorScheme) else _userRatingRow(colorScheme),
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

  /// The full-width interactive user row: 10 hearts filled to the current rating, caption below.
  ///
  /// The hearts flip optimistically — the bloc emits the new value before the API call — and
  /// [RatingBar] snaps back on failure because the reverted [userRating] prop change reaches its
  /// `didUpdateWidget`. Empty hearts are faded so an unrated bar reads as an affordance, not a
  /// zero score.
  Widget _userRatingRow(ColorScheme colorScheme) {
    final parsed = int.tryParse(userRating ?? '') ?? 0;
    final rated = parsed > 0;

    return Column(
      children: [
        RatingBar(
          initialRating: parsed.toDouble(),
          minRating: 1,
          allowHalfRating: false,
          itemCount: 10,
          itemSize: ScreenSizeUtil.calculateSize(26),
          itemPadding: EdgeInsets.symmetric(horizontal: ScreenSizeUtil.calculateSize(2)),
          glowColor: ThemeColors.primary,
          ignoreGestures: onRate == null,
          ratingWidget: RatingWidget(
            full: HeartWidgetUtil.fullImage(ThemeColors.primary, 26, 26),
            half: HeartWidgetUtil.halfImage(ThemeColors.primary, 26, 26),
            empty: HeartWidgetUtil.emptyImage(ThemeColors.primary.withValues(alpha: 0.45), 26, 26),
          ),
          onRatingUpdate: (value) {
            final next = value.round();
            if (next == parsed) return;
            onRate?.call(next);
          },
        ),
        SizedBox(height: ScreenSizeUtil.calculateSize(6)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rated ? '$parsed/10 · Your rating' : 'What did you think? Tap to rate',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
            if (rated && onRemoveRating != null) ...[
              Text(' · ', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              GestureDetector(
                onTap: onRemoveRating,
                child: Text('Remove', style: TextStyle(fontSize: 11, color: colorScheme.primary)),
              ),
            ],
          ],
        ),
      ],
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

/// The top row's stand-in while there is nothing to show: keeps the row's height and the card's
/// shape so the heart bar below does not jump when a rating does arrive.
class _PlaceholderHalf extends StatelessWidget {
  final ColorScheme colorScheme;

  const _PlaceholderHalf(this.colorScheme);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.star_border_rounded, size: 28, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        SizedBox(width: ScreenSizeUtil.calculateSize(10)),
        Text(
          'No ratings yet',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
      ],
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        SizedBox(width: ScreenSizeUtil.calculateSize(10)),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(caption, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}
