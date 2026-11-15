import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:ticketbox/ui/pages/details/common/details_favorite_badge.dart';
import 'package:ticketbox/ui/pages/details/common/details_hero_banner.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_overflow_menu.dart';
import 'package:ticketbox/ui/pages/details/common/details_popularity_card.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_providers.dart';
import 'package:ticketbox/ui/pages/details/common/details_watched_badge.dart';
import 'package:ticketbox/ui/pages/details/common/ratings_card.dart';
import 'package:ticketbox/ui/pages/details/show/show_details_bloc.dart';
import 'package:ticketbox/ui/pages/details/show/show_details_state.dart';
import 'package:ticketbox/ui/pages/details/show/widgets/show_actors.dart';
import 'package:ticketbox/ui/pages/details/show/widgets/show_overview.dart';
import 'package:ticketbox/ui/pages/details/show/widgets/show_seasons_grid.dart';
import 'package:ticketbox/ui/pages/details/show/widgets/show_similar.dart';
import 'package:ticketbox/ui/pages/details/show/widgets/show_stats.dart';
import 'package:ticketbox/ui/pages/details/show/widgets/show_watch_history.dart';

/// Mobile layout for the show details page.
///
/// Mirrors the episode and season details pages: a collapsing hero app bar
/// renders the show banner with the title overlaid; below it the content is
/// organized into the same uniform sections. A show has no parent, so in place
/// of the breadcrumb the other two carry it has a seasons poster grid pointing
/// *down* the hierarchy. Everything reads from [ShowDetailsState] except the
/// check-in heads-up, which is the app-wide [CheckInBanner] reading the shared
/// check-in state.
///
/// The mutations the page offers are mark-as-watched and the watchlist toggle in
/// [DetailsActionBar], rating from the [RatingsCard]'s heart bar, favoriting the show or ignoring
/// it from the app bar's [DetailsOverflowMenu] (un-ignoring also from the [DetailsDroppedNotice]),
/// and deleting a watch entry from the history section. Watched
/// state is three-way here — none, partly watched (a progress readout under the button), or every
/// aired episode watched, the only case that earns the banner badge.
class ShowDetailsMobilePage extends StatefulWidget {
  const ShowDetailsMobilePage({super.key});

  @override
  State<ShowDetailsMobilePage> createState() => _ShowDetailsMobilePageState();
}

class _ShowDetailsMobilePageState extends State<ShowDetailsMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShowDetailsBloc>().init();
    });
  }

  void _markAsWatched(BuildContext context, ShowDetailsState state) {
    MarkAsWatchedWidget.modal(context, state.markAsWatchedTarget);
  }

  Future<void> _setWatchlisted(BuildContext context, bool watchlisted) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<ShowDetailsBloc>().setWatchlisted(watchlisted);
    final verb = watchlisted ? 'add this show to' : 'remove this show from';
    final message = result.message('Could not $verb your Watchlist. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _rate(BuildContext context, int rating) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<ShowDetailsBloc>().rate(rating);
    final message = result.message('Could not save your rating. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _removeRating(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<ShowDetailsBloc>().removeRating();
    final message = result.message('Could not remove your rating. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _setIgnored(BuildContext context, bool ignored) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<ShowDetailsBloc>().setIgnored(ignored);
    final verb = ignored ? 'ignore' : 'stop ignoring';
    final message = result.message('Could not $verb this show. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _setFavorite(BuildContext context, bool favorite) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<ShowDetailsBloc>().setFavorite(favorite);
    final verb = favorite ? 'add' : 'remove';
    final message = result.message('Could not $verb this show ${favorite ? 'to' : 'from'} your favorites. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CustomNavigationDrawer(),
      body: BlocBuilder<ShowDetailsBloc, ShowDetailsState>(
        builder: (context, state) {
          final watchedStatus = state.watchedStatus;
          // Built once per state emission and reused across scroll frames — the LayoutBuilder
          // below rebuilds on every scrolled pixel, and an identical child instance lets the
          // framework skip re-building the banner subtree.
          final banner = DetailsHeroBanner(ArtworkRef.backdrop(MediaKey.show(state.providerId), state.backdropPath));

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: ScreenSizeUtil.calculateSize(230),
                actions: [
                  // The cues live in the app bar rather than over the artwork so they survive
                  // the bar collapsing and never sit under the menu. Favorite goes first, then
                  // dropped, leaving the watched badge nearest the menu it shares its row with.
                  if (state.favorite)
                    Padding(
                      padding: ScreenSizeUtil.fromLTRB(0, 0, 4, 0),
                      child: const Center(child: DetailsFavoriteBadge()),
                    ),
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
                    showTitle: state.title,
                    ignored: state.dropped,
                    onIgnoredChanged: (ignored) => _setIgnored(context, ignored),
                    favorite: state.favorite,
                    onFavoriteChanged: (favorite) => _setFavorite(context, favorite),
                    pendingAction: state.pendingAction,
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
                          state.title ?? 'Show details',
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
                const SliverPageLoading('Loading show details')
              else if (state.loadStatus == DetailsLoadStatus.notFound || state.loadStatus == DetailsLoadStatus.unreachable)
                SliverPageLoading(state.message)
              else ...[
                // The section list is split around the seasons grid on purpose: a sliver cannot
                // live inside a SliverChildListDelegate, and nesting a shrinkWrap grid instead
                // would mount every season tile at once — each one opening its own poster watch
                // stream. Keeping it a real SliverGrid keeps it viewport-lazy. Don't merge these
                // back into one list.
                SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    const CheckInBanner(),
                    DetailsDroppedNotice(
                      dropped: state.dropped,
                      pendingAction: state.pendingAction,
                      onUndo: () => _setIgnored(context, false),
                    ),
                    ShowStats(
                      firstAired: state.firstAired,
                      status: state.status,
                      nextEpisodeAirDate: state.nextEpisodeAirDate,
                      runtime: state.runtime,
                      network: state.network,
                      country: state.country,
                      certification: state.certification,
                      language: state.language,
                      genres: state.genres,
                      watchedEpisodes: state.watchedEpisodes,
                      airedEpisodes: state.airedEpisodes,
                    ),
                    DetailsActionBar(
                      status: watchedStatus,
                      watchListed: state.watchListed,
                      pendingAction: state.pendingAction,
                      onMarkAsWatched: () => _markAsWatched(context, state),
                      onWatchListedChanged: (watchlisted) => _setWatchlisted(context, watchlisted),
                    ),
                    ShowOverview(state.overview),
                    RatingsCard(
                      userRating: state.userRating,
                      externalRatings: state.externalRatings,
                      onRate: state.pendingAction != null ? null : (rating) => _rate(context, rating),
                      onRemoveRating: state.pendingAction != null || state.userRating == null ? null : () => _removeRating(context),
                    ),
                    DetailsPopularityCard(popularity: state.popularity, voteCount: state.voteCount),
                    DetailsExternalLinks(links: state.externalLinks),
                    DetailsWatchProviders(
                      regionSet: state.watchProviderRegionSet,
                      providers: state.watchProviders,
                      link: state.watchProviderLink,
                    ),
                    ShowActors(regulars: state.actorsRegulars, guests: state.actorsGuests, itemKey: MediaKey.show(state.providerId)),
                  ]),
                ),
                ...ShowSeasonsGrid.slivers(state.seasons),
                SliverList(
                  delegate: SliverChildListDelegate.fixed([ShowWatchHistory(state.watchedHistory), ShowSimilar(models: state.related)]),
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
