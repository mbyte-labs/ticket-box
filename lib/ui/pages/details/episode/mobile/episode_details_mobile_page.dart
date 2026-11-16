import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/check_in/check_in_banner.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/general_widget/confirmation/mark_as_watched/mark_as_watched_widget.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/details/common/details_action_bar.dart';
import 'package:ticketbox/ui/pages/details/common/details_dropped_badge.dart';
import 'package:ticketbox/ui/pages/details/common/details_dropped_notice.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_links.dart';
import 'package:ticketbox/ui/pages/details/common/details_hero_banner.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_overflow_menu.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_providers.dart';
import 'package:ticketbox/ui/pages/details/common/details_watched_badge.dart';
import 'package:ticketbox/ui/pages/details/common/ratings_card.dart';
import 'package:ticketbox/ui/pages/details/episode/episode_details_bloc.dart';
import 'package:ticketbox/ui/pages/details/episode/episode_details_state.dart';
import 'package:ticketbox/ui/pages/details/episode/widgets/episode_actors.dart';
import 'package:ticketbox/ui/pages/details/episode/widgets/episode_context_breadcrumb.dart';
import 'package:ticketbox/ui/pages/details/episode/widgets/episode_overview.dart';
import 'package:ticketbox/ui/pages/details/episode/widgets/episode_stats.dart';
import 'package:ticketbox/ui/pages/details/episode/widgets/episode_watch_history.dart';

/// Mobile layout for the episode details page.
///
/// A collapsing hero app bar renders the episode banner with the episode title
/// overlaid; below it the content is organized into uniform sections
/// (breadcrumb, meta strip, actions, overview, ratings, watch now, cast,
/// history).
/// Sections are backed by real state read from [EpisodeDetailsState]. The
/// check-in heads-up is the app-wide [CheckInBanner], which reads the shared
/// check-in state rather than this page's.
///
/// The mutations the page offers are mark-as-watched and the watchlist toggle in
/// [DetailsActionBar], rating from the [RatingsCard]'s heart bar, ignoring the show from the app
/// bar's [DetailsOverflowMenu] or un-ignoring it from the [DetailsDroppedNotice], and deleting a
/// watch entry from the history section. The watched
/// state is surfaced twice: on the action bar's primary button and as a badge on the banner, which
/// becomes a compact badge in the app bar once the bar collapses. Starting a check-in lives one
/// level down, inside the mark-as-watched sheet, where it is the alternative to logging a finished
/// play.
class EpisodeDetailsMobilePage extends StatefulWidget {
  const EpisodeDetailsMobilePage({super.key});

  @override
  State<EpisodeDetailsMobilePage> createState() => _EpisodeDetailsMobilePageState();
}

