import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ticketbox/service/artwork/cache/artwork_cache.dart';
import 'package:ticketbox/service/screen_size_util.dart';

/// Hero app bar background for the person page: the headshot blurred as a backdrop, with a sharp
/// rounded portrait and the person's name in front.
///
/// The shared [DetailsHeroBanner] stretches its image edge-to-edge, which suits wide movie
/// backdrops but crops a 2:3 headshot into the middle of the face. Blurring the photo behind a
/// clean portrait keeps the artwork filling the bar without the crop mattering, and puts the name
/// on screen while the bar is expanded — the collapsed app bar title only fades in on scroll.
///
/// A null [photoUrl] renders as a plain surface fill for the same reason [DetailsHeroBanner]
/// documents: the bar is built before the page data loads, so null means "still loading" just as
/// often as "no photo available". Opened from a cast card, the page already starts with that card's
/// name and headshot (`PersonRouteArgs`), so the header is usually filled from the first frame and
/// stays that way even if the person request then fails.
class PersonHeroHeader extends StatelessWidget {
  final String? photoUrl;
  final String? name;

  /// Department, life line and birthplace in one line (see `PersonTextFormat.metaLine`); null
  /// while loading or when TMDB knows none of them.
  final String? metaLine;

  const PersonHeroHeader({required this.photoUrl, required this.name, this.metaLine, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final url = photoUrl;

    final portraitFallback = ColoredBox(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Center(
        child: Icon(Icons.person_outline, size: ScreenSizeUtil.calculateSize(40), color: colorScheme.onSurfaceVariant),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (url == null || url.isEmpty)
          ColoredBox(color: colorScheme.surface)
        else
          // The backdrop is heavily blurred, so it decodes at a fraction of the screen width —
          // a bigger source would only cost memory without adding visible detail.
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20, tileMode: TileMode.clamp),
            child: CachedNetworkImage(
              imageUrl: url,
              cacheManager: ArtworkCache.manager,
              fit: BoxFit.cover,
              memCacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context) / 4).round(),
              placeholder: (context, url) => ColoredBox(color: colorScheme.surface),
              errorWidget: (context, url, error) => ColoredBox(color: colorScheme.surface),
            ),
          ),
        // Uniform darkening keeps the foreground legible over a bright blur, and the bottom
        // gradient fades the bar into the page surface — same stops as DetailsHeroBanner.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.35, 0.55, 1.0],
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0.35),
                colorScheme.surface.withValues(alpha: 0.95),
              ],
            ),
          ),
        ),
        Padding(
          // Left inset clears nothing in particular (the drawer button sits at the top, the
          // portrait at the bottom), it just matches the page gutter.
          padding: ScreenSizeUtil.fromLTRB(16, 0, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                height: ScreenSizeUtil.calculateSize(150),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: url == null || url.isEmpty
                        ? portraitFallback
                        : CachedNetworkImage(
                            imageUrl: url,
                            cacheManager: ArtworkCache.manager,
                            fit: BoxFit.cover,
                            memCacheWidth: (ScreenSizeUtil.calculateSize(100) * MediaQuery.devicePixelRatioOf(context)).round(),
                            placeholder: (context, url) => portraitFallback,
                            errorWidget: (context, url, error) => portraitFallback,
                          ),
                  ),
                ),
              ),
              SizedBox(width: ScreenSizeUtil.calculateSize(14)),
              Expanded(
                child: Padding(
                  padding: ScreenSizeUtil.fromLTRB(0, 0, 0, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      if (metaLine != null) ...[
                        SizedBox(height: ScreenSizeUtil.calculateSize(4)),
                        Text(
                          metaLine!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
