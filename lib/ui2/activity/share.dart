// Share — activity-aware, because a share card with the map taken out is not
// a strength card, it is a broken run card.
//
// Every template draws the archetype's OWN defining object as its texture and
// its own headline as the hero, and the stat chips offer only the stats this
// session actually has. Nothing on the card is invented: if a session has no
// distance, "Distance" is not offered, so it cannot be shared.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/units_controller.dart';
import '../charts.dart';
import '../grammar.dart';
import '../paint_activity.dart';
import '../screens/home_screen.dart' show unitsOf;
import '../theme.dart';
import 'catalogue.dart';
import 'summary.dart';

/// The rect an iPad or Mac share popover points at.
///
/// `UIActivityViewController` is a popover on those, and `share_plus` throws
/// rather than guessing when it is given no anchor — which is how every iPad
/// share in this app failed silently. Any `share_plus` call from a widget
/// should pass this.
Rect shareOrigin(BuildContext c) {
  final box = c.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  return box.localToGlobal(Offset.zero) & box.size;
}

class ShareSheet extends StatefulWidget {
  final ActivityResult result;
  const ShareSheet(this.result, {super.key});

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  /// The textured card when this session has one, the plain card when it does
  /// not — never an index into an option that is not offered.
  late int style = _styles.length - 1;
  late final Set<String> chosen = {
    for (final s in _available(widget.result).take(4)) s.$1,
  };

  /// The card, as pixels. Sharing a picture of it means capturing the thing on
  /// screen rather than re-drawing a second, slightly different one.
  final _card = GlobalKey();
  bool _sharing = false;

  ActivityResult get r => widget.result;
  Arch get arch => r.arch;

