//import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/theme/action_colors.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';
import 'package:ticketbox/ui/theme/theme_definition_colors.dart';

class ThemeDefinition {
  //static const String fontFamily = "Urbanist";
  static const String? fontFamily = null;

  /// Built once. The sub-themes below are all constant, so rebuilding this per frame — which is
  /// what happened while `main.dart` called the builder straight from `build()` — was pure waste.
  static final ThemeData darkTheme = _buildDarkTheme();

  static ThemeData getDarkTheme() => darkTheme;

  static ThemeData _buildDarkTheme() {
    VisualDensity visualDensity = VisualDensity.standard;
    // if (kIsWeb) {
    //   visualDensity = VisualDensity.compact;
    // }

    // Built first so the sub-themes below can `copyWith` off the M3 defaults rather than
    // restating every field.
    final theme = ThemeData(
      visualDensity: visualDensity,
      useMaterial3: true,
      colorScheme: ThemeDefinitionColors.darkColorScheme,
      fontFamily: fontFamily,
    );

    return theme.copyWith(
      extensions: const <ThemeExtension<dynamic>>[ActionColors.dark],
      bottomNavigationBarTheme: theme.bottomNavigationBarTheme.copyWith(
        backgroundColor: ThemeColors.greyScale900,
        selectedItemColor: ThemeColors.primary,
        unselectedItemColor: ThemeColors.greyScale500,
        selectedLabelStyle: const TextStyle(fontSize: 10, color: ThemeColors.primary, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 10, color: ThemeColors.greyScale500, fontWeight: FontWeight.w500),
      ),
      navigationRailTheme: theme.navigationRailTheme.copyWith(
        backgroundColor: ThemeColors.greyScale900,
        indicatorColor: ThemeColors.greyScale900,
        useIndicator: false,
        selectedIconTheme: const IconThemeData(color: ThemeColors.primary, size: 24),
        unselectedIconTheme: const IconThemeData(color: ThemeColors.greyScale500, size: 24),
        selectedLabelTextStyle: const TextStyle(fontSize: 10, letterSpacing: 00.2, color: ThemeColors.primary, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: const TextStyle(fontSize: 10, color: ThemeColors.greyScale500, fontWeight: FontWeight.w500),
      ),
      drawerTheme: theme.drawerTheme.copyWith(backgroundColor: ThemeColors.greyScale900, surfaceTintColor: ThemeColors.greyScale900),
      navigationDrawerTheme: theme.navigationDrawerTheme.copyWith(
        backgroundColor: ThemeColors.greyScale900,
        surfaceTintColor: ThemeColors.greyScale900,
        // The red accent lives on the selected icon/label (matching bottom nav and rail above);
        // a primary-red indicator fill would be low-contrast behind it.
        indicatorColor: ThemeColors.dark4,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
          (Set<WidgetState> states) =>
              IconThemeData(color: states.contains(WidgetState.selected) ? ThemeColors.primary : ThemeColors.greyScale500, size: 24),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? const TextStyle(fontFamily: fontFamily, fontSize: 14, color: ThemeColors.primary, fontWeight: FontWeight.w700)
              : const TextStyle(fontFamily: fontFamily, fontSize: 14, color: ThemeColors.greyScale300, fontWeight: FontWeight.w500),
        ),
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: ThemeColors.greyScale900,
        surfaceTintColor: ThemeColors.dark4,
        centerTitle: false,
        // Set here rather than per-page so every AppBar/SliverAppBar gets it. The two colour
        // fields are no-ops on Android 15+ (the bars are always transparent there) but still
        // apply on API 29-34; the brightness fields are what keep the icons legible over the
        // dark app bar now that it extends behind the status bar.
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
        iconTheme: const IconThemeData(color: ThemeColors.white, size: 28),
        titleTextStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ThemeColors.white),
      ),
      searchBarTheme: theme.searchBarTheme.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) => ThemeColors.dark2),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) => ThemeColors.dark2),
        surfaceTintColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) => ThemeColors.dark2),
        elevation: WidgetStateProperty.all(0),
        textStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (Set<WidgetState> states) => const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            color: ThemeColors.white,
            fontStyle: FontStyle.normal,
            fontWeight: FontWeight.w600,
          ),
        ),
        hintStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (Set<WidgetState> states) => const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            color: ThemeColors.greyScale600,
            fontStyle: FontStyle.normal,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      bottomSheetTheme: theme.bottomSheetTheme.copyWith(
        backgroundColor: ThemeColors.greyScale900,
        surfaceTintColor: ThemeColors.greyScale900,
        showDragHandle: true,
      ),
      popupMenuTheme: theme.popupMenuTheme.copyWith(
        color: ThemeColors.greyScale900,
        surfaceTintColor: ThemeColors.dark4,
        iconColor: ThemeColors.greyScale50,
        textStyle: const TextStyle(color: ThemeColors.greyScale50),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        iconColor: ThemeColors.white,
        textColor: ThemeColors.white,
        titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ThemeColors.white),
        leadingAndTrailingTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ThemeColors.white),
        subtitleTextStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ThemeColors.greyScale700),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        contentPadding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        labelStyle: const TextStyle(fontFamily: ThemeDefinition.fontFamily, fontWeight: FontWeight.w500, color: ThemeColors.white),
        floatingLabelStyle: const TextStyle(fontFamily: ThemeDefinition.fontFamily, fontWeight: FontWeight.w500, color: ThemeColors.white),
        helperStyle: const TextStyle(
          fontFamily: ThemeDefinition.fontFamily,
          fontWeight: FontWeight.w400,
          color: ThemeColors.greyScale300,
          fontSize: 12,
        ),
        filled: false,
        fillColor: ThemeColors.dark2,
      ),
      dividerTheme: theme.dividerTheme.copyWith(color: ThemeColors.dark4, indent: 5, endIndent: 5, thickness: 2),
      buttonTheme: theme.buttonTheme.copyWith(
        buttonColor: ThemeColors.dark2,
        hoverColor: ThemeColors.dark4,
        highlightColor: ThemeColors.dark4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          // Disabled buttons are greyed out, the same way the outlined and text button themes
          // below do it. Without this a disabled button is indistinguishable from an enabled one.
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) => states.contains(WidgetState.disabled) ? ThemeColors.greyScale800 : ThemeColors.primary,
          ),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) => ThemeColors.primary),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) => states.contains(WidgetState.disabled) ? ThemeColors.greyScale600 : ThemeColors.white,
          ),
          textStyle: WidgetStateProperty.resolveWith<TextStyle?>(
            (Set<WidgetState> states) =>
                const TextStyle(fontFamily: fontFamily, fontSize: 16, color: ThemeColors.white, fontStyle: FontStyle.normal),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) => ThemeColors.greyScale900),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) => ThemeColors.primary),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) => ThemeColors.white),
          side: WidgetStateProperty.resolveWith<BorderSide?>(
            (Set<WidgetState> states) => const BorderSide(color: ThemeColors.primary, width: 1),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.disabled)) {
              return ThemeColors.greyScale600;
            }
            return ThemeColors.white;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return ThemeColors.greyScale600;
            }
            return ThemeColors.primary900;
          }),
        ),
      ),
      chipTheme: theme.chipTheme.copyWith(
        selectedColor: ThemeColors.primary900,
        side: const BorderSide(color: ThemeColors.primary900),
        // shape: RoundedRectangleBorder(
        //   borderRadius: BorderRadius.circular(20),
        //   side: const BorderSide(color: ThemeColors.primary900),
        // ),
      ),
      dialogTheme: theme.dialogTheme.copyWith(
        surfaceTintColor: ThemeColors.dark2,
        backgroundColor: ThemeColors.dark2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      // `showDatePicker` / `showTimePicker` do not read `dialogTheme` — their M3 default background
      // is `colorScheme.surfaceContainerHigh`. Pinned to the same colour as `dialogTheme` above so
      // every dialog in the app sits at one depth; without this the pickers read as raised while
      // AlertDialog reads as recessed.
      datePickerTheme: theme.datePickerTheme.copyWith(backgroundColor: ThemeColors.dark2),
      timePickerTheme: theme.timePickerTheme.copyWith(backgroundColor: ThemeColors.dark2),
      // SnackBars carry no colour at their ~15 call sites, so left alone they take M3's default —
      // the near-white `colorScheme.inverseSurface`, which is jarring in an all-dark app.
      snackBarTheme: theme.snackBarTheme.copyWith(
        backgroundColor: ThemeColors.dark3,
        contentTextStyle: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        actionTextColor: ThemeColors.primary,
      ),
      switchTheme: theme.switchTheme.copyWith(
        trackOutlineColor: WidgetStateProperty.all(ThemeColors.primary900),
        trackColor: WidgetStateProperty.all(ThemeColors.primary900),
        thumbColor: WidgetStateProperty.all(ThemeColors.white),
        trackOutlineWidth: WidgetStateProperty.all(0),
      ),
      // Every progress indicator in the app is pink, resolved here rather than at ~14 call sites.
      // Flutter picks valueColor -> color -> this -> colorScheme.primary, so the three indicators
      // that carry an action colour (check-in red, watch-progress violet, watchlist blue) still
      // override it locally, and everything else needs no colour argument at all.
      progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(color: ThemeColors.loadingIndicator),
      iconTheme: theme.iconTheme.copyWith(color: ThemeColors.white),
      textTheme: theme.textTheme.copyWith(
        bodyLarge: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        bodyMedium: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        bodySmall: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        displayLarge: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        displayMedium: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        displaySmall: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        headlineLarge: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        headlineMedium: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        headlineSmall: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        labelLarge: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        labelMedium: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        labelSmall: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        titleLarge: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        titleMedium: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
        titleSmall: const TextStyle(fontFamily: fontFamily, color: ThemeColors.white),
      ),
    );
  }
}
