// WHOOP Material theme from an explicit palette. The active screen type scale
// lives in ui2 F styles; bundled fonts and palette-driven Material styles stay
// here. Light/dark ThemeData remain internally consistent during mode changes.

// iOS/macOS page transitions are NOT named here on purpose.
//
// CupertinoPageTransitionsBuilder has MOVED between SDK versions: on 3.41.6
// (the pinned toolchain, see .github/workflows/test.yml) material.dart exports
// it and cupertino.dart does not; on 3.44.x it is the other way round. So there
// is no single import that compiles on both — importing from cupertino breaks
// the pin with "doesn't export a member with the shown name", and importing
// from material breaks newer SDKs with "isn't defined", which also takes the
// surrounding const map down with it.
//
// Spreading PageTransitionsTheme's own defaults sidesteps the question: the SDK
// already maps iOS/macOS to whatever Cupertino builder that version ships, so
// we override only the platforms we actually want changed and never name the
// moving class. Version-proof in both directions.
//
// Do not "simplify" this back to an explicit iOS entry. The Cupertino builder
// is what supplies the interactive edge-swipe-back gesture — see
// page_transitions.dart's navigation contract.
import 'package:flutter/material.dart';
import 'page_transitions.dart';
import 'tokens.dart';

/// Type scale — one family (Manrope). Numerics carry tabular figures.
/// Colours come from the live [AppColors] getters → they track the active mode.
/// Manrope, bundled as a local asset (pubspec.yaml `flutter.fonts`) rather
/// than resolved through google_fonts, which fetches the family from
/// fonts.gstatic.com on first launch, which a local-first app should never
/// do. Same call shape as `GoogleFonts.manrope(...)`, no network.
TextStyle _manrope({
  double? fontSize,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
  Color? color,
}) => TextStyle(
  fontFamily: 'Manrope',
  fontSize: fontSize,
  fontWeight: fontWeight,
  height: height,
  letterSpacing: letterSpacing,
  color: color,
);

/// Build the full theme from an explicit [Palette] so light/dark are each
/// self-consistent. Call with [kLightPalette] / [kDarkPalette].
ThemeData buildWhoopTheme(Palette p) {
  // Material's `primary` drives every routine/non-evaluative default (Switch,
  // ProgressIndicator, FilledButton, focus rings, splash) — that's brand
  // identity territory, not alert territory, so it seeds from `p.brand` (calm
  // cyan/teal), never `p.coral` (reserved for genuinely low/urgent states).
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.brand,
        brightness: p.brightness,
      ).copyWith(
        surface: p.surface,
        onSurface: p.ink,
        primary: p.brand,
        onPrimary: Colors.white,
        secondary: p.brandDeep,
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    dividerColor: p.divider,
    splashColor: p.brand.withValues(alpha: 0.08),
    highlightColor: p.brand.withValues(alpha: 0.05),
    textTheme: (p.brightness == Brightness.dark
            ? Typography.material2021().white
            : Typography.material2021().black)
        .apply(
      fontFamily: 'Manrope',
      bodyColor: p.ink,
      displayColor: p.ink,
    ),
    // Page transitions live HERE (not in a custom PageRouteBuilder) so pushed
    // routes stay MaterialPageRoutes: iOS keeps the native slide transition
    // AND the interactive edge-swipe-back gesture; Android-likes get the
    // app's shared-axis fade-through. See page_transitions.dart.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        // iOS/macOS come from the SDK defaults — see the note at the top.
        ...const PageTransitionsTheme().builders,
        TargetPlatform.android: const SharedAxisPageTransitionsBuilder(),
        TargetPlatform.fuchsia: const SharedAxisPageTransitionsBuilder(),
        TargetPlatform.linux: const SharedAxisPageTransitionsBuilder(),
        TargetPlatform.windows: const SharedAxisPageTransitionsBuilder(),
      },
    ),
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: _manrope(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.35,
        color: p.ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Sp.x5,
        vertical: Sp.x4,
      ),
      hintStyle: _manrope(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        color: p.inkMuted,
      ),
      labelStyle: _manrope(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        color: p.inkSoft,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.cardSm),
        borderSide: BorderSide(color: p.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.cardSm),
        borderSide: BorderSide(color: p.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.cardSm),
        borderSide: BorderSide(color: p.brand, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Default FilledButton = the routine primary-action colour (brand
        // teal). Genuinely destructive actions override this explicitly with
        // AppColors.critical at the call site (see profile_screen's confirm
        // dialog) — that pattern is unaffected by this change.
        backgroundColor: p.brand,
        foregroundColor: Colors.white,
        disabledBackgroundColor: p.inkMuted.withValues(alpha: 0.35),
        minimumSize: const Size(0, 56),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.pill),
        ),
        textStyle: _manrope(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(0, 56),
        side: BorderSide(color: p.divider, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.pill),
        ),
        textStyle: _manrope(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.brandDeep,
        textStyle: _manrope(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.isDark ? p.surfaceAlt : AppColors.night,
      contentTextStyle: _manrope(color: AppColors.onNight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.chip),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.card)),
      ),
    ),
  );
}
