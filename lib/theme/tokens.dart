// Design tokens — WHOOP "Ember on Paper" (day) / "Ember on Char" (night).
// Day: warm off-white surfaces, near-black ink, a single confident coral accent.
// Night: the paper burns down to warm charcoal — same ember, never cold black.
// The accent stays coral across both modes; warmth is the constant, not lightness.
//
// Active screen typography is defined in ui2/theme.dart; these retained palettes
// do not select its font family or scale.
// The honesty system (confidence dots, est./relative/beta labels) is preserved.
//
// Mode switching: every mode-varying role lives on [Palette]; [AppColors] exposes
// the same names it always did, resolved through [AppColors.active]. The theme
// controller swaps `active` (synchronously) the instant the mode changes, so the
// 546 `AppColors.x` call sites keep working untouched and re-theme on rebuild.

import 'package:flutter/material.dart';

/// A complete set of mode-varying colour roles. Two const instances exist
/// ([kLightPalette], [kDarkPalette]); the active one is swapped at runtime.
@immutable
class Palette {
  final Brightness brightness;

  // Surfaces.
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceSunk;
  final Color cool;
  final Color coolInk;
  final Color divider;

  // Ink.
  final Color ink;
  final Color inkSoft;
  final Color inkMuted;

  // Accent — ember coral. Reserved for genuinely low/poor/urgent evaluative
  // states (including DomainAccent.heart's domain exception)
  // — never used for routine brand chrome; see `brand` below for that.
  final Color coral;
  final Color coralDeep;
  final Color coralSoft;
  final Color coralInk;

  // Brand identity — a calm, controlled cyan/teal, structurally separate
  // from `coral`. Powers nav active-state, routine/non-evaluative CTAs and
  // chrome (Material `primary`, FilledButton, AppColors.accent/accentSoft) —
  // deliberately never a "something needs attention" colour, so orange stays
  // legible as a genuine signal wherever it does appear.
  final Color brand;
  final Color brandDeep;
  final Color brandSoft;
  final Color brandInk;

  // Status.
  final Color good;
  final Color goodSoft;
  final Color warn;
  final Color warnSoft;
  final Color bad;
  final Color badSoft;

  // Confidence + load (independent tones; the rest derive from status).
  final Color confLow;
  final Color loadDetraining;

  const Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSunk,
    required this.cool,
    required this.coolInk,
    required this.divider,
    required this.ink,
    required this.inkSoft,
    required this.inkMuted,
    required this.coral,
    required this.coralDeep,
    required this.coralSoft,
    required this.coralInk,
    required this.brand,
    required this.brandDeep,
    required this.brandSoft,
    required this.brandInk,
    required this.good,
    required this.goodSoft,
    required this.warn,
    required this.warnSoft,
    required this.bad,
    required this.badSoft,
    required this.confLow,
    required this.loadDetraining,
  });

}

/// Day — "Ember on Paper". The original, beloved palette, unchanged in value.
const Palette kLightPalette = Palette(
  brightness: Brightness.light,
  bg: Color(0xFFF4F1EC), // warm paper background
  surface: Color(0xFFFFFFFF), // cards
  surfaceAlt: Color(0xFFECE7DF), // inset / skeleton base
  surfaceSunk: Color(0xFFEDE9E1), // subtle wells
  cool: Color(0xFFE7EBF5), // cool secondary section
  coolInk: Color(0xFF2B3350), // ink on the cool surface
  divider: Color(0xFFE6E0D6),
  ink: Color(0xFF16130F), // near-black, warm
  inkSoft: Color(0xFF6B6157), // secondary
  inkMuted: Color(0xFFA59C90), // tertiary / placeholders
  coral: Color(0xFFFF5A36),
  coralDeep: Color(0xFFE8431F),
  coralSoft: Color(0xFFFFE7DF), // tint fill
  coralInk: Color(0xFF7A2A16), // ink on coralSoft
  brand: Color(0xFF12879B), // controlled cyan/teal — calm, not orange
  brandDeep: Color(0xFF0C6C7D),
  brandSoft: Color(0xFFDCF2F4), // tint fill
  brandInk: Color(0xFF0A4650), // ink on brandSoft
  good: Color(0xFF2BB673),
  goodSoft: Color(0xFFDBF3E7),
  warn: Color(0xFFF5A623),
  warnSoft: Color(0xFFFBEBCF),
  bad: Color(0xFFE5484D),
  badSoft: Color(0xFFFAE0E0),
  confLow: Color(0xFFC9C0B4),
  loadDetraining: Color(0xFF7CA8F0),
);

