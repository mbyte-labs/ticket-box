import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/title_builder.dart';
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
import 'package:ticketbox/ui/pages/details/season/season_details_bloc.dart';
import 'package:ticketbox/ui/pages/details/season/season_details_state.dart';
import 'package:ticketbox/ui/pages/details/season/widgets/season_actors.dart';
import 'package:ticketbox/ui/pages/details/season/widgets/season_context_breadcrumb.dart';
import 'package:ticketbox/ui/pages/details/season/widgets/season_episodes_grid.dart';
import 'package:ticketbox/ui/pages/details/season/widgets/season_overview.dart';
import 'package:ticketbox/ui/pages/details/season/widgets/season_stats.dart';
import 'package:ticketbox/ui/pages/details/season/widgets/season_watch_history.dart';

/// Mobile layout for the season details page.
///
/// Mirrors the episode details page: a collapsing hero app bar renders the show
/// banner with the season title overlaid; below it the content is organized into
/// the same uniform sections (breadcrumb, meta strip, overview, ratings,
/// watch now, cast, episodes, history), with a grid of episode stills
/// pointing *down* the hierarchy. Sections backed by real state read from
/// [SeasonDetailsState]. The check-in heads-up is the app-wide [CheckInBanner],
/// which reads the shared check-in state rather than this page's.
///
/// The mutations the page offers are mark-as-watched and the watchlist toggle in
/// [DetailsActionBar], ignoring the show from the app bar's [DetailsOverflowMenu] or un-ignoring
/// it from the [DetailsDroppedNotice], and deleting a watch entry from the history section. A
/// season is not rated directly: the [RatingsCard]'s hearts are a read-only average of the user's
/// episode ratings. Watched
/// state is three-way here — none, partly watched (a progress readout under the button), or every
/// aired episode watched, the only case that earns the banner badge.
class SeasonDetailsMobilePage extends StatefulWidget {
  const SeasonDetailsMobilePage({super.key});

  @override
  State<SeasonDetailsMobilePage> createState() => _SeasonDetailsMobilePageState();
}

class _SeasonDetailsMobilePageState extends State<SeasonDetailsMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SeasonDetailsBloc>().init();
    });
  }

  void _markAsWatched(BuildContext context, SeasonDetailsState state) {
    MarkAsWatchedWidget.modal(context, state.markAsWatchedTarget);
  }

  Future<void> _setWatchlisted(BuildContext context, bool watchlisted) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<SeasonDetailsBloc>().setWatchlisted(watchlisted);
    final verb = watchlisted ? 'add this season to' : 'remove this season from';
    final message = result.message('Could not $verb your Watchlist. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _setIgnored(BuildContext context, bool ignored) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<SeasonDetailsBloc>().setIgnored(ignored);
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
      body: BlocBuilder<SeasonDetailsBloc, SeasonDetailsState>(
        builder: (context, state) {
          final show = state.providerId.item1;
          final season = state.providerId.item2;
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
                          state.title ?? ConfirmationTitleBuilder.seasonTitle(season),
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
                const SliverPageLoading('Loading season details')
              else if (state.loadStatus == DetailsLoadStatus.notFound || state.loadStatus == DetailsLoadStatus.unreachable)
                SliverPageLoading(state.message)
              else ...[
                // The section list is split around the episodes grid on purpose: a sliver cannot
                // live inside a SliverChildListDelegate, and nesting a shrinkWrap grid instead
                // would mount every episode tile at once — each one opening its own poster watch
                // stream. Keeping it a real SliverGrid keeps it viewport-lazy. Don't merge these
                // back into one list.
                SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    SeasonContextBreadcrumb(showTmdbId: show, season: season, showTitle: state.showTitle),
                    const CheckInBanner(),
                    DetailsDroppedNotice(
                      dropped: state.dropped,
                      pendingAction: state.pendingAction,
                      onUndo: () => _setIgnored(context, false),
                      subtitle: 'This show is hidden from your progress and Up Next lists.',
                    ),
                    SeasonStats(
                      firstAired: state.firstAired,
                      episodeCount: state.episodeCount,
                      airedEpisodes: state.airedEpisodes,
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
                    SeasonOverview(state.overview),
                    RatingsCard.season(
                      externalRatings: state.externalRatings,
                      episodeAverage: state.episodeRatingAverage == null
                          ? null
                          : (average: state.episodeRatingAverage!, count: state.ratedEpisodes),
                    ),
                    DetailsExternalLinks(links: state.externalLinks),
                    DetailsWatchProviders(
                      regionSet: state.watchProviderRegionSet,
                      providers: state.watchProviders,
                      link: state.watchProviderLink,
                    ),
                    SeasonActors(regulars: state.actorsRegulars, guests: state.actorsGuests, itemKey: MediaKey.show(show)),
                  ]),
                ),
                ...SeasonEpisodesGrid.slivers(state.episodes),
                SliverList(
                  delegate: SliverChildListDelegate.fixed([SeasonWatchHistory(season: season, entries: state.watchedHistory)]),
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
