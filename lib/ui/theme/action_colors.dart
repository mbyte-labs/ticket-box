import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The colours of the three library actions — check in, mark as watched, add to watchlist.
///
/// These sit outside the M3 colour roles on purpose. The chrome is red, but the actions have to
/// stay tellable apart at a glance wherever they appear, so each keeps a fixed hue: red, violet
/// and blue respectively.
///
/// Each action comes as a **pair**, because one colour cannot do both jobs on a dark app:
///
/// * the *fill* is what goes behind [onAction] — chosen to clear 4.5:1 against white;
/// * the *accent* is the lighter tint used when the colour is drawn straight onto a dark surface
///   as text, an icon or a border — chosen to clear 4.5:1 against [ThemeColors.greyScale900].
///
/// Using a fill as a foreground is the mistake this pairing exists to prevent: the check-in red
/// is 4.68:1 on white but only 2.67:1 on the app's own background.
///
/// Read them through [ActionColorsX.actionColors] rather than reaching for [ThemeColors] directly,
/// so a widget picks up whatever theme it is actually rendered under.
@immutable
class ActionColors extends ThemeExtension<ActionColors> {
  /// Check in — red fill.
  final Color checkIn;

  /// Check in — red accent. The heads-up banner's label, icon, border and progress bar.
  final Color checkInAccent;

  /// Mark as watched — violet fill. Also the watched badge and the poster pill.
  final Color markWatched;

  /// Mark as watched — violet accent. The outlined `Watched · <date>` / `12 / 24 watched` button
  /// and the details page's watch-progress bar.
  final Color markWatchedAccent;

  /// Add to watchlist — blue fill. The details toggle once selected, and the poster pill.
  final Color watchlist;

  /// Add to watchlist — blue accent. The details toggle's unselected outline and icon.
  final Color watchlistAccent;

  /// Foreground for labels and icons sitting on any of the three fills.
  final Color onAction;

  const ActionColors({
    required this.checkIn,
    required this.checkInAccent,
    required this.markWatched,
    required this.markWatchedAccent,
    required this.watchlist,
    required this.watchlistAccent,
    required this.onAction,
  });

  static const dark = ActionColors(
    checkIn: ThemeColors.actionCheckIn,
    checkInAccent: ThemeColors.actionCheckInAccent,
    markWatched: ThemeColors.actionMarkWatched,
    markWatchedAccent: ThemeColors.actionMarkWatchedAccent,
    watchlist: ThemeColors.actionWatchlist,
    watchlistAccent: ThemeColors.actionWatchlistAccent,
    onAction: ThemeColors.white,
  );

  @override
  ActionColors copyWith({
    Color? checkIn,
    Color? checkInAccent,
    Color? markWatched,
    Color? markWatchedAccent,
    Color? watchlist,
    Color? watchlistAccent,
    Color? onAction,
  }) {
    return ActionColors(
      checkIn: checkIn ?? this.checkIn,
      checkInAccent: checkInAccent ?? this.checkInAccent,
      markWatched: markWatched ?? this.markWatched,
      markWatchedAccent: markWatchedAccent ?? this.markWatchedAccent,
      watchlist: watchlist ?? this.watchlist,
      watchlistAccent: watchlistAccent ?? this.watchlistAccent,
      onAction: onAction ?? this.onAction,
    );
  }

  @override
  ActionColors lerp(ThemeExtension<ActionColors>? other, double t) {
    if (other is! ActionColors) {
      return this;
    }
    return ActionColors(
      checkIn: Color.lerp(checkIn, other.checkIn, t)!,
      checkInAccent: Color.lerp(checkInAccent, other.checkInAccent, t)!,
      markWatched: Color.lerp(markWatched, other.markWatched, t)!,
      markWatchedAccent: Color.lerp(markWatchedAccent, other.markWatchedAccent, t)!,
      watchlist: Color.lerp(watchlist, other.watchlist, t)!,
      watchlistAccent: Color.lerp(watchlistAccent, other.watchlistAccent, t)!,
      onAction: Color.lerp(onAction, other.onAction, t)!,
    );
  }
}

extension ActionColorsX on BuildContext {
  /// The action palette of the theme this widget is rendered under.
  ///
  /// Non-null because [ActionColors.dark] is registered on the only theme the app ships.
  ActionColors get actionColors => Theme.of(this).extension<ActionColors>()!;
}
