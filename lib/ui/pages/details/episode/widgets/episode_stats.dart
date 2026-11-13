import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ticketbox/service/screen_size_util.dart';

/// Icon + value meta strip for the episode (air date, runtime, network,
/// language, genres).
///
/// Air date and runtime belong to the episode; network, language and genres
/// come from the parent show's summary. Each item is skipped when TMDB has no
/// value for it, so the strip never renders a blank entry.
class EpisodeStats extends StatelessWidget {
  final DateTime? firstAired;
  final int? runtime;
  final String? network;
  final String? language;
  final List<String> genres;

  const EpisodeStats({
    required this.firstAired,
    required this.runtime,
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

    if (runtime != null && runtime! > 0) {
      items.add(_MetaItem(icon: Icons.schedule_outlined, label: '$runtime min'));
    }

    final showNetwork = network;
    if (showNetwork != null && showNetwork.isNotEmpty) {
      items.add(_MetaItem(icon: Icons.live_tv_outlined, label: showNetwork));
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
