import 'package:flutter/material.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/poster/pills/poster_watched_pill.dart';
import 'package:ticketbox/ui/common/poster/pills/season_finale_pill.dart';
import 'package:ticketbox/ui/common/poster/pills/season_premiere.dart';
import 'package:ticketbox/ui/common/poster/pills/upcoming_episode_pill.dart';
import 'package:ticketbox/ui/common/poster/pills/watchlisted_pill.dart';

class PosterTopLeftPills extends StatelessWidget {
  final PosterModel details;

  const PosterTopLeftPills(this.details, {super.key});

  @override
  Widget build(BuildContext context) {
    List<Widget> pills = [];

    if (details.upcoming) {
      pills.add(UpcomingEpisodePill(details.airDate));
    }

    if (details.seasonPremiere) {
      pills.add(const SeasonPremierePill());
    } else if (details.seriesFinale) {
      pills.add(const SeriesFinalePill());
    } else if (details.seasonFinale) {
      pills.add(const SeasonFinalePill());
    } else if (details.midSeasonFinale) {
      pills.add(const MidSeasonFinalePill());
    }

    if (details.marks.watched) {
      pills.add(const PosterWatchedPill());
    }
    if (details.marks.watchListed) {
      pills.add(const WatchlistedPill());
    }

    if (pills.isEmpty) {
      return const SizedBox();
    }

    return Container(
      alignment: Alignment.topLeft,
      child: Column(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.start, children: pills),
    );
  }
}
