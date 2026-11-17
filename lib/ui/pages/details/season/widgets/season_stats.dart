import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';

/// Icon + value meta strip for the season (air date, episode count, network,
/// language, genres).
///
/// Air date and episode counts belong to the season; network, language and
/// genres come from the parent show's summary. Each item is skipped when TMDB
/// has no value for it, so the strip never renders a blank entry.
class SeasonStats extends StatelessWidget {
  final DateTime? firstAired;
  final int episodeCount;
  final int airedEpisodes;
  final String? network;
  final String? language;
  final List<String> genres;

  const SeasonStats({
    required this.firstAired,
    required this.episodeCount,
    required this.airedEpisodes,
    required this.network,
    required this.language,
    required this.genres,
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

    if (episodeCount > 0) {
      // Only worth spelling out both numbers while the season is still airing.
      final label = airedEpisodes < episodeCount ? '$airedEpisodes of $episodeCount episodes' : '$episodeCount episodes';
      items.add(_MetaItem(icon: Icons.playlist_play_outlined, label: label));
    }

    final networkName = network;
    if (networkName != null && networkName.isNotEmpty) {
      items.add(_MetaItem(icon: Icons.live_tv_outlined, label: networkName));
    }

    final showLanguage = language;
    if (showLanguage != null && showLanguage.isNotEmpty) {
      items.add(_MetaItem(icon: Icons.translate_outlined, label: showLanguage));
    }

    if (genres.isNotEmpty) {
      items.add(_MetaItem(icon: Icons.theater_comedy_outlined, label: genres.join(' · ')));
    }

    return Container(
      width: double.infinity,
      margin: ScreenSizeUtil.fromLTRB(14, 14, 14, 0),
      child: Wrap(spacing: ScreenSizeUtil.calculateSize(16), runSpacing: ScreenSizeUtil.calculateSize(8), children: items),
    );
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