/// Night — "Ember on Char". Warm charcoal, never cold black. Ink is the paper
/// colour; coral lifts ~8% so it reads cleanly on dark; the pale "*Soft" tints
/// become deep warm ember/earth fills so light ink sits on them comfortably.
const Palette kDarkPalette = Palette(
  brightness: Brightness.dark,
  bg: Color(0xFF14110D), // warm near-black char
  surface: Color(0xFF1E1A15), // cards, lifted off bg
  surfaceAlt: Color(0xFF2A251F), // inset / skeleton base
  surfaceSunk: Color(0xFF100E0A), // wells, darker than bg
  cool: Color(0xFF20242E), // cool secondary, darkened
  coolInk: Color(0xFFC3CADB), // ink on the cool surface
  divider: Color(0xFF302A22),
  ink: Color(0xFFF1ECE3), // warm off-white — the paper becomes the ink
  inkSoft: Color(0xFFB6AB9C),
  inkMuted: Color(0xFF7E7466),
  coral: Color(0xFFFF6B47), // a hair brighter on dark
  coralDeep: Color(0xFFFF8159), // "deep" = stronger/lighter coral on dark text
  coralSoft: Color(0xFF3A2018), // deep warm ember tint fill
  coralInk: Color(0xFFFFB59E), // light coral text on coralSoft
  brand: Color(0xFF3FD3E3), // a hair brighter on dark, same family as light
  brandDeep: Color(0xFF63E3EF),
  brandSoft: Color(0xFF102E32), // deep teal tint fill
  brandInk: Color(0xFFA6ECF2), // light cyan text on brandSoft
  good: Color(0xFF34C988),
  goodSoft: Color(0xFF15281F),
  warn: Color(0xFFF7B53A),
  warnSoft: Color(0xFF31280F),
  bad: Color(0xFFF26168),
  badSoft: Color(0xFF331A1B),
  confLow: Color(0xFF5A5248),
  loadDetraining: Color(0xFF8FB4F2),
);

/// Palette — warm paper + coral. Same public names as before; mode-varying roles
/// now resolve through [active], which the theme controller swaps at runtime.
abstract final class AppColors {

  /// The currently-rendered palette. Swapped (synchronously) by the theme
  /// controller before the tree rebuilds, so getters below always match the
  /// mode MaterialApp is painting.
  static Palette active = kLightPalette;


  // ── Surfaces (mode-varying) ──
  static Color get bg => active.bg;
  static Color get surface => active.surface;
  static Color get surfaceAlt => active.surfaceAlt;
  static Color get surfaceSunk => active.surfaceSunk;
  static Color get cool => active.cool;
  static Color get coolInk => active.coolInk;
  static Color get divider => active.divider;

  // ── Ink (mode-varying) ──
  static Color get ink => active.ink;
  static Color get inkSoft => active.inkSoft;
  static Color get inkMuted => active.inkMuted;

  // ── Dark hero surfaces — INVARIANT across modes (always-dark cards: the
  //    device card, the live-workout screen, splash overlays). ──
  static const night = Color(0xFF181613);
  static const nightAlt = Color(0xFF24211D);

  // ── Ink ramp for permanently-dark surfaces (the live session screen) ──
  //
  // These exist because that screen was written with ad-hoc `Colors.white30` /
  // `white38` values, and MEASURED against [nightAlt] they do not clear the
  // WCAG AA floor for small text (4.5:1):
  //
  //     white24 → 2.20:1     white30 → 2.72:1     white38 → 3.49:1
  //
  // Its labels are 9 px overlines, so that is squarely small text — the
  // "labels are invisible on the dark panel" report. Opacity is a convenient
  // knob but it is not a contrast decision; picking one requires knowing the
  // backdrop, which is exactly what a token can encode and a call site cannot.
  //
  // Ratios below are against [nightAlt] (the sheet); every one is higher
  // against the darker [night]. Guarded by test/zone_contrast_test.dart.

  /// Primary ink on a dark session surface — 14.23:1.
  static const onNight = Color(0xFFF4F1EC);

  // ── Accent — ember coral (mode-varying). Alert/urgent semantics ONLY —
  //    see `brand` below for the routine identity accent. ──
  static Color get coral => active.coral;
  static Color get coralDeep => active.coralDeep;
  static Color get coralSoft => active.coralSoft;
  static Color get coralInk => active.coralInk;

  // ── Brand identity — calm cyan/teal (mode-varying). Structurally separate
  //    from `coral`: this is what `accent`/`accentSoft` below resolve to. ──
  static Color get brand => active.brand;
  static Color get brandDeep => active.brandDeep;
  static Color get brandSoft => active.brandSoft;
  static Color get brandInk => active.brandInk;

  // ── Status (mode-varying) ──
  static Color get good => active.good;
  static Color get goodSoft => active.goodSoft;
  static Color get warn => active.warn;
  static Color get warnSoft => active.warnSoft;
  static Color get bad => active.bad;
  static Color get badSoft => active.badSoft;

  // ── Confidence dot ──
  static Color get confLow => active.confLow;

  // ── Load (ACWR) bands ──
  static Color get loadDetraining => active.loadDetraining;

