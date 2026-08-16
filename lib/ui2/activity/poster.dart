// The poster — the share card for a session that actually went somewhere.
//
// The other styles draw the route as a line in a box, which is a shape. This
// one draws it on a real basemap, so the shape becomes a place: the streets
// you ran, at the scale you ran them. That is the whole difference, and it is
// only offered when the session has real coordinates behind it.
//
// The composition is a full-bleed photo with everything else in a left column
// over it: wordmark, activity, the one big number, the stats as a vertical
// list, the map, the stamp. A column reads top-to-bottom in one pass; the
// horizontal stat strip this replaced made three numbers compete for the same
// glance and gave the map the whole bottom of the card for a shape you can
// read in a third of it.
//
// Three rules this card is built around.
//
//   1. NOTHING ON IT IS INVENTED. Every posted running card in the world shows
//      cadence, elevation and weather; this stack measures none of the three
//      for a gen4 band from stored data, so none of the three is here. The
//      rows are the same `shareStats` list the other styles offer — the ones
//      the session genuinely has.
//   2. The photo is the USER'S. It is not fetched, not generated, not a stock
//      backdrop chosen by activity type. If they do not add one, the card is
//      the accent gradient and says nothing about where they were.
//   3. The map is credited. `kOsmAttribution` is drawn ON the map, and only
//      when there are tiles under it — see the licence note in tiles.dart.
//
// Like `ShareCard`, this is a PICTURE at a fixed size and does not inherit the
// reader's text scale: it is exported at one resolution and sent to someone
// else's phone, and a 2× card would export clipped for every recipient.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/units_controller.dart';
import '../screens/home_screen.dart' show unitsOf;
import '../theme.dart';
import 'share.dart' show shareHero, shareStats;
import 'summary.dart';
import 'tiles.dart';

/// 3:4 — the aspect every feed and story crops least badly.
const kPosterW = 300.0;
const kPosterH = 400.0;

/// The left column owns half the card. The rest is photo, and the scrim that
/// makes the column legible over it fades out before it gets there.
const _colFrac = .5;
const kPosterColW = kPosterW * _colFrac;

const _padL = S.x5;
const _padR = S.x3;

/// The map box, in card units. Fixed rather than derived from the leftover
/// space so the tile fetch can ask for the right aspect ratio up front — and
/// [PosterRoute] covers rather than stretches if layout disagrees anyway.
const kPosterMapW = kPosterColW - _padL - _padR;
const kPosterMapH = 52.0;

/// The hero's slot. Fixed so the column's arithmetic is fixed: the number
/// inside scales down to fit rather than pushing the map off the card.
const _heroH = 44.0;

/// How many rows the column can hold without the map losing its place. This is
/// a CEILING, not a pad — a session with two stats prints two.
///
/// Four, because four is what `ShareSheet` pre-selects and what a run actually
/// has: time, pace, calories, heart rate. At three the fourth was dropped
/// silently, which is the one behaviour this card is not allowed to have.
const _maxRows = 4;

class PosterCard extends StatelessWidget {
  final ActivityResult r;

  /// The stat names to print, from the same offer list the other styles use.
  final Set<String> chosen;

  /// The user's own picture, or null for the gradient.
  final ImageProvider? photo;

  /// The basemap, already fetched and projected. Null while it is loading, or
  /// forever if there was no network — the card then draws the route on the
  /// card's own surface instead of on streets. A plainer picture, never a
  /// half-loaded one.
  final RouteMosaic? mosaic;

  const PosterCard(this.r, this.chosen, {super.key, this.photo, this.mosaic});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final u = unitsOf(c);
    final accent = r.activity.color;
    final stats = [
      for (final s in posterStats(r, u))
        if (chosen.contains(s.$1)) s,
    ].take(_maxRows).toList();

