import 'package:flutter/material.dart';

// 100% - FF
// 95% - F2
// 90% - E6
// 85% - D9
// 80% - CC
// 75% - BF
// 70% - B3
// 65% - A6
// 60% - 99
// 55% - 8C
// 50% - 80
// 45% - 73
// 40% - 66
// 35% - 59
// 30% - 4D
// 25% - 40
// 20% - 33
// 15% - 26
// 10% - 1A
// 5% - 0D
// 0% - 00
class ThemeColors {
  //
  //
  //
  // --------- MAIN

  /// #F5484A — the brand accent: nav selection, chips, buttons, borders, rating hearts.
  ///
  /// 4.53:1 on [greyScale900], so it works as a foreground as well as a fill.
  static const primary = Color(0xFFF5484A);

  static const primary900 = primary;

  /// #F65A5C
  static const primary800 = Color(0xFFF65A5C);

  /// #F76D6E
  static const primary700 = Color(0xFFF76D6E);

  /// #F87F80
  static const primary600 = Color(0xFFF87F80);

  /// #F99192
  static const primary500 = Color(0xFFF99192);

  /// #FAA4A5
  static const primary400 = Color(0xFFFAA4A5);

  /// #FBB6B7
  static const primary300 = Color(0xFFFBB6B7);

  /// #FCC8C9
  static const primary200 = Color(0xFFFCC8C9);

  /// #FDDADB
  static const primary100 = Color(0xFFFDDADB);

  /// #FEEDED
  static const primary50 = Color(0xFFFEEDED);

  /// #7F1D1D — the deep red, sitting below [primary900] rather than on the 900..50 ramp: the fill
  /// behind a white label in M3's `primaryContainer` / `secondaryContainer` / `tertiaryContainer` /
  /// `errorContainer` roles, at 10.0:1.
  ///
  /// A *fill* only — far too dark to be drawn as text on [greyScale900]. See the fill/accent rule
  /// in `AGENTS.md`. Deliberately not [actionCheckIn], which is check-in's own identity colour.
  static const primaryDeep = Color(0xFF7F1D1D);

  /// #E91E63 — the logo pink. Loading only: every progress indicator in the app gets this from
  /// `progressIndicatorTheme`. Never hand-apply it to a widget — that is how it ended up scattered
  /// across a dozen call sites before. Deliberately not the brand accent; that is [primary].
  static const loadingIndicator = Color(0xFFE91E63);

  /// #FF9800
  static const secondary = Color(0xFFFF9800);

  /// #FF9800
  static const secondary900 = secondary;

  /// #FFA21A
  static const secondary800 = Color(0xFFFFA21A);

  /// #FFAD33
  static const secondary700 = Color(0xFFFFAD33);

  /// #FFB74D
  static const secondary600 = Color(0xFFFFB74D);

  /// #FFC166
  static const secondary500 = Color(0xFFFFC166);

  /// #FFCC80
  static const secondary400 = Color(0xFFFFCC80);

  /// #FFD699
  static const secondary300 = Color(0xFFFFD699);

  /// #FFE0B3
  static const secondary200 = Color(0xFFFFE0B3);

  /// #FFEACC
  static const secondary100 = Color(0xFFFFEACC);

  /// #FFF5E6
  static const secondary50 = Color(0xFFFFF5E6);

  //
  //
  //
  // ---------  ALERT AND STATUS

  /// #12D18E
  static const success = Color(0xFF12D18E);

  /// #246BFD
  static const info = Color(0xFF246BFD);

  /// #FACC15
  static const warning = Color(0xFFFACC15);

  /// #c43a3b
  static const error = Color(0xFFF75555);

  /// #D8D8D8
  static const disabled = Color(0xFFD8D8D8);

  /// #c43a3b
  static const disabledButton = Color(0xFFC43A3B);

  //
  //
  //
  // ---------  ACTION COLORS
  //
  // The three library actions keep bespoke hues so they stay distinguishable from each other and
  // from the red chrome. Reach for them through the ActionColors ThemeExtension, not directly.
  // All three clear 4.5:1 against white.

