import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/title_builder.dart';
import 'package:ticketbox/ui/common/loading/sync_progress_bar.dart';
import 'package:ticketbox/ui/pages/show_progress/common/episode_chip.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_bloc.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_details.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_state.dart';

/// One season inside a show's expanded details: name, watched count, progress bar and - once
/// expanded - the episode chips.
class SeasonProgressTile extends StatelessWidget {
  final int showId;
  final SeasonProgressDetails season;

  const SeasonProgressTile({required this.showId, required this.season, super.key});

  @override
  Widget build(BuildContext context) {
    final key = ShowProgressBloc.seasonKey(showId, season.season);

    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
      buildWhen: (previous, current) => previous.expandedSeasonKeys.contains(key) != current.expandedSeasonKeys.contains(key),
      builder: (context, state) {
        final isExpanded = state.expandedSeasonKeys.contains(key);

        return Container(
          margin: ScreenSizeUtil.fromLTRB(0, 5, 0, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => context.read<ShowProgressBloc>().toggleSeason(showId, season.season),
                child: Row(
                  children: [
                    Expanded(child: Text(ConfirmationTitleBuilder.seasonTitle(season.season))),
                    Text('${season.completed}/${season.aired} episodes'),
                    Icon(isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down),
                  ],
                ),
              ),
              SizedBox(height: ScreenSizeUtil.calculateSize(4)),
              SyncProgressBar(value: season.progress),
              if (isExpanded)
                Container(
                  margin: ScreenSizeUtil.fromLTRB(0, 8, 0, 0),
                  child: Wrap(
                    spacing: ScreenSizeUtil.calculateSize(12),
                    runSpacing: ScreenSizeUtil.calculateSize(6),
                    children: season.episodes.map((episode) => EpisodeChip(episode)).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