    return MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
        width: kPosterW,
        height: kPosterH,
        decoration: BoxDecoration(
          borderRadius: R.rXl,
          color: C.n900,
          boxShadow: p.el(3),
        ),
        child: ClipRRect(
          borderRadius: R.rXl,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo != null)
                Image(image: photo!, fit: BoxFit.cover)
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(C.n900, accent, .18)!,
                        Color.lerp(C.n900, accent, .52)!,
                      ],
                    ),
                  ),
                ),
              // The scrim is what makes white type legible over an unknown
              // picture. Without it the card is a coin toss: a bright sky and
              // the distance disappears. It runs sideways rather than down
              // because the type does — near-opaque under the column, gone by
              // the time it reaches the part of the photo worth showing.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    // Held nearly flat across the column, then dropped: a
                    // straight ramp to zero at 65% leaves only .21 alpha under
                    // the last third of the type, and a bright photo eats the
                    // labels there.
                    stops: const [0, .40, .74, 1],
                    colors: [
                      C.n900.withValues(alpha: photo == null ? .82 : .94),
                      C.n900.withValues(alpha: photo == null ? .62 : .80),
                      C.n900.withValues(alpha: 0),
                      C.n900.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              // A slight vignette, so the card has edges of its own whatever
              // the photo does at the top and bottom of the frame.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .45, 1],
                    colors: [
                      C.n900.withValues(alpha: .35),
                      C.n900.withValues(alpha: 0),
                      C.n900.withValues(alpha: .45),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: kPosterColW,
                child: _column(accent, stats, posterHero(r, u)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _column(
    Color accent,
    List<(String, String)> stats,
    (String, String, String) hero,
  ) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(_padL, S.x4, _padR, S.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _wordmark(accent),
            const SizedBox(height: S.x4),
            _activity(accent),
            const SizedBox(height: S.x2),
            _hero(hero),
            const SizedBox(height: S.x3),
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) _divider(),
              PosterStatRow(
                icon: posterStatIcon(stats[i].$1),
                label: stats[i].$1,
                value: splitStatUnit(stats[i].$2).$1,
                unit: splitStatUnit(stats[i].$2).$2,
                accent: accent,
                ink: C.white,
              ),
            ],
            // The slack lives here, so the map and the stamp stay pinned to
            // the bottom whether the session printed three rows or none.
            const Spacer(),
            _map(accent),
            const SizedBox(height: S.x2),
            _stamp(accent),
          ],
        ),
      );

  Widget _wordmark(Color accent) => Row(children: [
        Container(
          width: S.x5,
          height: S.x5,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: accent, borderRadius: R.rSm),
          child: const Icon(LucideIcons.activity, size: 12, color: C.white),
        ),
        const SizedBox(width: S.x2),
        // scaleDown, like everything else in this column: the name of the app
        // is the one string on the card that may never be truncated, and a
        // face wider than the one this was measured in is not a reason to
        // print 'OpenStr…'.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('OpenStrap',
                style: F.over
                    .copyWith(color: C.white, fontWeight: FontWeight.w700),
                maxLines: 1),
          ),
        ),
      ]);

  Widget _activity(Color accent) => Row(children: [
        Icon(r.activity.icon, size: 13, color: accent),
        const SizedBox(width: S.x2),
        Flexible(
          child: Text(r.activity.name.toUpperCase(),
              style: F.over.copyWith(color: accent, letterSpacing: 1.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        if (r.private) ...[
          const SizedBox(width: S.x1),
          Icon(LucideIcons.lock, size: 11, color: accent),
        ],
      ]);

  /// The one big number. scaleDown, not ellipsis — this is a fixed-size
  /// PICTURE, so a long value has nowhere to wrap to, and a truncated distance
  /// ('12.4…') on a card somebody else receives is worse than the same
  /// distance a few points smaller.
  Widget _hero((String, String, String) hero) => SizedBox(
        height: _heroH,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(hero.$1,
                  style: F.n48.copyWith(color: C.white), maxLines: 1),
              if (hero.$2.isNotEmpty) ...[
                const SizedBox(width: S.x2),
                Text(hero.$2,
                    style: F.cap
                        .copyWith(color: C.white.withValues(alpha: .70))),
              ],
            ],
          ),
        ),
      );

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x2),
        child: SizedBox(
          width: double.infinity,
          height: 1,
          child: ColoredBox(color: C.white.withValues(alpha: .10)),
        ),
      );

  Widget _map(Color accent) => SizedBox(
        width: kPosterMapW,
        height: kPosterMapH,
        child: ClipRRect(
          borderRadius: R.rMd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Color.lerp(C.n900, C.white, .10)!),
              CustomPaint(
                painter: PosterRoute(
                  mosaic: mosaic,
                  fallback: r.route,
                  pace: r.routePace,
                  line: accent,
                  casing: C.n900,
                  start: C.green,
                  end: C.red,
                ),
              ),
              // The credit rides ON the map, because the map is what it
              // credits and the two must never be separable by a crop — and it
              // is absent when there are no tiles, because crediting
              // OpenStreetMap for a map that is not on the card would be its
              // own small lie.
              if (mosaic != null)
                Positioned(
                  left: S.x1,
                  right: S.x1,
                  bottom: 1,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(kOsmAttribution,
                        style: F.over.copyWith(
                            color: C.white.withValues(alpha: .80),
                            letterSpacing: 0)),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _stamp(Color accent) => Row(children: [
        Icon(LucideIcons.calendar, size: 11, color: accent),
        const SizedBox(width: S.x2),
        // The longest string on the card relative to its slot — it shrinks to
        // fit rather than pushing itself off the column.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(posterDate(r.start),
                style: F.over.copyWith(color: C.white, letterSpacing: 0),
                maxLines: 1),
          ),
        ),
      ]);
}