  /// #C61017 — check in, as a fill behind a white label.
  static const actionCheckIn = Color(0xFFC61017);

  /// #F5484A — check in, as a foreground on a dark surface: the banner's label, icon, border and
  /// progress bar. [actionCheckIn] is only 2.67:1 against [greyScale900] and unreadable as text;
  /// this is 4.53:1.
  ///
  /// Currently the same value as [primary]. Kept as its own token so the banner stays pinned to
  /// check-in's identity rather than to whatever the brand accent happens to be.
  static const actionCheckInAccent = Color(0xFFF5484A);

  /// #8E44AD — mark as watched, as a fill behind a white label or icon.
  static const actionMarkWatched = Color(0xFF8E44AD);

  /// #B685CA — mark as watched, as a foreground on a dark surface: the outlined
  /// `Watched · <date>` / `12 / 24 watched` button and the watch-progress bar.
  /// [actionMarkWatched] is only 2.75:1 against [greyScale900]; this is 5.52:1.
  static const actionMarkWatchedAccent = Color(0xFFB685CA);

  /// #1565C0 — add to watchlist, as a fill behind a white label or icon. Deliberately not
  /// Material Blue 500, which is only 3.12:1 against white.
  static const actionWatchlist = Color(0xFF1565C0);

  /// #64B5F6 — add to watchlist, as a foreground on a dark surface: the details toggle's
  /// unselected outline and icon. [actionWatchlist] is only 2.83:1 there; this is 7.27:1.
  static const actionWatchlistAccent = Color(0xFF64B5F6);

  /// Fill of the details pages' "favorite" badge: a heart pink that stays
  /// apart from the three action colours and the red chrome. 5.1:1 behind white.
  static const favorite = Color(0xFFC2185B);

  //
  //
  //
  // ---------  BRAND (third-party rating sources)
  //
  // Logo tints only — the value/caption text next to them stays on the surface roles.

  /// #F5C518 — IMDb brand yellow, for the IMDb logo on the Ratings card.
  static const brandImdb = Color(0xFFF5C518);

  /// #01B4E4 — TMDB brand light blue, for the TMDB logo on the Ratings card.
  static const brandTmdb = Color(0xFF01B4E4);

  /// #FF0000 — YouTube brand red, for the trailer link on the details pages.
  static const brandYoutube = Color(0xFFFF0000);

  /// #FF4500 — Reddit brand orange, for the community link on the About page.
  static const brandReddit = Color(0xFFFF4500);

  /// #5865F2 — Discord brand blurple, for the community link on the About page.
  static const brandDiscord = Color(0xFF5865F2);

  //
  //
  //
  // ---------  GREYSCALE

  /// #212121
  static const greyScale900 = Color(0xFF212121);

  /// #424242
  static const greyScale800 = Color(0xFF424242);

  /// #616161
  static const greyScale700 = Color(0xFF616161);

  /// #757575
  static const greyScale600 = Color(0xFF757575);

  /// #9E9E9E
  static const greyScale500 = Color(0xFF9E9E9E);

  /// #BDBDBD
  static const greyScale400 = Color(0xFFBDBDBD);

  /// #E0E0E0
  static const greyScale300 = Color(0xFFE0E0E0);

  /// #EEEEEE
  static const greyScale200 = Color(0xFFEEEEEE);

  /// #F5F5F5
  static const greyScale100 = Color(0xFFF5F5F5);

  /// #FAFAFA
  static const greyScale50 = Color(0xFFFAFAFA);

  //
  //
  //
  // ---------  DARK COLORS
  //
  // The elevation ladder for chrome that is not a plain [greyScale900] page: dialogs, the search
  // bar, dividers, chart furniture. **Neutral by construction** — every one of these has R = G = B.
  // They used to be cool blue-greys (`dark2` was #1F222A, blue +11 over red), which fought the
  // warm M3 scheme and made the app read tinted rather than simply dark. The values below are
  // luminance-matched to those originals, so only the hue changed.
  //
  // [dark2] is the one deliberate departure: its exact neutral twin is #222222, which would
  // collide with the [greyScale900] page. It sits slightly recessed instead, which is the
  // relationship the blue-grey version had — dialogs and the search bar read *below* the page.

