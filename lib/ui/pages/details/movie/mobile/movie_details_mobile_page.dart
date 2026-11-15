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
import 'package:ticketbox/ui/pages/details/common/details_external_links.dart';
import 'package:ticketbox/ui/pages/details/common/details_favorite_badge.dart';
import 'package:ticketbox/ui/pages/details/common/details_hero_banner.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_overflow_menu.dart';
import 'package:ticketbox/ui/pages/details/common/details_popularity_card.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_providers.dart';
import 'package:ticketbox/ui/pages/details/common/details_watched_badge.dart';
import 'package:ticketbox/ui/pages/details/common/ratings_card.dart';
import 'package:ticketbox/ui/pages/details/movie/movie_details_bloc.dart';
import 'package:ticketbox/ui/pages/details/movie/movie_details_state.dart';
import 'package:ticketbox/ui/pages/details/movie/widgets/movie_actors.dart';
import 'package:ticketbox/ui/pages/details/movie/widgets/movie_overview.dart';
import 'package:ticketbox/ui/pages/details/movie/widgets/movie_similar.dart';
import 'package:ticketbox/ui/pages/details/movie/widgets/movie_stats.dart';
import 'package:ticketbox/ui/pages/details/movie/widgets/movie_watch_history.dart';

/// Mobile layout for the movie details page.
///
/// Mirrors the show details page: a collapsing hero app bar renders the movie
/// banner with the title overlaid; below it the content is organized into the
/// same uniform sections. A movie has neither a parent breadcrumb nor anything
/// below it in the hierarchy, so there is no grid between the sections and the
/// history; the page ends on the similar-movies row instead, the one section
/// that points away from this movie. Everything reads from [MovieDetailsState] except the check-in
/// heads-up, which is the app-wide [CheckInBanner] reading the shared check-in
/// state.
///
/// The mutations the page offers are mark-as-watched and the watchlist toggle
/// in [DetailsActionBar], rating from the [RatingsCard]'s heart bar, favoriting
/// the movie from the app bar's [DetailsOverflowMenu], and deleting a watch entry
/// from the history section.
/// Starting a check-in lives one level down, inside the mark-as-watched sheet,
/// where it is the alternative to logging a finished play.
/// Only whole shows can be dropped, so the ignore flow (and with it the dropped
/// badge/notice) has no movie equivalent: the overflow menu here holds the
/// favorite toggle alone. Watched state is two-way — a movie is watched or it is not.
class MovieDetailsMobilePage extends StatefulWidget {
  const MovieDetailsMobilePage({super.key});

  @override
  State<MovieDetailsMobilePage> createState() => _MovieDetailsMobilePageState();
}

class _MovieDetailsMobilePageState extends State<MovieDetailsMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MovieDetailsBloc>().init();
    });
  }

  void _markAsWatched(BuildContext context, MovieDetailsState state) {
    MarkAsWatchedWidget.modal(context, state.markAsWatchedTarget);
  }

  Future<void> _setWatchlisted(BuildContext context, bool watchlisted) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<MovieDetailsBloc>().setWatchlisted(watchlisted);
    final verb = watchlisted ? 'add this movie to' : 'remove this movie from';
    final message = result.message('Could not $verb your Watchlist. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _rate(BuildContext context, int rating) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<MovieDetailsBloc>().rate(rating);
    final message = result.message('Could not save your rating. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _removeRating(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<MovieDetailsBloc>().removeRating();
    final message = result.message('Could not remove your rating. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _setFavorite(BuildContext context, bool favorite) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<MovieDetailsBloc>().setFavorite(favorite);
    final verb = favorite ? 'add' : 'remove';
    final message = result.message('Could not $verb this movie ${favorite ? 'to' : 'from'} your favorites. Please try again.');
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CustomNavigationDrawer(),
      body: BlocBuilder<MovieDetailsBloc, MovieDetailsState>(
        builder: (context, state) {
          final watchedStatus = state.watchedStatus;
          // Built once per state emission and reused across scroll frames — the LayoutBuilder
          // below rebuilds on every scrolled pixel, and an identical child instance lets the
          // framework skip re-building the banner subtree.
          final banner = DetailsHeroBanner(ArtworkRef.backdrop(MediaKey.movie(state.providerId), state.backdropPath));

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: ScreenSizeUtil.calculateSize(230),
                actions: [
                  // The cues live in the app bar rather than over the artwork so they survive the
                  // bar collapsing and never sit under the menu. Favorite goes first, leaving
                  // the watched badge nearest the menu it shares its row with.
                  if (state.favorite)
                    Padding(
                      padding: ScreenSizeUtil.fromLTRB(0, 0, 4, 0),
                      child: const Center(child: DetailsFavoriteBadge()),
                    ),
                  if (watchedStatus.isComplete)
                    Padding(
                      padding: ScreenSizeUtil.fromLTRB(0, 0, 4, 0),
                      child: const Center(child: DetailsWatchedBadge()),
                    ),
                  DetailsOverflowMenu(
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
                          state.title ?? 'Movie details',
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
                const SliverPageLoading('Loading movie details')
              else if (state.loadStatus == DetailsLoadStatus.notFound || state.loadStatus == DetailsLoadStatus.unreachable)
                SliverPageLoading(state.message)
              else ...[
                SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    // The scope tells the banner a check-in for this movie is the page the user
                    // is already on, so tapping it should not navigate anywhere.
                    CheckInBanner(scope: CheckInBannerScope.movie(tmdbId: state.providerId)),
                    MovieStats(
                      released: state.released,
                      status: state.status,
                      runtime: state.runtime,
                      country: state.country,
                      certification: state.certification,
                      language: state.language,
                      genres: state.genres,
                      userPlays: state.userPlays,
                    ),
                    DetailsActionBar(
                      status: watchedStatus,
                      watchListed: state.watchListed,
                      pendingAction: state.pendingAction,
                      onMarkAsWatched: () => _markAsWatched(context, state),
                      onWatchListedChanged: (watchlisted) => _setWatchlisted(context, watchlisted),
                    ),
                    MovieOverview(tagLine: state.tagLine, overview: state.overview),
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
                    MovieActors(actors: state.actors, itemKey: MediaKey.movie(state.providerId)),
                    MovieWatchHistory(state.watchedHistory),
                    MovieSimilar(models: state.related),
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
