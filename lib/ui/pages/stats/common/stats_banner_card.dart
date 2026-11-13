import 'package:flutter/material.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/artwork/artwork_image.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_artwork_placeholder.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// One movie or show as a backdrop card: the image, a scrim fading to black at the bottom and,
/// on top of it, a badge, the title and an optional subtitle, with an optional [action] (a
/// button) in the bottom-right corner. Tapping anywhere else opens the title's details page.
class StatsBannerCard extends StatelessWidget {
  /// The movie or show; a season or episode key opens and draws its show.
  final MediaKey mediaKey;

  /// The title's backdrop; null while its artwork is not loaded yet. A ref without a path (the
  /// title has no backdrop) draws the placeholder too.
  final ArtworkRef? banner;

  /// The short uppercase label in the primary-colored chip, e.g. `OLDEST · 1975`.
  final String badge;

  /// Empty when the title's row is not in the local library; a generic label is shown then.
  final String title;
  final String? subtitle;
  final double aspectRatio;
  final Widget? action;

  const StatsBannerCard({
    required this.mediaKey,
    required this.banner,
    required this.badge,
    required this.title,
    this.subtitle,
    this.aspectRatio = 2,
    this.action,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final type = mediaKey.showKey.type;
    final banner = this.banner;
    final subtitle = this.subtitle;
    final action = this.action;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                if (banner == null)
                  StatsArtworkPlaceholder(type)
                else
                  ArtworkImage(
                    ref: banner,
                    fit: BoxFit.cover,
                    // Decode at the banner's own width rather than the backdrop's full resolution.
                    memCacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round(),
                    // A plain fill rather than a spinner: the banner is decoration, not content.
                    placeholder: (context) => StatsArtworkPlaceholder(type),
                    errorWidget: (context) => StatsArtworkPlaceholder(type),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.4, 1.0],
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.85)],
                    ),
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: () => _open(context)),
                ),
                Padding(
                  padding: ScreenSizeUtil.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // The text passes taps through to the InkWell underneath; only the action
                      // takes its own.
                      Expanded(
                        child: IgnorePointer(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(color: ThemeColors.primary, borderRadius: BorderRadius.circular(6)),
                                child: Padding(
                                  padding: ScreenSizeUtil.fromLTRB(8, 3, 8, 3),
                                  child: Text(
                                    badge,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: ThemeColors.white,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: ScreenSizeUtil.calculateSize(6)),
                              Text(
                                title.isEmpty ? (type == ItemType.movie ? 'A movie' : 'A show') : title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  color: ThemeColors.white,
                                  fontWeight: FontWeight.w700,
                                  shadows: const [Shadow(blurRadius: 6)],
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(color: ThemeColors.white.withValues(alpha: 0.75)),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (action != null) ...[SizedBox(width: ScreenSizeUtil.calculateSize(8)), action],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final key = mediaKey.showKey;
    if (key.type == ItemType.movie) {
      PosterNavigation.movieNavigateRaw(context, key.tmdbId);
    } else {
      PosterNavigation.showNavigateRaw(context, key.tmdbId);
    }
  }
}
