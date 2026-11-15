import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Orange counterpart of the green `SeasonPremierePill`: an Up Next episode that has not aired yet,
/// labelled `Airs 20.10.2027`, or `Airs TBA` when TMDB has no date for it.
///
/// Geometry matches the premiere and finale pills so they stack cleanly in the poster's top-left
/// corner.
class UpcomingEpisodePill extends StatelessWidget {
  static final _decoration = BoxDecoration(
    border: Border.all(width: 0, color: Colors.transparent),
    color: ThemeColors.orange.withValues(alpha: 0.7),
  );
  static final _dateFormat = DateFormat('dd.MM.yyyy');

  /// `YYYY-MM-DD`, or null when unscheduled.
  final String? airDate;

  const UpcomingEpisodePill(this.airDate, {super.key});

  static String label(String? airDate) {
    final date = airDate == null ? null : DateTime.tryParse(airDate);
    return date == null ? 'Airs TBA' : 'Airs ${_dateFormat.format(date)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 105,
      height: 20,
      decoration: _decoration,
      // Explicit white label and a scale-down FittedBox, as on the finale pills: the date label is
      // close to the fixed 105px width.
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(label(airDate), maxLines: 1, style: const TextStyle(fontSize: 12, color: ThemeColors.white)),
          ),
        ),
      ),
    );
  }
}
