import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/movie_status.dart';
import 'package:ticketbox/service/screen_size_util.dart';

/// Icon + value meta strip for the movie.
///
/// The TMDB movie summary carries the release date, status, runtime, country,
/// certification, language and genres, and the play count comes from the local
/// watch history. Each item hides itself when its value is missing.
class MovieStats extends StatelessWidget {
  final DateTime? released;
  final MovieStatus status;
  final int? runtime;
  final String? country;
  final String? certification;
  final String? language;
  final List<String> genres;
  final int userPlays;

  const MovieStats({
    required this.released,
    required this.status,
    required this.runtime,
    required this.country,
    required this.certification,
    required this.language,
    required this.genres,
    required this.userPlays,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    final release = released;
    if (release != null) {
      final icon = release.isAfter(DateTime.now()) ? Icons.upcoming_outlined : Icons.event_outlined;
      items.add(_MetaItem(icon: icon, label: DateFormat.yMMMd().format(release)));
    }

    if (status != MovieStatus.unknown) {
      items.add(_MetaItem(icon: Icons.info_outline, label: status.label));
    }

    if (userPlays > 0) {
      items.add(_MetaItem(icon: Icons.playlist_play_outlined, label: userPlays == 1 ? 'Watched once' : 'Watched $userPlays times'));
    }

    if (runtime != null && runtime! > 0) {
      items.add(_MetaItem(icon: Icons.timer_outlined, label: '$runtime min'));
    }

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
