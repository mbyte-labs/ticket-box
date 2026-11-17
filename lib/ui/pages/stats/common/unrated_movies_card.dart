import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/general_widget/confirmation/select_rating_widget.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_artwork_refs.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_banner_card.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_poster_thumb.dart';
import 'package:ticketbox/ui/pages/stats/stats_bloc.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The most recently watched movies without a rating. The latest one is a backdrop hero, the
/// rest are rows with a poster thumbnail. Each opens the movie's details page, and its Rate
/// button opens a heart sheet right here. A rating recomputes the page, so the next unrated movie
/// moves up.
class UnratedMoviesCard extends StatelessWidget {
  final UnratedMoviesStats unrated;

  /// Poster and backdrop by key. A movie without an entry yet shows placeholders.
  final Map<MediaKey, TitleArtwork> artwork;

  const UnratedMoviesCard(this.unrated, {required this.artwork, super.key});

  @override
  Widget build(BuildContext context) {
    final total = unrated.total;
    final hero = unrated.recent.first;

    return DetailsSection(
      title: 'Waiting for your rating',
      child: DetailsCard(
        padding: ScreenSizeUtil.fromLTRB(4, 12, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: ScreenSizeUtil.fromLTRB(10, 0, 10, 10),
              child: Text(
                total == 1 ? '1 watched movie without a rating' : '$total watched movies without a rating',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: ScreenSizeUtil.fromLTRB(6, 0, 6, 6),
              child: StatsBannerCard(
                mediaKey: MediaKey.movie(hero.tmdbId),
                banner: artwork.bannerOf(MediaKey.movie(hero.tmdbId)),
                badge: 'WATCHED ${hero.watchedAgo(DateTime.now()).toUpperCase()}',
                title: hero.title,
                subtitle: hero.year?.toString(),
                action: FilledButton.icon(
                  onPressed: () => _openRatingSheet(context, hero),
                  style: FilledButton.styleFrom(backgroundColor: ThemeColors.primary, foregroundColor: ThemeColors.white),
                  icon: const Icon(Icons.favorite, size: 18),
                  label: const Text('Rate'),
                ),
              ),
            ),
            for (final movie in unrated.recent.skip(1)) _UnratedRow(movie, poster: artwork.posterOf(MediaKey.movie(movie.tmdbId))),
          ],
        ),
      ),
    );
  }
}

class _UnratedRow extends StatelessWidget {
  final UnratedMovie movie;
  final ArtworkRef? poster;

  const _UnratedRow(this.movie, {required this.poster});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => PosterNavigation.movieNavigateRaw(context, movie.tmdbId),
      child: Padding(
        padding: ScreenSizeUtil.fromLTRB(6, 6, 2, 6),
        child: Row(
          children: [
            StatsPosterThumb(type: ItemType.movie, poster: poster),
            SizedBox(width: ScreenSizeUtil.calculateSize(12)),
            Expanded(
              child: Text(_titleOf(movie), maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium),
            ),
            if (movie.year != null) ...[
              SizedBox(width: ScreenSizeUtil.calculateSize(8)),
              Text('${movie.year}', style: textTheme.bodyMedium?.copyWith(color: ThemeColors.greyScale500)),
            ],
            SizedBox(width: ScreenSizeUtil.calculateSize(4)),
            TextButton(onPressed: () => _openRatingSheet(context, movie), child: const Text('Rate')),
          ],
        ),
      ),
    );
  }
}

/// The sheet's own context sits outside the page's BlocProvider, so the bloc and the messenger
/// are taken from the page first.
void _openRatingSheet(BuildContext context, UnratedMovie movie) {
  final bloc = context.read<StatsBloc>();
  final messenger = ScaffoldMessenger.of(context);

  unawaited(
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: ScreenSizeUtil.fromLTRB(15, 20, 15, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _titleOf(movie),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                ),
                if (movie.year != null) ...[
                  const SizedBox(height: 4),
                  Text('${movie.year}', style: const TextStyle(color: ThemeColors.greyScale500)),
                ],
                SizedBox(height: ScreenSizeUtil.calculateSize(20)),
                FittedBox(
                  child: ConfirmationSelectRating(
                    onRatingUpdate: (value) async {
                      final rating = value.round();
                      if (rating < 1) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      final succeeded = await bloc.rateMovie(movie, rating);
                      if (!succeeded) {
                        messenger.showSnackBar(const SnackBar(content: Text('Could not save your rating. Please try again.')));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

String _titleOf(UnratedMovie movie) => movie.title.isEmpty ? 'A movie' : movie.title;
