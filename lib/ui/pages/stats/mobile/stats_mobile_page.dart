import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/check_in/check_in_banner.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/stats/common/activity_section.dart';
import 'package:ticketbox/ui/pages/stats/common/completion_card.dart';
import 'package:ticketbox/ui/pages/stats/common/crowd_comparison_section.dart';
import 'package:ticketbox/ui/pages/stats/common/decades_section.dart';
import 'package:ticketbox/ui/pages/stats/common/filter_container.dart';
import 'package:ticketbox/ui/pages/stats/common/most_watched_show_card.dart';
import 'package:ticketbox/ui/pages/stats/common/no_stats_container.dart';
import 'package:ticketbox/ui/pages/stats/common/rating_trend_section.dart';
import 'package:ticketbox/ui/pages/stats/common/ratings_section.dart';
import 'package:ticketbox/ui/pages/stats/common/stat_tile_grid.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_artwork_refs.dart';
import 'package:ticketbox/ui/pages/stats/common/top_genres_card.dart';
import 'package:ticketbox/ui/pages/stats/common/top_rated_row.dart';
import 'package:ticketbox/ui/pages/stats/common/top_rewatched_list.dart';
import 'package:ticketbox/ui/pages/stats/common/unrated_movies_card.dart';
import 'package:ticketbox/ui/pages/stats/stats_bloc.dart';
import 'package:ticketbox/ui/pages/stats/stats_state.dart';

class StatsMobilePage extends StatefulWidget {
  const StatsMobilePage({super.key});

  @override
  State<StatsMobilePage> createState() => _StatsMobilePage();
}

class _StatsMobilePage extends State<StatsMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StatsBloc>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      drawer: CustomNavigationDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text('Stats'),
            floating: true,
            pinned: false,
            bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
          ),
          SliverToBoxAdapter(child: CheckInBanner()),
          SliverToBoxAdapter(child: StatsFilterContainer()),
          _Body(),
          SliverBottomInset(),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StatsBloc, StatsState>(
      buildWhen: (previous, current) => previous.initialLoading != current.initialLoading,
      builder: (context, state) {
        if (state.initialLoading) {
          return const SliverPageLoading('Crunching your numbers');
        } else {
          return const _StatsSections();
        }
      },
    );
  }
}

class _StatsSections extends StatelessWidget {
  const _StatsSections();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StatsBloc, StatsState>(
      buildWhen: (previous, current) =>
          previous.overview != current.overview ||
          previous.hasError != current.hasError ||
          previous.artwork != current.artwork ||
          previous.topRated != current.topRated,
      builder: (context, state) {
        final overview = state.overview;
        if (overview == null || overview.isEmpty) {
          return const NoStatsContainer();
        }
        final artwork = state.artwork;
        final mostWatched = overview.mostWatchedShow;
        final period = overview.period;

        return SliverList(
          delegate: SliverChildListDelegate([
            StatTileGrid(overview.headline, period: period),
            if (mostWatched != null) MostWatchedShowCard(mostWatched, banner: artwork.bannerOf(MediaKey.show(mostWatched.tmdbId))),
            if (overview.ratingDistribution != null || overview.ratingsGiven != null)
              RatingsSection(distribution: overview.ratingDistribution, ratingsGiven: overview.ratingsGiven),
            TopRatedRow(models: state.topRated),
            if (overview.ratingTrend != null) RatingTrendSection(overview.ratingTrend!, period: period),
            if (overview.crowdComparison != null) CrowdComparisonSection(overview.crowdComparison!, artwork: artwork),
            if (overview.unratedMovies != null) UnratedMoviesCard(overview.unratedMovies!, artwork: artwork),
            ActivitySection(overview.activity, period: period, artwork: artwork),
            if (overview.decades != null) DecadesSection(overview.decades!, artwork: artwork),
            if (overview.topRewatched.isNotEmpty) TopRewatchedList(overview.topRewatched, artwork: artwork),
            if (overview.completion.tracked > 0) CompletionCard(overview.completion, artwork: artwork),
            if (overview.topGenres != null) TopGenresCard(overview.topGenres!, period: period),
            SizedBox(height: ScreenSizeUtil.calculateSize(24)),
          ]),
        );
      },
    );
  }
}