/// One measured thing: a ringed icon, its name, and the number.
///
/// Public and poster-free on purpose — the workout screens print the same
/// three-part row, and two widgets drawing one grammar is how the last design
/// system ended up with four stat rows that disagreed about their own spacing.
///
/// [ink] is the ink to set the value in; null takes the page's own, so the row
/// works on a card as well as on a photo. The label and the unit are derived
/// from it rather than passed, so a caller cannot half-theme the row.
class PosterStatRow extends StatelessWidget {
  final IconData icon;

  /// Printed in caps. Pass it in sentence case.
  final String label;

  final String value;

  /// Trails the value, smaller and muted. Null for a bare count.
  final String? unit;

  final Color accent;

  /// The value's ink. Null resolves to the page's — see the class note.
  final Color? ink;

  const PosterStatRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.unit,
    this.ink,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final on = ink ?? p.ink;
    final muted = ink == null ? p.ink3 : ink!.withValues(alpha: .62);
    return Row(children: [
      Container(
        width: S.x6,
        height: S.x6,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent.withValues(alpha: .55)),
        ),
        child: Icon(icon, size: 12, color: accent),
      ),
      const SizedBox(width: S.x3),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: F.over.copyWith(color: muted, letterSpacing: 1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            // scaleDown rather than ellipsis, for the same reason the hero
            // uses it: '2,310 kcal' and '52 bpm' are both real and are not the
            // same width, and a truncated number is not a number.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: F.n17.copyWith(color: on), maxLines: 1),
                  if (unit != null) ...[
                    const SizedBox(width: S.x1),
                    Text(unit!, style: F.cap.copyWith(color: muted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

/// Split a formatted stat into its number and its unit.
///
/// `shareStats` hands back one string because that is what a chip prints. A
/// row sets the two halves differently, so it has to take them apart — and it
/// only does so when the tail actually LOOKS like a unit. '1h 02m' is a
/// duration whose last word is not a unit of anything, and splitting it would
/// print '1h' in the value slot.
(String, String?) splitStatUnit(String s) {
  final m = RegExp(r'^(.+?)\s+([a-zA-Z/][a-zA-Z/]*)$').firstMatch(s.trim());
  return m == null ? (s, null) : (m.group(1)!, m.group(2)!);
}

/// The glyph for a stat name, from the same offer list `shareStats` returns.
/// Anything unrecognised gets the neutral mark rather than a guess.
IconData posterStatIcon(String name) => switch (name) {
      'Time' => LucideIcons.timer,
      'Distance' => LucideIcons.ruler,
      'Pace' => LucideIcons.gauge,
      'Heart rate' => LucideIcons.heart,
      'Calories' => LucideIcons.flame,
      'Elevation' => LucideIcons.mountain,
      'Volume' => LucideIcons.dumbbell,
      'Sets' => LucideIcons.layers,
      'Laps' => LucideIcons.repeat,
      _ => LucideIcons.activity,
    };

/// Fast → slow, as a four-stop ramp. [t] is the 0…1 speed a fix was carrying,
/// 1 being the fastest of the session — so green is where you were moving and
/// red is where you were not.
Color paceColor(double t) {
  const ramp = [C.red, C.orange, C.yellow, C.green];
  final x = t.clamp(0.0, 1.0) * (ramp.length - 1);
  final i = x.floor().clamp(0, ramp.length - 2);
  return Color.lerp(ramp[i], ramp[i + 1], x - i)!;
}

/// The route, on the basemap when there is one and on bare card when there is
/// not.
///
/// Two passes for the line — a dark casing under a coloured core — because a
/// single stroke over an arbitrary photo or an arbitrary map tile is legible
/// against some of them and invisible against the rest.
class PosterRoute extends CustomPainter {
  final RouteMosaic? mosaic;

  /// The 0…1 normalised route, used only when [mosaic] is null.
  final List<Offset> fallback;

  /// Per-point 0…1 speed, for the ramp. Null when the fixes carried no speed.
  final List<double>? pace;

  final Color line, casing, start, end;

  PosterRoute({
    required this.mosaic,
    required this.fallback,
    required this.pace,
    required this.line,
    required this.casing,
    required this.start,
    required this.end,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    List<Offset> pts;
    final m = mosaic;
    if (m != null) {
      // COVER, not stretch. The mosaic is fetched at one size and the box it
      // lands in is decided by layout, so the two will not always agree — and
      // a basemap scaled unevenly is a map of somewhere that does not exist.
      // One uniform scale, centred, cropping the overhang; the route is
      // transformed identically so it stays on its own streets.
      final k = math.max(size.width / m.width, size.height / m.height);
      final ox = (size.width - m.width * k) / 2;
      final oy = (size.height - m.height * k) / 2;
      canvas.save();
      canvas.translate(ox, oy);
      canvas.scale(k, k);
      canvas.drawImage(m.image, Offset.zero, Paint()..isAntiAlias = true);
      canvas.restore();
      pts = [for (final o in m.path) Offset(ox + o.dx * k, oy + o.dy * k)];
    } else {
      // No basemap: fit the normalised shape into the box with a margin, the
      // same way the plain card does. Room at the top for the pins, which
      // stand ABOVE the point they mark.
      const pad = .12;
      final s = size.shortestSide * (1 - pad * 2);
      final ox = (size.width - s) / 2, oy = (size.height - s) / 2;
      pts = [for (final o in fallback) Offset(ox + o.dx * s, oy + o.dy * s)];
    }
    if (pts.length < 2) return;
    for (final o in pts) {
      if (o.dx.isNaN || o.dy.isNaN) return;
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = casing.withValues(alpha: .55)
        ..isAntiAlias = true,
    );

    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final ramp = pace;
    if (ramp != null && ramp.length == pts.length) {
      // Segment by segment, so the colour is the speed you were doing there.
      for (var i = 1; i < pts.length; i++) {
        core.color = paceColor((ramp[i] + ramp[i - 1]) / 2);
        canvas.drawLine(pts[i - 1], pts[i], core);
      }
    } else {
      canvas.drawPath(path, core..color = line);
    }

    _pin(canvas, pts.first, start);
    _pin(canvas, pts.last, end);
  }

  /// A map pin, not a dot: the head sits above the fix and the tip is on it,
  /// so the mark points at the place rather than covering it.
  void _pin(Canvas canvas, Offset o, Color col) {
    const rad = 3.6, tall = 11.0;
    final head = Offset(o.dx, o.dy - tall + rad);
    final path = Path()
      ..addOval(Rect.fromCircle(center: head, radius: rad))
      ..moveTo(o.dx - rad * .72, head.dy + rad * .70)
      ..lineTo(o.dx, o.dy)
      ..lineTo(o.dx + rad * .72, head.dy + rad * .70)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = C.white
        ..isAntiAlias = true,
    );
    canvas.drawPath(path, Paint()..color = col..isAntiAlias = true);
    canvas.drawCircle(head, 1.4, Paint()..color = C.white);
  }

  @override
  bool shouldRepaint(covariant PosterRoute o) =>
      o.mosaic != mosaic || o.fallback != fallback || o.line != line;
}

/// `20 May 2026 • 7:15 AM`, in the reader's own clock terms.
String posterDate(DateTime t) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final min = t.minute.toString().padLeft(2, '0');
  return '${m[t.month - 1]} ${t.day}, ${t.year} • $h:$min '
      '${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Hero, unit, caption — distance when the session has one, time when it does
/// not. Shared with `ShareCard`'s own hero so the two styles cannot disagree
/// about the same session.
(String, String, String) posterHero(ActivityResult r, UnitsController? u) =>
    shareHero(r, u);

/// The stats a poster may print, in offer order. Same source as every other
/// style: if the session did not measure it, it is not on the list.
List<(String, String)> posterStats(ActivityResult r, UnitsController? u) =>
    shareStats(r, u);
