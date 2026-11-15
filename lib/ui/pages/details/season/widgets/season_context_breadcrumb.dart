import 'package:flutter/material.dart';
import 'package:ticketbox/service/title_builder.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/details/common/details_breadcrumb.dart';

/// Breadcrumb-style context header shown right under the app bar:
/// `<show name> › Season N`.
///
/// The show crumb is a tappable chip opening its details page; the season crumb
/// is the current page and is plain emphasized text.
class SeasonContextBreadcrumb extends StatelessWidget {
  final int showTmdbId;
  final int season;
  final String? showTitle;

  const SeasonContextBreadcrumb({required this.showTmdbId, required this.season, required this.showTitle, super.key});

  @override
  Widget build(BuildContext context) {
    return DetailsBreadcrumb(
      crumbs: [
        BreadcrumbCrumb(
          icon: Icons.tv_outlined,
          label: showTitle ?? 'Show details',
          onTap: () => PosterNavigation.showNavigateRaw(context, showTmdbId),
        ),
      ],
      currentLabel: ConfirmationTitleBuilder.seasonTitle(season),
    );
  }
}
