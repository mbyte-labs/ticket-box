import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/details/common/details_breadcrumb.dart';

/// Breadcrumb-style context header shown right under the app bar:
/// `<show name> › Season N › E<n> · <episode name>`.
///
/// Replaces the old bottom tab bar. The show and season crumbs are tappable
/// chips opening their details pages; the episode crumb is the current page
/// and is plain emphasized text.
class EpisodeContextBreadcrumb extends StatelessWidget {
  final int showTmdbId;
  final int season;
  final String? showTitle;
  final int episode;
  final String? episodeTitle;

  const EpisodeContextBreadcrumb({
    required this.showTmdbId,
    required this.season,
    required this.showTitle,
    required this.episode,
    required this.episodeTitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final seasonLabel = season == 0 ? 'Specials' : 'Season $season';
    final title = episodeTitle;
    final episodeLabel = title == null || title.isEmpty ? 'Episode $episode' : 'E$episode · $title';

    return DetailsBreadcrumb(
      crumbs: [
        BreadcrumbCrumb(
          icon: Icons.tv_outlined,
          label: showTitle ?? 'Show details',
          onTap: () => PosterNavigation.showNavigateRaw(context, showTmdbId),
        ),
        BreadcrumbCrumb(
          icon: Icons.video_library_outlined,
          label: seasonLabel,
          onTap: () => PosterNavigation.seasonNavigateRaw(context, showTmdbId, season),
        ),
      ],
      currentLabel: episodeLabel,
    );
  }
}