  // ── HR zone palette (Z0..Z5) — the single source for zone colours. Reads the
  //    active palette at call time, so it re-themes for free. Both the live
  //    session ladder and the workouts zone bars source their colours here. ──
  static Color zone(int z) => zoneIn(active, z);

  /// The zone ramp resolved against a SPECIFIC palette rather than whatever is
  /// active. Needed because not every surface follows the app theme.
  static Color zoneIn(Palette p, int z) {
    switch (z.clamp(0, 5)) {
      case 0:
        return p.cool; // resting / below zone 1
      case 1:
        return p.loadDetraining; // warm-up
      case 2:
        return p.good; // fat burn
      case 3:
        return p.warn; // aerobic
      case 4:
        return p.coral; // threshold
      default:
        return p.coralDeep; // max effort (Z5)
    }
  }

  /// Zone colour for a surface that is ALWAYS dark, regardless of the user's
  /// theme — today that means the live workout session screen, which paints on
  /// [night]/[nightAlt] whether the app is in light or dark mode.
  ///
  /// Two separate legibility bugs are fixed here, both measured rather than
  /// eyeballed (WCAG relative-luminance contrast against [nightAlt]):
  ///
  ///  1. Plain [zone] resolves the ACTIVE palette. With the app in LIGHT mode
  ///     that returned hues tuned for contrast against white and painted them
  ///     on near-black.
  ///  2. Even on the dark palette, Z0 mapped to `cool` — which is a SURFACE
  ///     token (a dark cool-grey panel), not an ink. As a foreground it
  ///     measured **1.03:1** against nightAlt: literally invisible. And Z0 is
  ///     the resting zone, i.e. exactly what is on screen at the start of
  ///     every workout and whenever heart rate is low or absent.
  ///
  /// Z0 therefore uses `coolInk` — the token that already exists as "ink on
  /// the cool surface" — measuring 9.76:1. The rest of the ramp was already
  /// clear (5.7:1 – 8.9:1) and is unchanged.
  ///
  /// Guarded by a test that asserts every zone clears 3:1 on this surface, so
  /// a future palette edit cannot silently reintroduce an invisible zone.
  static Color zoneOnDark(int z) =>
      z.clamp(0, 5) == 0 ? kDarkPalette.coolInk : zoneIn(kDarkPalette, z);

  // ── Semantic aliases — the design-system vocabulary. One canonical name per
  //    role, resolved through [active] like everything else. New components
  //    (lib/ui/design/) speak these; the legacy names above keep working. ──

  /// Screen background (warm paper / deep char).
  static Color get background => active.bg;

  /// Primary content colour on any surface.
  static Color get onSurface => active.ink;

  /// THE brand accent — calm cyan/teal identity colour. Routine,
  /// non-evaluative CTAs/chrome and nav active-state ONLY: structurally
  /// separate from the alert semantics (`coral`/`warn`/`bad`) so a genuinely
  /// low/urgent state never has to compete with the brand hue for attention.
  /// See [DomainAccent] for per-health-domain colours (heart keeps the ember
  /// coral as its own domain identity, a deliberate, contained exception).
  static Color get accent => active.brand;

  /// Brand tint fill (chips, soft badges, nav lozenge); pair text with
  /// [onAccentSoft].
  static Color get accentSoft => active.brandSoft;
  static Color get onAccentSoft => active.brandInk;

  /// Status roles.
  static Color get positive => active.good;
  static Color get critical => active.bad;
  // (warn / warnSoft already exist above.)
}

/// Spacing — 4-pt grid.
abstract final class Sp {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const screen = 20.0; // generous side gutter
}

/// Radii — soft, generous (modern rounded cards).
abstract final class R {
  static const card = 28.0;
  static const cardSm = 20.0;
  static const chip = 14.0;
  static const pill = 999.0;
}

/// Motion.
abstract final class Motion {
  static const fast = Duration(milliseconds: 180);
  static const med = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 520);
  static const ring = Duration(milliseconds: 1000);
  static const curve = Curves.easeOutCubic;
  static const emphatic = Curves.easeOutQuint;

  // ── Motion semantics — (duration, curve) pairs naming *why* something moves.
  //    Use like `Motion.enter.d` / `Motion.enter.c`. ──

  /// Content settling into place (list items, cards revealing).
  static const ({Duration d, Curve c}) enter = (d: med, c: curve);

  /// A responsive, slightly-overshooting pop (press, badge, chip).
  static const ({Duration d, Curve c}) springy = (
    d: med,
    c: Curves.easeOutBack,
  );

  /// A drawn-out, celebratory reveal (count-ups, finish card, PR pops).
  static const ({Duration d, Curve c}) celebratory = (d: slow, c: emphatic);

  /// Direct-manipulation follow (scrub thumbs, drag handles, seg-control
  /// thumbs tracking a finger) — near-instant and linear so it never lags
  /// the gesture.
  static const ({Duration d, Curve c}) scrub = (
    d: Duration(milliseconds: 90),
    c: Curves.linear,
  );
}
