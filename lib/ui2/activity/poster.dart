// The poster — the share card for a session that actually went somewhere.
//
// The other styles draw the route as a line in a box, which is a shape. This
// one draws it on a real basemap, so the shape becomes a place: the streets
// you ran, at the scale you ran them. That is the whole difference, and it is
// only offered when the session has real coordinates behind it.
//
// Three rules this card is built around.
//
//   1. NOTHING ON IT IS INVENTED. Every posted running card in the world shows
//      cadence, elevation and weather; this stack measures none of the three
//      for a gen4 band from stored data, so none of the three is here. The
//      chips are the same `_available` list the other styles offer — the ones
//      the session genuinely has.
//   2. The photo is the USER'S. It is not fetched, not generated, not a stock
//      backdrop chosen by activity type. If they do not add one, the card is
//      the accent gradient and says nothing about where they were.
//   3. The map is credited. `kOsmAttribution` is on the card, not in a
//      settings screen — see the licence note in tiles.dart.
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

/// 4:5 — the aspect every feed and story crops least badly.
const kPosterW = 300.0;
const kPosterH = 375.0;

/// How much of the card the photo (or the gradient standing in for it) owns.
const _photoFrac = .46;

/// The map box, in card units. Fixed rather than derived from the leftover
/// space so the tile fetch can ask for the right aspect ratio up front — and
/// [PosterRoute] covers rather than stretches if layout disagrees anyway.
const kPosterMapW = kPosterW - S.x4 * 2;
const kPosterMapH = 112.0;

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

  const PosterCard(this.r, this.chosen,
      {super.key, this.photo, this.mosaic});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final u = unitsOf(c);
    final accent = r.activity.color;
    final stats = [
      for (final s in posterStats(r, u))
        if (chosen.contains(s.$1)) s,
    ].take(3).toList();
    final hero = posterHero(r, u);

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
          child: Column(
            children: [
              SizedBox(
                height: kPosterH * _photoFrac,
                child: _head(p, accent, hero),
              ),
              Expanded(child: _foot(p, accent, stats)),
            ],
          ),
        ),
      ),
    );
  }

  /// Photo (or gradient), scrim, label, and the one big number.
  Widget _head(P p, Color accent, (String, String, String) hero) => Stack(
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
          // picture. Without it the card is a coin toss: a bright sky and the
          // distance disappears.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  C.n900.withValues(alpha: photo == null ? .10 : .45),
                  C.n900.withValues(alpha: photo == null ? .35 : .88),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(S.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(r.activity.icon, size: 14, color: C.white),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: Text(r.activity.name.toUpperCase(),
                        style: F.over.copyWith(color: C.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (r.private)
                    const Icon(LucideIcons.lock, size: 12, color: C.white),
                ]),
                const Spacer(),
                // scaleDown, not ellipsis. This is a fixed-size PICTURE, so a
                // long value has nowhere to wrap to — and a truncated distance
                // ("12.4…") on a card somebody else receives is worse than the
                // same distance a few points smaller. Never scales UP: a short
                // value keeps the type scale the rest of the card is set in.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(hero.$1,
                          style: F.n48.copyWith(color: C.white, height: 1),
                          maxLines: 1),
                      if (hero.$2.isNotEmpty) ...[
                        const SizedBox(width: S.x2),
                        Text(hero.$2,
                            style: F.body.copyWith(
                                color: C.white.withValues(alpha: .85))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(hero.$3,
                    style: F.cap
                        .copyWith(color: C.white.withValues(alpha: .70)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      );

  /// Chips, then the map, then the credit line.
  Widget _foot(P p, Color accent, List<(String, String)> stats) => ColoredBox(
        color: C.n900,
        child: Column(
          children: [
            if (stats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(S.x5, S.x4, S.x5, S.x3),
                child: Row(
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0)
                        Container(
                            width: 1,
                            height: 26,
                            color: C.white.withValues(alpha: .14)),
                      Expanded(
                        child: Column(children: [
                          // Same rule as the hero: a long value shrinks rather
                          // than truncating. '1:02:14' and '2,310 kcal' are
                          // both real and are not the same width.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(stats[i].$2,
                                style: F.head.copyWith(color: C.white),
                                maxLines: 1),
                          ),
                          const SizedBox(height: 1),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(stats[i].$1.toUpperCase(),
                                style: F.over.copyWith(
                                    color: C.white.withValues(alpha: .60)),
                                maxLines: 1,
                                textAlign: TextAlign.center),
                          ),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    S.x4, stats.isEmpty ? S.x4 : 0, S.x4, S.x2),
                child: ClipRRect(
                  borderRadius: R.rLg,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Color.lerp(C.n900, C.white, .06)!),
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
                      // The credit rides ON the map, because the map is what
                      // it credits and the two must never be separable by a
                      // crop.
                      Positioned(
                        left: S.x2,
                        bottom: S.x1,
                        child: Text(
                          mosaic == null ? '' : kOsmAttribution,
                          style: F.over.copyWith(
                              color: C.white.withValues(alpha: .55)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x5, 0, S.x5, S.x3),
              child: Row(children: [
                Expanded(
                  child: Text('OpenStrap',
                      style: F.over
                          .copyWith(color: C.white.withValues(alpha: .55)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: S.x3),
                // The stamp is the longest string on the card relative to its
                // slot — '13 AUG 2026 · 18:20' in a face wider than the one it
                // was measured in overflowed this row by 62 pt. It shrinks to
                // fit rather than pushing the wordmark off the card.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(posterDate(r.start),
                        style: F.over.copyWith(
                            color: C.white.withValues(alpha: .55)),
                        maxLines: 1),
                  ),
                ),
              ]),
            ),
          ],
        ),
      );
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
      // same way the plain card does.
      const pad = .1;
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
        ..strokeWidth = 5.5
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
        core.color =
            Color.lerp(line, C.white, ((ramp[i] + ramp[i - 1]) / 2).clamp(0, 1))!;
        canvas.drawLine(pts[i - 1], pts[i], core);
      }
    } else {
      canvas.drawPath(path, core..color = line);
    }

    for (final (o, col) in [(pts.first, start), (pts.last, end)]) {
      canvas.drawCircle(o, 4, Paint()..color = C.white);
      canvas.drawCircle(o, 2.6, Paint()..color = col);
    }
  }

  @override
  bool shouldRepaint(covariant PosterRoute o) =>
      o.mosaic != mosaic || o.fallback != fallback || o.line != line;
}

/// `20 MAY 2026 · 07:15`.
String posterDate(DateTime t) {
  const m = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.day} ${m[t.month - 1]} ${t.year} · ${two(t.hour)}:${two(t.minute)}';
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
