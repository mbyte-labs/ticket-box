import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/show_status.dart';
import 'package:ticketbox/service/screen_size_util.dart';

/// Icon + value meta strip for the show.
///
/// Unlike the episode and season equivalents every item here is real: the TMDB
/// show summary carries the status, next air date, runtime, network, country,
/// certification, language and genres, and the watched count comes from the
/// local watch progress. Each item hides itself when its value is missing.
class ShowStats extends StatelessWidget {
  final DateTime? firstAired;
  final ShowStatus status;

  /// When the next episode airs, if TMDB has announced one. Takes the slot the air schedule
  /// used to have — TMDB has no weekday/time schedule, but it does know the next date.
  final DateTime? nextEpisodeAirDate;
  final int? runtime;
  final String? network;
  final String? country;
  final String? certification;
  final String? language;
  final List<String> genres;
  final int watchedEpisodes;
  final int airedEpisodes;

  const ShowStats({
    required this.firstAired,
    required this.status,
    required this.nextEpisodeAirDate,
    required this.runtime,
    required this.network,
    required this.country,
    required this.certification,
    required this.language,
    required this.genres,
    required this.watchedEpisodes,
    required this.airedEpisodes,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    final aired = firstAired;
    if (aired != null) {
      final icon = aired.isAfter(DateTime.now()) ? Icons.upcoming_outlined : Icons.event_outlined;
      items.add(_MetaItem(icon: icon, label: DateFormat.yMMMd().format(aired)));
    }

    if (status != ShowStatus.unknown) {
      items.add(_MetaItem(icon: Icons.info_outline, label: status.label));
    }

    final nextAir = nextEpisodeAirDate;
    if (nextAir != null) {
      items.add(_MetaItem(icon: Icons.schedule_outlined, label: 'Next episode: ${DateFormat.yMMMd().format(nextAir)}'));
    }

    if (airedEpisodes > 0) {
      items.add(_MetaItem(icon: Icons.playlist_play_outlined, label: '$watchedEpisodes of $airedEpisodes watched'));
    }

    if (runtime != null && runtime! > 0) {
      items.add(_MetaItem(icon: Icons.timer_outlined, label: '$runtime min'));
    }

    _addIfPresent(items, Icons.live_tv_outlined, network);
    _addIfPresent(items, Icons.public_outlined, country?.toUpperCase());
    _addIfPresent(items, Icons.shield_outlined, certification);
    _addIfPresent(items, Icons.translate_outlined, language?.toUpperCase());

    if (genres.isNotEmpty) {
      items.add(_MetaItem(icon: Icons.theater_comedy_outlined, label: genres.join(' · ')));
    }

    return Container(
      width: double.infinity,
      margin: ScreenSizeUtil.fromLTRB(14, 14, 14, 0),
      child: Wrap(spacing: ScreenSizeUtil.calculateSize(16), runSpacing: ScreenSizeUtil.calculateSize(8), children: items),
    );
  }

  static void _addIfPresent(List<Widget> items, IconData icon, String? label) {
    if (label != null && label.isNotEmpty) {
      items.add(_MetaItem(icon: icon, label: label));
    }
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: ScreenSizeUtil.calculateSize(15), color: colorScheme.onSurfaceVariant),
        SizedBox(width: ScreenSizeUtil.calculateSize(5)),
        Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withValues(alpha: 0.9))),
      ],
    );
  }
}