  Future<void> _share() async {
    if (_sharing) return;
    _sharing = true;
    // Both read the tree, so both are read before the first await.
    final origin = shareOrigin(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary =
          _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      await Share.shareXFiles(
        [
          XFile.fromData(png.buffer.asUint8List(),
              mimeType: 'image/png', name: '${r.activity.typeKey}.png'),
        ],
        sharePositionOrigin: origin,
      );
    } catch (e) {
      // A share that quietly does nothing is worse than one that says it
      // failed: this swallowed every iPad share for the life of the screen.
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not open the share sheet.')));
      }
      debugPrint('share failed: $e');
    } finally {
      _sharing = false;
    }
  }

  /// The card has exactly two looks — with the archetype's own texture behind
  /// the numbers, and without — and index 1 is the one with it. The other two
  /// names on each of these lists were labels for a card identical to
  /// 'Minimal': a 'Photo' style on a screen that cannot attach a photo, a
  /// 'Splits' style that drew the same lap bars as 'Lanes'. A choice that
  /// changes nothing is not a choice.
  List<(String, IconData)> get _styles => [
    ('Minimal', LucideIcons.type),
    // Only when there is something to draw. `_art` falls back to nothing when
    // the session has no route, no sets, no rounds — which made the option an
    // invisible no-op rather than an absence.
    if (_hasArt(r))
      switch (arch) {
        Arch.route => ('Route', LucideIcons.map),
        Arch.strength => ('Muscle map', LucideIcons.personStanding),
        Arch.journey => ('Elevation', LucideIcons.mountain),
        Arch.flow => ('Calm', LucideIcons.leaf),
        Arch.laps => ('Lanes', LucideIcons.waves),
        Arch.interval => ('Rounds', LucideIcons.timer),
        Arch.match || Arch.basic => ('Heart rate', LucideIcons.activity),
      },
  ];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final stats = _available(r, unitsOf(c));
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: const NavBar('Share'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x8),
                children: [
                  Center(
                    child: RepaintBoundary(
                      key: _card,
                      child: ShareCard(r, style, chosen),
                    ),
                  ),
                  const SizedBox(height: S.x6),
                  Text('CHOOSE A STYLE', style: F.over.copyWith(color: p.ink3)),
                  const SizedBox(height: S.x3),
                  Surface(
                    pad: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: Column(
                      children: [
                        for (var i = 0; i < _styles.length; i++) ...[
                          Pressable(
                            onTap: () => setState(() => style = i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: S.x3,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _styles[i].$2,
                                    size: 17,
                                    color: style == i
                                        ? p.on(r.activity.color)
                                        : p.ink3,
                                  ),
                                  const SizedBox(width: S.x3),
                                  Expanded(
                                    child: Text(
                                      _styles[i].$1,
                                      style: F.body.copyWith(
                                        color: p.ink,
                                        fontWeight: style == i
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    style == i
                                        ? LucideIcons.circleCheck
                                        : LucideIcons.circle,
                                    size: 19,
                                    color: style == i
                                        ? p.on(r.activity.color)
                                        : p.line,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (i < _styles.length - 1)
                            Divider(color: p.line, height: 1),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x5),
                  Text('INCLUDE', style: F.over.copyWith(color: p.ink3)),
                  const SizedBox(height: S.x3),
                  if (stats.isEmpty)
                    const StatusCard(
                      'Nothing measured to include',
                      'No heart rate, distance or calories.',
                      icon: LucideIcons.circleHelp,
                    )
                  else
                    Wrap(
                      spacing: S.x2,
                      runSpacing: S.x2,
                      children: [
                        for (final s in stats)
                          Pressable(
                            semanticLabel: '${s.$1} ${s.$2}',
                            onTap: () => setState(
                              () => chosen.contains(s.$1)
                                  ? chosen.remove(s.$1)
                                  : chosen.add(s.$1),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: S.x3,
                                vertical: S.x2,
                              ),
                              constraints: const BoxConstraints(
                                minHeight: S.tap,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: chosen.contains(s.$1)
                                    ? p.wash(r.activity.color)
                                    : p.card2,
                                borderRadius: R.rPill,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    chosen.contains(s.$1)
                                        ? LucideIcons.check
                                        : LucideIcons.plus,
                                    size: 13,
                                    color: chosen.contains(s.$1)
                                        ? p.on(r.activity.color)
                                        : p.ink3,
                                  ),
                                  const SizedBox(width: S.x1),
                                  Text(
                                    s.$1,
                                    style: F.cap.copyWith(
                                      color: chosen.contains(s.$1)
                                          ? p.on(r.activity.color)
                                          : p.ink2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: S.x6),
                  // One button, and it is the system share sheet — which is
                  // where "story", "message" and "save" actually live. The
                  // four destination tiles that used to sit here were four
                  // integrations this app does not have.
                  BigButton(
                    'Share',
                    icon: LucideIcons.share2,
                    color: r.activity.color,
                    onTap: _share,
                  ),
                  if (r.private) ...[
                    const SizedBox(height: S.x4),
                    const StatusCard(
                      'This session is private',
                      'Hidden from summaries and exports.',
                      icon: LucideIcons.lock,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Whether [ShareCard._art] has anything to draw for this session. Kept beside
/// `_available` because it answers the same question about the texture that
/// that list answers about the numbers, and it must stay in step with `_art`.
/// The session's average pace in the reader's unit, or null when there is no
/// pace worth printing — the stat is then not offered at all rather than
/// offered with a placeholder in it.
String? _paceOf(ActivityResult r, UnitsController? u) {
  final secPerKm = r.paceSecPerKm;
  if (secPerKm == null) return null;
  final perUnit = u == null ? 1.0 : u.distanceUnitMeters / 1000;
  return UnitsController.formatPace(secPerKm * perUnit);
}

bool _hasArt(ActivityResult r) => switch (r.arch) {
  Arch.route => r.route.length >= 2,
  Arch.strength => muscleLoad(r.strength.volumeByExercise).isNotEmpty,
  Arch.journey => r.elevationM.length >= 2,
  Arch.laps => r.lapSpeeds.isNotEmpty,
  Arch.interval => r.rounds.isNotEmpty,
  // The breath ring is drawn, not measured, so a flow session always has one.
  Arch.flow => true,
  Arch.match || Arch.basic => r.hr.length >= 2,
};

/// The stats this session can honestly put on a card, in offer order.
///
/// [u] is the reader's unit system, null in a golden (and at the one call site
/// that only reads the stat NAMES, which no unit system changes) — metric is
/// what the store holds, so that is what a card without one shows.
List<(String, String)> _available(ActivityResult r, [UnitsController? u]) => [
  ('Time', hms(r.duration)),
  if (r.distanceKm != null)
    (
      'Distance',
      u == null
          ? '${r.distanceKm!.toStringAsFixed(2)} km'
          : u.distance(r.distanceKm! * 1000)!,
    ),
  if (_paceOf(r, u) != null)
    ('Pace', '${_paceOf(r, u)} /${u?.distanceUnit ?? 'km'}'),
  if (r.avgHr != null) ('Heart rate', '${r.avgHr} bpm'),
  // With its unit. A bare "612" on a card is a number nobody can read back.
  if (r.calories != null) ('Calories', '${grouped(r.calories!)} kcal'),
  if (r.gainM != null) ('Elevation', '+${r.gainM!.round()} m'),
  if (r.strength.volumeKg != null)
    ('Volume', '${grouped(r.strength.volumeKg!)} kg'),
  if (!r.strength.isEmpty) ('Sets', '${r.strength.setCount}'),
  if (r.lapCount != null) ('Laps', '${r.lapCount}'),
];

/// The card. The visual metaphor changes; type and spacing do not.
class ShareCard extends StatelessWidget {
  final ActivityResult r;
  final int style;
  final Set<String> chosen;
  const ShareCard(this.r, this.style, this.chosen, {super.key});

  Arch get arch => r.arch;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final accent = _accent();
    // Derived from the accent rather than hand-picked hex, so a palette change
    // moves the cards with it and every card is dark enough for white ink.
    final bg = [
      Color.lerp(C.n900, accent, .10)!,
      Color.lerp(C.n900, accent, .38)!,
    ];
    final hero = _hero(unitsOf(c));
    // The card is a PICTURE — a fixed-aspect graphic that gets exported at one
    // size, not a piece of UI. So it does not inherit the reader's text scale:
    // at 2× the same 240×320 box would overflow, and the exported image would
    // be clipped for everyone who received it. Everything AROUND the card in
    // this sheet still scales.
    return MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
        width: 240,
        height: 320,
        decoration: BoxDecoration(
          borderRadius: R.rXl,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: bg,
          ),
          boxShadow: p.el(3),
        ),
        child: ClipRRect(
          borderRadius: R.rXl,
          child: Stack(
            children: [
              if (style == 1) Positioned.fill(child: _art(accent)),
              Padding(
                padding: const EdgeInsets.all(S.x5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label().toUpperCase(),
                      style: F.over.copyWith(color: _ink(.72)),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            hero.$1,
                            style: F.n34.copyWith(color: C.white),
                            maxLines: 1,
                          ),
                        ),
                        if (hero.$2.isNotEmpty) ...[
                          const SizedBox(width: S.x1),
                          Text(hero.$2, style: F.cap.copyWith(color: _ink(.8))),
                        ],
                      ],
                    ),
                    Text(
                      hero.$3,
                      style: F.cap.copyWith(color: _ink(.72)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: S.x4),
                    Wrap(
                      spacing: S.x4,
                      runSpacing: S.x2,
                      children: [
                        for (final s in _available(r, unitsOf(c))
                            .where((s) => chosen.contains(s.$1))
                            .take(4))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.$2,
                                style: F.head.copyWith(color: C.white),
                              ),
                              Text(
                                s.$1.toUpperCase(),
                                style: F.over.copyWith(color: _ink(.6)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _ink(double a) => C.white.withValues(alpha: a);

  Color _accent() => switch (arch) {
    Arch.route => C.green,
    Arch.strength => C.purple,
    Arch.interval => C.red,
    Arch.flow => C.teal,
    Arch.laps => C.blue,
    Arch.journey => C.green,
    Arch.match => C.indigo,
    Arch.basic => r.activity.color,
  };

  String _label() => switch (arch) {
    Arch.route => r.activity.name,
    Arch.strength => 'Strength',
    Arch.interval => 'Intervals',
    Arch.flow => r.activity.name,
    Arch.laps => 'Swim',
    Arch.journey => r.activity.name,
    Arch.match || Arch.basic => r.activity.name,
  };

  (String, String, String) _hero(UnitsController? u) {
    final fallback = (hms(r.duration), '', r.activity.name);
    final km = r.distanceKm;
    return switch (arch) {
      Arch.route || Arch.journey =>
        km == null
            ? fallback
            : (
                (u == null ? km : u.distanceValue(km * 1000))
                    .toStringAsFixed(2),
                u?.distanceUnit ?? 'km',
                r.gainM == null
                    ? r.activity.name
                    : '+${r.gainM!.round()} m elevation',
              ),
      Arch.strength =>
        r.strength.volumeKg == null
            ? fallback
            : (grouped(r.strength.volumeKg!), 'kg', 'Total volume'),
      Arch.laps =>
        r.swimMetres == null
            ? fallback
            : (grouped(r.swimMetres!), 'm', '${r.lapCount} laps'),
      Arch.interval || Arch.flow || Arch.match || Arch.basic => fallback,
    };
  }

  /// The texture is the archetype's real defining object drawn from the real
  /// data. Nothing to draw → nothing drawn.
  Widget _art(Color accent) {
    switch (arch) {
      case Arch.route:
        if (r.route.length < 2) return const SizedBox.shrink();
        return CustomPaint(
          painter: RouteMap(
            r.route,
            pace: r.routePace,
            slow: _ink(.55),
            fast: C.white,
            pins: false,
          ),
        );
      case Arch.strength:
        final load = muscleLoad(r.strength.volumeByExercise);
        if (load.isEmpty) return const SizedBox.shrink();
        return Opacity(
          opacity: .30,
          child: CustomPaint(painter: MuscleMap(load, C.white, _ink(.10))),
        );
      case Arch.journey:
        if (r.elevationM.length < 2) return const SizedBox.shrink();
        return Opacity(
          opacity: .55,
          child: CustomPaint(
            painter: Elevation(r.elevationM, C.white, markerInk: accent),
          ),
        );
      case Arch.laps:
        if (r.lapSpeeds.isEmpty) return const SizedBox.shrink();
        return Opacity(
          opacity: .40,
          child: CustomPaint(painter: LapBars(r.lapSpeeds, C.white, _ink(.12))),
        );
      case Arch.interval:
        if (r.rounds.isEmpty) return const SizedBox.shrink();
        final peak = r.rounds
            .map((x) => x.workSec > x.restSec ? x.workSec : x.restSec)
            .reduce((x, y) => x > y ? x : y)
            .toDouble();
        return Opacity(
          opacity: .45,
          child: CustomPaint(
            painter: IntervalLadder(
              [
                for (final x in r.rounds)
                  (work: x.workSec / peak, rest: x.restSec / peak),
              ],
              C.white,
              _ink(.45),
            ),
          ),
        );
      case Arch.flow:
        return Center(
          child: CustomPaint(
            size: const Size(200, 200),
            painter: BreathRing(.8, _ink(.35)),
          ),
        );
      // A match and an untracked session share one honest texture: the heart
      // rate they actually recorded. (The court map this used to draw needed
      // indoor positioning, which nothing here has.)
      case Arch.match || Arch.basic:
        if (r.hr.length < 2) return const SizedBox.shrink();
        return Opacity(
          opacity: .5,
          child: CustomPaint(painter: LineChart(r.hr, C.white)),
        );
    }
  }
}