  /// #1A1A1A
  static const dark1 = Color(0xFF1A1A1A);

  /// #1C1C1C
  static const dark2 = Color(0xFF1C1C1C);

  /// #262626
  static const dark3 = Color(0xFF262626);

  /// #363636
  static const dark4 = Color(0xFF363636);

  //
  //
  //
  // ---------  Others

  /// #FFFFFF
  static const white = Color(0xFFFFFFFF);

  /// #000000
  static const black = Color(0xFF000000);

  /// #F44336
  static const red = Color(0xFFF54336);

  /// #E91E63
  static const pink = Color(0xFFE91E63);

  /// #9C27B0
  static const purple = Color(0xFF9C27B0);

  /// #673AB7
  static const deepPurple = Color(0xFF673AB7);

  /// #3F51B5
  static const indigo = Color(0xFF3F51B5);

  /// #2196F3
  static const blue = Color(0xFF2196F3);

  /// #03A9F4
  static const lightblue = Color(0xFF03A9F4);

  /// #00BCD4
  static const cyan = Color(0xFF00BCD4);

  /// #009688
  static const teal = Color(0xFF009688);

  /// #4CAF50
  static const green = Color(0xFF4CAF50);

  /// #8BC34A
  static const lightGreen = Color(0xFF8BC34A);

  /// #CDDC39
  static const lime = Color(0xFFCDDC39);

  /// #FFEB3B
  static const yellow = Color(0xFFFFEB3B);

  /// #FFC107
  static const amber = Color(0xFFFFC107);

  /// #FF9800
  static const orange = Color(0xFFFF9800);

  /// #FF5722
  static const deepOrange = Color(0xFFFF5722);

  /// #795548
  static const brown = Color(0xFF795548);

  /// #607D8B
  static const blueGrey = Color(0xFF607D8B);

  //
  //
  //
  // ---------  Gradient

  /// #F5484A & #F7375
  static const gradientRed = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [Color(0xfff5484a), Color(0xffff7375)],
  );

  static const gradientYellow = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [Color(0xfffacc15), Color(0xffffe57f)],
  );

  static const gradientOrange = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [Color(0xfff89300), Color(0xffffbb58)],
  );

  static const gradientGreen = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [Color(0xff12d18e), Color(0xff71e3bb)],
  );

  static const gradientBlue = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [Color(0xff246bfd), Color(0xff5089fd)],
  );

  static const gradientPurple = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [Color(0xff6949ff), Color(0xff876dff)],
  );

  static const gradientTeal = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [Color(0xff019b83), Color(0xff17c5aa)],
  );

  //
  //
  //
  // ---------  Background

  /// #FFF4F4
  static const backgroundRed = Color(0xFFFFF4F4);

  /// #FFFCEB
  static const backgroundYellow = Color(0xFFFFFCEB);

  /// #FFF8EE
  static const backgroundOrage = Color(0xFFFFF8EE);

  /// #F1FDF5
  static const backgroundGreen = Color(0xFFF1FDF5);

  /// #F6F9FF
  static const backgroundBlue = Color(0xFFF6F9FF);

  /// #F9F8FF
  static const backgroundPurple = Color(0xFFF9F8FF);

  /// #F2FFFD
  static const backgroundTeal = Color(0xFFF2FFFD);

  //
  //
  //
  // ---------  Transparent

  /// #F5484A
  static const transparentRed = Color(0x14f5484a);

  /// #FFD300
  static const transparentYellow = Color(0x14ffd300);

  /// #F89300
  static const transparentOrange = Color(0x14f89300);

  /// #12D18E
  static const transparentGreen = Color(0x141bac4b);

  /// #246BFD
  static const transparentBlue = Color(0x14246bfd);

  /// #6949FF
  static const transparentPurple = Color(0x146949ff);

  /// #019B83
  static const transparentTeal = Color(0x14019b83);

  /// ##00BCD4
  static const transparentCyan = Color(0x1400bcd4);
}
