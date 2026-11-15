import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ticketbox/service/artwork/cache/artwork_cache.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/link_opener.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_provider.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';

/// Watch now section: the streaming services carrying this title in the user's country
/// (JustWatch data via TMDB).
///
/// Shared by all four details pages. What each one passes in differs in scope: a show's list is
/// the union across its seasons, while the season and episode pages ask TMDB about that season or
/// episode specifically and so can legitimately show fewer services than the show page.
///
/// Tapping any logo — or the attribution — opens [link], the JustWatch offer page for this title
/// in this region. Every logo opens the same page because that is all TMDB gives: one link per
/// payload, not one per service — and on the season and episode pages that link is the *show's*
/// page, since TMDB scopes the provider list per level but not the link. A null [link] leaves the
/// tiles inert rather than hiding them; the logos are still worth showing on their own.
///
/// Renders nothing while no streaming country is set (the up-next dashboard carries the
/// "set your country" nudge) or when no service streams the title there; otherwise a horizontal
/// logo row followed by the JustWatch attribution TMDB's terms require.
class DetailsWatchProviders extends StatelessWidget {
  final bool regionSet;
  final List<DetailsWatchProvider> providers;
  final String? link;

  const DetailsWatchProviders({required this.regionSet, required this.providers, this.link, super.key});

  @override
  Widget build(BuildContext context) {
    if (!regionSet || providers.isEmpty) {
      return const SizedBox.shrink();
    }

    return DetailsSection(title: 'Watch now', child: _ProviderRow(providers, link));
  }
}

class _ProviderRow extends StatelessWidget {
  final List<DetailsWatchProvider> providers;
  final String? link;

  const _ProviderRow(this.providers, this.link);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final link = this.link;

    final attribution = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Powered by', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        SizedBox(width: ScreenSizeUtil.calculateSize(6)),
        Image.asset(AssetsPath.justWatchLogo, height: ScreenSizeUtil.calculateSize(14)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: ScreenSizeUtil.calculateSize(56),
          width: double.infinity,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: providers.length,
            itemBuilder: (context, index) {
              return Container(
                margin: ScreenSizeUtil.fromLTRB(0, 0, 8, 0),
                width: ScreenSizeUtil.calculateSize(56),
                child: _ProviderLogo(providers[index], link),
              );
            },
          ),
        ),
        SizedBox(height: ScreenSizeUtil.calculateSize(8)),
        if (link == null)
          attribution
        else
          InkWell(
            onTap: () => unawaited(openExternalLink(context, link)),
            child: Padding(padding: ScreenSizeUtil.fromLTRB(0, 2, 4, 2), child: attribution),
          ),
      ],
    );
  }
}

class _ProviderLogo extends StatelessWidget {
  final DetailsWatchProvider provider;
  final String? link;

  const _ProviderLogo(this.provider, this.link);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logoUrl = provider.logoUrl;
    final link = this.link;

    final fallback = ColoredBox(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Center(child: Icon(Icons.live_tv_outlined, color: colorScheme.onSurfaceVariant)),
    );

    return Tooltip(
      message: provider.name,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (logoUrl == null)
                fallback
              else
                CachedNetworkImage(
                  imageUrl: logoUrl,
                  cacheManager: ArtworkCache.manager,
                  fit: BoxFit.cover,
                  // Decode at tile width instead of the source resolution.
                  memCacheWidth: (ScreenSizeUtil.calculateSize(56) * MediaQuery.devicePixelRatioOf(context)).round(),
                  placeholder: (context, url) => fallback,
                  errorWidget: (context, url, error) => fallback,
                ),
              // Layered over the logo rather than wrapped around it so the ripple paints on top of
              // the image instead of behind it, clipped to the same rounded corners.
              Material(
                color: Colors.transparent,
                child: InkWell(onTap: link == null ? null : () => unawaited(openExternalLink(context, link))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
