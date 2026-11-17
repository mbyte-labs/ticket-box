import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_banner_card.dart';

/// The show with the most watched time, as a backdrop banner: the hours in the badge, the play
/// count and the last watch underneath the title. Tapping opens the show.
class MostWatchedShowCard extends StatelessWidget {
  final MostWatchedShow show;

  /// The show's backdrop; null while its artwork is not loaded yet.
  final ArtworkRef? banner;

  const MostWatchedShowCard(this.show, {required this.banner, super.key});

  @override
  Widget build(BuildContext context) {
    final hours = show.hours;
    final plays = show.episodePlays;

    return DetailsSection(
      title: 'Most watched show',
      child: DetailsCard(
        padding: ScreenSizeUtil.fromLTRB(6, 6, 6, 6),
        child: StatsBannerCard(
          mediaKey: MediaKey.show(show.tmdbId),
          banner: banner,
          // No hours while none of its episode runtimes is cached yet: the number would read as
          // "0 hours" for a show that was clearly watched a lot.
          badge: hours == 0 ? 'MOST WATCHED' : 'MOST WATCHED · $hours ${hours == 1 ? 'HOUR' : 'HOURS'}',
          title: show.title,
          subtitle: '${plays == 1 ? '1 episode play' : '$plays episode plays'} · watched ${show.watchedAgo(DateTime.now())}',
        ),
      ),
    );
  }
}