class _EpisodeDetailsMobilePageState extends State<EpisodeDetailsMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EpisodeDetailsBloc>().init();
    });
  }

  void _markAsWatched(BuildContext context, EpisodeDetailsState state) {
    MarkAsWatchedWidget.modal(context, state.markAsWatchedTarget);
  }

  Future<void> _setWatchlisted(BuildContext context, bool watchlisted) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<EpisodeDetailsBloc>().setWatchlisted(watchlisted);
    final verb = watchlisted ? 'add this episode to' : 'remove this episode from';
    final message = result.message('Could not $verb your Watchlist. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _rate(BuildContext context, int rating) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<EpisodeDetailsBloc>().rate(rating);
    final message = result.message('Could not save your rating. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _removeRating(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<EpisodeDetailsBloc>().removeRating();
    final message = result.message('Could not remove your rating. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _setIgnored(BuildContext context, bool ignored) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<EpisodeDetailsBloc>().setIgnored(ignored);
    final verb = ignored ? 'ignore' : 'stop ignoring';
    final message = result.message('Could not $verb this show. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CustomNavigationDrawer(),
      body: BlocBuilder<EpisodeDetailsBloc, EpisodeDetailsState>(
        builder: (context, state) {
          final show = state.providerId.item1;
          final season = state.providerId.item2;
          final episode = state.providerId.item3;
          final watchedStatus = state.watchedStatus;
          // Built once per state emission and reused across scroll frames — the LayoutBuilder
          // below rebuilds on every scrolled pixel, and an identical child instance lets the
          // framework skip re-building the banner subtree.
          final banner = DetailsHeroBanner(ArtworkRef.backdrop(MediaKey.show(show), state.backdropPath));

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: ScreenSizeUtil.calculateSize(230),
                actions: [
                  // Both cues live in the app bar rather than over the artwork so they survive
                  // the bar collapsing and never sit under the menu. Dropped goes first, leaving
                  // the watched badge nearest the menu it shares its row with.
                  if (state.dropped)
                    Padding(
                      padding: ScreenSizeUtil.fromLTRB(0, 0, 4, 0),
                      child: const Center(child: DetailsDroppedBadge()),
                    ),
                  if (watchedStatus.isComplete)
                    Padding(
                      padding: ScreenSizeUtil.fromLTRB(0, 0, 4, 0),
                      child: const Center(child: DetailsWatchedBadge()),
                    ),
                  DetailsOverflowMenu(
                    showTitle: state.showTitle,
                    ignored: state.dropped,
                    pendingAction: state.pendingAction,
                    onIgnoredChanged: (ignored) => _setIgnored(context, ignored),
                  ),
                ],
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    // Show the title only when the bar is (nearly) collapsed, so it
                    // never overlaps the banner artwork while expanded.
                    final settings = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
                    final expandRatio = ((constraints.maxHeight - settings.minExtent) / (settings.maxExtent - settings.minExtent)).clamp(
                      0.0,
                      1.0,
                    );

                    return FlexibleSpaceBar(
                      titlePadding: EdgeInsetsDirectional.only(
                        start: ScreenSizeUtil.calculateSize(56),
                        bottom: ScreenSizeUtil.calculateSize(16),
                        end: ScreenSizeUtil.calculateSize(16),
                      ),
                      expandedTitleScale: 1.0,
                      title: AnimatedOpacity(
                        opacity: expandRatio < 0.25 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Text(
                          state.title ?? 'Episode ${season}x$episode',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      background: banner,
                    );
                  },
                ),
              ),
              if (state.initialLoading)
                const SliverPageLoading('Loading episode details')
              else if (state.loadStatus == DetailsLoadStatus.notFound || state.loadStatus == DetailsLoadStatus.unreachable)
                SliverPageLoading(state.message)
              else ...[
                SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    EpisodeContextBreadcrumb(
                      showTmdbId: show,
                      season: season,
                      showTitle: state.showTitle,
                      episode: episode,
                      episodeTitle: state.title,
                    ),
                    CheckInBanner(
                      scope: CheckInBannerScope.episode(tmdbId: show, season: season, episode: episode),
                    ),
                    DetailsDroppedNotice(
                      dropped: state.dropped,
                      pendingAction: state.pendingAction,
                      onUndo: () => _setIgnored(context, false),
                      subtitle: 'This show is hidden from your progress and Up Next lists.',
                    ),
                    EpisodeStats(
                      firstAired: state.firstAired,
                      runtime: state.runtime,
                      network: state.network,
                      language: state.language,
                      genres: state.genres,
                    ),
                    DetailsActionBar(
                      status: watchedStatus,
                      watchListed: state.watchListed,
                      pendingAction: state.pendingAction,
                      onMarkAsWatched: () => _markAsWatched(context, state),
                      onWatchListedChanged: (watchlisted) => _setWatchlisted(context, watchlisted),
                    ),
                    EpisodeOverview(state.overview),
                    RatingsCard(
                      userRating: state.userRating,
                      externalRatings: state.externalRatings,
                      onRate: state.pendingAction != null ? null : (rating) => _rate(context, rating),
                      onRemoveRating: state.pendingAction != null || state.userRating == null ? null : () => _removeRating(context),
                    ),
                    DetailsExternalLinks(links: state.externalLinks),
                    DetailsWatchProviders(
                      regionSet: state.watchProviderRegionSet,
                      providers: state.watchProviders,
                      link: state.watchProviderLink,
                    ),
                    EpisodeActors(regulars: state.actorsRegulars, guests: state.actorsGuests, itemKey: MediaKey.show(show)),
                    EpisodeWatchHistory(state.watchedHistory),
                  ]),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
              const SliverBottomInset(),
            ],
          );
        },
      ),
    );
  }
}
