import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/loading/sync_progress_bar.dart';
import 'package:ticketbox/ui/common/poster/poster.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/show_progress/common/season_progress_tile.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_bloc.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_details.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_state.dart';

/// One tracked show: poster, title, watched progress, last watched episode and the expandable
/// "View more details" season breakdown.
class ShowProgressRow extends StatelessWidget {
  final ShowProgressRowDetails row;

  const ShowProgressRow(this.row, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: ScreenSizeUtil.fromLTRB(10, 10, 10, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ScreenSizeUtil.calculateSize(110),
            child: Poster(model: row.poster, onTap: (model) => PosterNavigation.navigate(context, model)),
          ),
          SizedBox(width: ScreenSizeUtil.calculateSize(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: ScreenSizeUtil.calculateSize(6)),
                SyncProgressBar(value: row.progress),
                SizedBox(height: ScreenSizeUtil.calculateSize(6)),
                Text('Watched ${row.completed} of ${row.aired} episodes.'),
                _LastWatchedLine(row.lastWatched),
                _DetailsToggle(row.showTmdbId),
                _ExpandedDetails(row.showTmdbId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LastWatchedLine extends StatelessWidget {
  final LastWatchedEpisode? lastWatched;

  const _LastWatchedLine(this.lastWatched);

  @override
  Widget build(BuildContext context) {
    final entry = lastWatched;
    if (entry == null) {
      return const SizedBox();
    }

    final watchedAt = DateFormat('hh:mm a d MMM y').format(entry.watchedAt);
    return Text.rich(
      TextSpan(
        text: 'Last watched ',
        children: [
          TextSpan(
            text: entry.label,
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' $watchedAt'),
        ],
      ),
    );
  }
}

class _DetailsToggle extends StatelessWidget {
  final int showId;

  const _DetailsToggle(this.showId);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
      buildWhen: (previous, current) => previous.expandedShowIds.contains(showId) != current.expandedShowIds.contains(showId),
      builder: (context, state) {
        final isExpanded = state.expandedShowIds.contains(showId);
        return TextButton(
          onPressed: () => context.read<ShowProgressBloc>().toggleShowDetails(showId),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [const Text('View more details'), Icon(isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down)],
          ),
        );
      },
    );
  }
}

class _ExpandedDetails extends StatelessWidget {
  final int showId;

  const _ExpandedDetails(this.showId);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShowProgressBloc, ShowProgressState>(
      buildWhen: (previous, current) =>
          previous.expandedShowIds.contains(showId) != current.expandedShowIds.contains(showId) ||
          previous.loadingSeasonDataIds.contains(showId) != current.loadingSeasonDataIds.contains(showId) ||
          previous.seasonData[showId] != current.seasonData[showId],
      builder: (context, state) {
        if (!state.expandedShowIds.contains(showId)) {
          return const SizedBox();
        }

        if (state.loadingSeasonDataIds.contains(showId)) {
          return Center(
            child: Container(
              margin: ScreenSizeUtil.fromLTRB(0, 10, 0, 10),
              width: ScreenSizeUtil.calculateSize(24),
              height: ScreenSizeUtil.calculateSize(24),
              child: const CircularProgressIndicator(),
            ),
          );
        }

        final seasons = state.seasonData[showId] ?? [];
        if (seasons.isEmpty) {
          return const Text('No season details available.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: seasons.map((season) => SeasonProgressTile(showId: showId, season: season)).toList(),
        );
      },
    );
  }
}
