import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Red counterpart of the green `SeasonPremierePill`: the episode ends a season (or the show).
///
/// Driven off the episode's classification (TMDB's `episode_type` plus local inference), so it only appears on an episode labelled as a
/// finale — the latest episode of a season that is still airing does not get one.
///
/// Geometry matches the premiere pill exactly so the two are visually interchangeable in the
/// poster's top-left corner.
class _FinalePill extends StatelessWidget {
  static final _decoration = BoxDecoration(
    border: Border.all(width: 0, color: Colors.transparent),
    color: ThemeColors.red.withValues(alpha: 0.7),
  );

  final String _label;

  const _FinalePill(this._label);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 105,
      height: 20,
      decoration: _decoration,
      // The label colour is explicit: inheriting the theme's body colour makes the text
      // unreadable on the red fill in the light theme. The FittedBox keeps the longest label
      // ('Mid-Season Finale') inside the fixed 105px width instead of overflowing it, while the
      // shorter ones stay at their natural 12px.
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(_label, maxLines: 1, style: const TextStyle(fontSize: 12, color: ThemeColors.white)),
          ),
        ),
      ),
    );
  }
}

class SeasonFinalePill extends StatelessWidget {
  const SeasonFinalePill({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FinalePill('Season Finale');
  }
}

class SeriesFinalePill extends StatelessWidget {
  const SeriesFinalePill({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FinalePill('Series Finale');
  }
}

class MidSeasonFinalePill extends StatelessWidget {
  const MidSeasonFinalePill({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FinalePill('Mid-Season Finale');
  }
}
