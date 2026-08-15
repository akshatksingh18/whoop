// OpenStrap theme — TWO type voices, ember-coral on paper (day) or char
// (night). `AppText` is the type scale; every numeric/metric style carries
// tabular figures so big numbers align and count-ups don't jitter. Text colours
// resolve through the live `AppColors` getters, so the type scale follows the
// active mode for free.
//
// Why two voices: a hero number (Readiness, Strain, Sleep score) and a
// plain-language sentence (an AI briefing, an insight caption) are two
// different KINDS of information and should read that way.
//  - `hero`/`display`/`metric`/`metricSm` (the big tabular figures) use
//    Barlow Condensed at heavy weight + slight tracking — confident and
//    kinetic, athletic-brand register. BUNDLED locally (assets/fonts/
//    BarlowCondensed/*.ttf, declared in pubspec.yaml's `flutter.fonts`) —
//    this app is local-first/offline by design, and the readiness ring's
//    numeral is the last thing that should be able to flicker or fall back
//    on a cold offline launch, which a google_fonts runtime HTTP fetch can
//    do on first use. SIL Open Font License (OFL.txt ships alongside the
//    .ttf files).
//  - Everything else (`h1`/`h2`/`title`/`body`/`bodySoft`/`label`/`caption`/
//    `overline`) uses Manrope, bundled the same way (assets/fonts/Manrope/
//    *.ttf, OFL.txt alongside). It used to resolve through google_fonts,
//    which fetches the family from fonts.gstatic.com on first launch — before
//    the consent screen, and contrary to PRIVACY.md.
//
// `buildOpenStrapTheme(palette)` builds a full ThemeData from an explicit
// [Palette] (not the live getters) so the light + dark ThemeData objects are
// each internally consistent regardless of which mode is currently active.

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
/// fonts.gstatic.com on first launch — before the consent screen, and contrary
/// to PRIVACY.md. Same call shape as `GoogleFonts.manrope(...)`, no network.
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

class AppText {
  AppText._();

  static const _tnum = [FontFeature.tabularFigures()];

  // ── Display / numerics — Barlow Condensed: heavy, tight, tabular, kinetic ──
  // Bundled as a local asset (pubspec.yaml `flutter.fonts`), NOT fetched at
  // runtime via google_fonts — see the file header. `_barlow` is a thin
  // TextStyle helper standing in for GoogleFonts.barlowCondensed(...); same
  // call shape, zero network dependency.
  static TextStyle _barlow({
    required double fontSize,
    required FontWeight fontWeight,
    required double height,
    required double letterSpacing,
  }) => TextStyle(
    fontFamily: 'Barlow Condensed',
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
    color: AppColors.ink,
    fontFeatures: _tnum,
  );

  static TextStyle get hero => _barlow(
    fontSize: 68,
    fontWeight: FontWeight.w800,
    height: 0.96,
    letterSpacing: -0.4,
  );
  static TextStyle get display => _barlow(
    fontSize: 47,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -0.2,
  );
  static TextStyle get metric => _barlow(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -0.1,
  );
  static TextStyle get metricSm => _barlow(
    fontSize: 23,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
  );

  // ── Headings ──
  static TextStyle get h1 => _manrope(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -0.7,
    color: AppColors.ink,
  );
  static TextStyle get h2 => _manrope(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.35,
    color: AppColors.ink,
  );

  // ── Body / labels ──
  static TextStyle get title => _manrope(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
    color: AppColors.ink,
  );
  static TextStyle get body => _manrope(
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: AppColors.ink,
  );
  static TextStyle get bodySoft => _manrope(
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: AppColors.inkSoft,
  );
  static TextStyle get label => _manrope(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.inkSoft,
    letterSpacing: 0.1,
  );
  static TextStyle get caption => _manrope(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.inkSoft,
  );
  static TextStyle get captionMuted => _manrope(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.inkMuted,
  );
  static TextStyle get overline => _manrope(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.5,
    color: AppColors.inkMuted,
  );
}

/// Build the full theme from an explicit [Palette] so light/dark are each
/// self-consistent. Call with [kLightPalette] / [kDarkPalette].
ThemeData buildOpenStrapTheme(Palette p) {
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
