import 'package:flutter/material.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The app's only colour scheme. Ticket Box is dark-only by design — there is no light
/// counterpart here, and `main.dart` points both of MaterialApp's theme slots at the dark theme
/// so no light fallback can surface.
///
/// **Hand-authored — do not paste Material Theme Builder output in here.** This used to be raw
/// builder output, which carried the builder's warm pink hue on every role: `surfaceContainerHighest`
/// was #534342, `onSurfaceVariant` #D8C2C0, `primary` a pale pink #FFB3AE. Since the app leans on
/// those roles heavily — `surfaceContainerHighest` backs every details card, `onSurfaceVariant`
/// every piece of secondary text — the whole app read pink-tinted. Two rules keep it clean:
///
/// 1. **Every surface, foreground and line role is a neutral grey** (R = G = B), taken from the
///    [ThemeColors] greyscale.
/// 2. **Every accent role is the brand red**, per `AGENTS.md`. The logo pink keeps its single job:
///    progress indicators, set once as `progressIndicatorTheme`.
class ThemeDefinitionColors {
  static const darkColorScheme = ColorScheme(
    brightness: Brightness.dark,

    // ---------  ACCENT
    //
    // `primary` is what M3 reaches for in everything the sub-themes in `theme_definition.dart`
    // don't override: the text cursor and selection handles, focused input borders, the discover
    // RangeSliders, date-picker selection, check icons. It was the pale pink; it is the brand red.
    //
    // `secondary` and `tertiary` point at the same red on purpose — the app has no second accent,
    // and leaving them on the builder's pinks is how an untouched M3 widget sneaks pink back in.
    //
    // White on [ThemeColors.primary] is 3.55:1, below AA for body text. That is the long-standing,
    // deliberate tradeoff documented in `AGENTS.md`, and already how `elevatedButtonTheme` behaves.
    primary: ThemeColors.primary,
    onPrimary: ThemeColors.white,
    primaryContainer: ThemeColors.primaryDeep,
    onPrimaryContainer: ThemeColors.white,
    secondary: ThemeColors.primary,
    onSecondary: ThemeColors.white,
    secondaryContainer: ThemeColors.primaryDeep,
    onSecondaryContainer: ThemeColors.white,
    tertiary: ThemeColors.primary,
    onTertiary: ThemeColors.white,
    tertiaryContainer: ThemeColors.primaryDeep,
    onTertiaryContainer: ThemeColors.white,

    // ---------  ERROR
    //
    // Near-identical to the accent red, which is unavoidable on a red-accented app and was already
    // true before (both roles were pale pink). Destructive controls — the outlined
    // `Remove from history` button, the drawer's profile-load failure banner — are told apart by
    // their labels, not their hue.
    error: ThemeColors.error,
    onError: ThemeColors.white,
    errorContainer: ThemeColors.primaryDeep,
    onErrorContainer: ThemeColors.white,

    // ---------  SURFACES
    //
    // A neutral ladder, set explicitly. The `surfaceContainer*` roles used to be omitted, and
    // Flutter silently falls those back to `surface` (`surfaceContainerHigh => _surfaceContainerHigh
    // ?? surface`), so the layering was never intentional — date pickers, which default to
    // `surfaceContainerHigh`, were flat against the page.
    //
    // [ThemeColors.greyScale800] for `surfaceContainerHighest` is load-bearing. It is the luminance
    // twin of the old #534342, so the eleven call sites that composite it at alpha 0.25–0.35 over
    // the page keep their exact brightness and lose only the hue (#302B2B becomes #2B2B2B). It also
    // has to hold up *opaque*, as the LinearProgressIndicator track in `SyncProgressBar` and the
    // details action bar, behind both the pink loading fill and the violet watch-progress fill.
    surface: ThemeColors.greyScale900,
    surfaceDim: ThemeColors.dark1,
    surfaceBright: Color(0xFF2A2A2A),
    surfaceContainerLowest: Color(0xFF161616),
    surfaceContainerLow: ThemeColors.dark2,
    surfaceContainer: ThemeColors.greyScale900,
    surfaceContainerHigh: Color(0xFF2A2A2A),
    surfaceContainerHighest: ThemeColors.greyScale800,

    // Inert in Flutter 3.44 — every M3 component default now sets `surfaceTintColor:
    // Colors.transparent`, so the elevation overlay never runs. Pinned to the surface colour
    // anyway, so that if some widget does opt back in, the overlay is a no-op instead of a tint.
    surfaceTint: ThemeColors.greyScale900,

    // ---------  FOREGROUNDS AND LINES
    //
    // `onSurfaceVariant` is the workhorse: ~79 call sites of secondary text and icons. At 8.57:1 it
    // is a touch dimmer than the exact twin of the old #D8C2C0, which helps — body text is pure
    // white, so the extra gap sharpens the hierarchy.
    onSurface: ThemeColors.white,
    onSurfaceVariant: ThemeColors.greyScale400,
    outline: ThemeColors.greyScale500,
    outlineVariant: ThemeColors.greyScale800,

    // ---------  INVERSE
    //
    // `inverseSurface` is the M3 default background for Tooltip, of which the details pages have a
    // dozen. It was #EDE0DE — a pink-tinted white. SnackBars would take it too, but
    // `theme_definition.dart` gives them an explicit dark `snackBarTheme` instead.
    inverseSurface: Color(0xFFE6E6E6),
    onInverseSurface: ThemeColors.greyScale900,
    inversePrimary: ThemeColors.primaryDeep,

    shadow: ThemeColors.black,
    scrim: ThemeColors.black,
  );
}
