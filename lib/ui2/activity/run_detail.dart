// The run screen: an Apple Maps route, the headline numbers, best efforts
// against every earlier run, a plain verdict, splits, and pace / heart rate /
// elevation charts that share one finger cursor (which also moves a dot along
// the map). Everything is worked out from the recorded track; see
// lib/gps/run_analysis.dart for the rules.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../compute/profile.dart'
    show Profile, keytelActiveKcal, runFloorKcal;
import '../../gps/map_snapshot.dart';
import '../../gps/route_math.dart' show kMetersPerKm;
import '../../gps/run_analysis.dart';
import '../../gps/run_history.dart';
import '../../state/units_controller.dart';
import '../ui2.dart';
import 'summary.dart';

/// Everything the run screen draws, worked out once per session.
class RunView {
  final ActivityResult r;
  final List<PacePoint> pace;
  final Map<String, double> efforts;

  /// Seconds from the first fix to the last.
  final double spanSec;

  /// Seconds from the session's start to the first fix (the HR curve is
  /// indexed from the session start).
  final double leadSec;

  RunView._(this.r, this.pace, this.efforts, this.spanSec, this.leadSec,
      this.effortEnds);

  /// Track index where each shown best effort ended, for the map medals.
  final Map<String, int> effortEnds;

  factory RunView(ActivityResult r) {
    final t = r.track;
    final span = t.length < 2 ? 0.0 : (t.last.tsMs - t.first.tsMs) / 1000;
    final lead = t.isEmpty
        ? 0.0
        : math.max(0.0, (t.first.tsMs - r.start.millisecondsSinceEpoch) / 1000);
    final run = isRunType(r.activity.typeKey);
    return RunView._(r, paceCurve(t), run ? bestEfforts(t) : const {}, span,
        lead, run ? bestEffortEnds(t) : const {});
  }

  bool get isRun => isRunType(r.activity.typeKey);

  /// Moving pace, seconds per km.
  double? get movingPace {
    final km = r.distanceKm, mv = r.movingSec;
    return km == null || km <= 0 || mv == null || mv <= 0 ? null : mv / km;
  }

  /// The track point nearest [f] (0…1 of the span).
  int pointAt(double f) {
    final t = r.track;
    final target = t.first.tsMs + f * spanSec * 1000;
    var lo = 0, hi = t.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (t[mid].tsMs < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  PacePoint? paceAt(double f) {
    if (pace.isEmpty) return null;
    final ts = f * spanSec;
    var best = pace.first;
    for (final p in pace) {
      if ((p.tSec - ts).abs() < (best.tSec - ts).abs()) best = p;
    }
    return best;
  }

  double? hrAt(double f) {
    final i = ((leadSec + f * spanSec) / 60).floor();
    return i >= 0 && i < r.hr.length ? r.hr[i] : null;
  }

  /// [n] evenly spaced bins over the span, for the charts.
  List<double?> paceBins(int n) => [
        for (var k = 0; k < n; k++)
          switch (paceAt(k / (n - 1))?.paceSecPerKm) {
            final v? => -v, // negative so faster draws higher
            null => null,
          },
      ];

  List<double?> hrBins(int n) => [for (var k = 0; k < n; k++) hrAt(k / (n - 1))];

  /// The phone's steps a minute at [f], or null.
  double? cadenceAt(double f) {
    final c = r.cadenceSeries;
    final i = ((leadSec + f * spanSec) / 60).floor();
    return i >= 0 && i < c.length ? c[i] : null;
  }

  List<double?> cadenceBins(int n) =>
      [for (var k = 0; k < n; k++) cadenceAt(k / (n - 1))];

  List<double?> elevationBins(int n) {
    final t = r.track;
    if (t.any((p) => p.alt == null)) return const [];
    return [
      for (var k = 0; k < n; k++)
        () {
          final i = pointAt(k / (n - 1));
          var sum = 0.0, cnt = 0;
          for (var j = math.max(0, i - 7); j <= math.min(t.length - 1, i + 7); j++) {
            sum += t[j].alt!;
            cnt++;
          }
          return sum / cnt;
        }(),
    ];
  }
}

String pace(double? secPerKm) =>
    secPerKm == null ? '' : (UnitsController.formatPace(secPerKm) ?? '');

String _effortTime(double sec) => clock(sec.round());

// ══════════════════ MAP ══════════════════

/// The route on a dark Apple Maps picture, coloured slow (red) to fast
/// (green), with start and finish pins and a dot at the shared cursor. Falls
/// back to the plain route shape when there is no map (offline, not iOS).
/// One medal on the route: where an effort ended, its lifetime rank (1–3)
/// and its label, e.g. "Fastest 5K".
typedef RunMedal = ({int index, int rank, String label});

/// The medals for [v] against [earlier] runs: every shown distance whose best
/// effort here ranks in the top three of all time. Empty while history loads
/// or with no earlier run of that distance (a first effort is not a record).
List<RunMedal> runMedals(RunView v, List<RunSummary>? earlier) {
  if (earlier == null) return const [];
  final out = <RunMedal>[];
  for (final (label, _) in kBestEffortDistances) {
    final sec = v.efforts[label], at = v.effortEnds[label];
    if (sec == null || at == null) continue;
    final rank = effortRank(sec, [for (final e in earlier) ?e.efforts[label]]);
    if (rank == null) continue;
    out.add((
      index: at,
      rank: rank,
      label: switch (rank) {
        1 => 'Fastest $label',
        2 => '2nd best $label',
        _ => '3rd best $label',
      },
    ));
  }
  return out;
}

class RunMapCard extends StatelessWidget {
  const RunMapCard(this.v, {super.key, this.cursor, this.medals = const []});

  final RunView v;
  final double? cursor;

  /// Medal pins on the route, labelled "Fastest 5K" / "2nd best 1K".
  final List<RunMedal> medals;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = v.r;
    return ClipRRect(
      borderRadius: R.rLg,
      child: SizedBox(
        height: 230,
        child: LayoutBuilder(builder: (c, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final idx = thinnedIndex(r.track.length);
          return FutureBuilder<MapSnapshot?>(
            future: mapSnapshot(
              r.sessionId ?? '${r.start.millisecondsSinceEpoch}',
              [for (final pt in r.track) pt.lat],
              [for (final pt in r.track) pt.lng],
              w,
              h,
            ),
            builder: (c, snap) {
              final s = snap.data;
              final List<Offset> pts;
              final List<double>? paceFrac;
              if (s != null) {
                pts = [for (var k = 0; k < s.x.length; k++) Offset(s.x[k], s.y[k])];
                paceFrac = r.routePace == null
                    ? null
                    : [for (final i in idx) r.routePace![i]];
              } else {
                pts = r.route;
                paceFrac = r.routePace;
              }
              // A track index → its place on whichever picture is drawn.
              Offset? place(int i) {
                if (pts.isEmpty) return null;
                if (s != null) {
                  var k = 0;
                  while (k + 1 < idx.length && idx[k + 1] <= i) {
                    k++;
                  }
                  return pts[k];
                }
                return i < pts.length ? pts[i] : null;
              }

              final dot = cursor == null ? null : place(v.pointAt(cursor!));
              // The fallback shape is inset 8% by the painter; match it.
              final pad = s == null ? 0.08 : 0.0;
              Offset onCard(Offset o) => Offset(
                  (pad + o.dx * (1 - 2 * pad)) * w,
                  (pad + o.dy * (1 - 2 * pad)) * h);
              return Stack(children: [
                Positioned.fill(
                  child: s == null
                      ? ColoredBox(color: p.card2)
                      : Image.memory(s.png, fit: BoxFit.fill, gaplessPlayback: true),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TrackPainter(
                      pts,
                      paceFrac,
                      slow: p.on(C.red),
                      fast: p.on(C.green),
                      plain: p.on(C.run),
                      ink: p.ink,
                      halo: p.bg,
                      dot: dot,
                      inset: s == null,
                    ),
                  ),
                ),
                for (var m = 0; m < medals.length; m++)
                  if (place(medals[m].index) case final o?)
                    _medal(c, p, onCard(o), medals[m], w, m),
              ]);
            },
          );
        }),
      ),
    );
  }
}

/// A medal pin with its label beside it (to the left near the right edge),
/// nudged down a line for each earlier medal so stacked labels stay readable.
Widget _medal(BuildContext c, P p, Offset at, RunMedal m, double w, int nth) {
  final col = switch (m.rank) {
    1 => C.yellow,
    2 => C.n400,
    _ => C.orange,
  };
  final leftSide = at.dx > w * .6;
  final pin = Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: p.on(col),
      shape: BoxShape.circle,
      border: Border.all(color: p.bg, width: 2),
    ),
    child: Text('${m.rank}', style: F.over.copyWith(color: p.bg)),
  );
  final label = Container(
    padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: 2),
    decoration: BoxDecoration(
        color: p.bg.withValues(alpha: .82), borderRadius: R.rSm),
    child: Text(m.label, style: F.over.copyWith(color: p.ink)),
  );
  final dy = nth * 22.0;
  return Positioned(
    left: leftSide ? null : at.dx - 10,
    right: leftSide ? w - at.dx - 10 : null,
    top: at.dy - 10 + dy,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: leftSide
          ? [label, const SizedBox(width: S.x1), pin]
          : [pin, const SizedBox(width: S.x1), label],
    ),
  );
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.pts, this.pace,
      {required this.slow,
      required this.fast,
      required this.plain,
      required this.ink,
      required this.halo,
      this.dot,
      this.inset = false});

  final List<Offset> pts;
  final List<double>? pace;
  final Color slow, fast, plain, ink, halo;
  final Offset? dot;

  /// The fallback shape has no margins of its own; give it some.
  final bool inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    final pad = inset ? 0.08 : 0.0;
    Offset at(Offset o) => Offset(
        (pad + o.dx * (1 - 2 * pad)) * size.width,
        (pad + o.dy * (1 - 2 * pad)) * size.height);
    final under = Paint()
      ..color = halo
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(at(pts.first).dx, at(pts.first).dy);
    for (final o in pts.skip(1)) {
      path.lineTo(at(o).dx, at(o).dy);
    }
    canvas.drawPath(path, under);
    final line = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < pts.length; i++) {
      final f = pace == null || i >= pace!.length ? null : pace![i];
      line.color = f == null ? plain : Color.lerp(slow, fast, f)!;
      canvas.drawLine(at(pts[i - 1]), at(pts[i]), line);
    }
    void pin(Offset o, Color col) {
      canvas.drawCircle(at(o), 7, Paint()..color = halo);
      canvas.drawCircle(at(o), 5, Paint()..color = col);
    }

    pin(pts.first, fast);
    pin(pts.last, slow);
    if (dot != null) {
      canvas.drawCircle(at(dot!), 9, Paint()..color = halo);
      canvas.drawCircle(at(dot!), 6, Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter o) =>
      o.pts != pts || o.dot != dot || o.pace != pace;
}

// ══════════════════ HEADLINE NUMBERS ══════════════════

class RunStatsGrid extends StatelessWidget {
  const RunStatsGrid(this.v, {super.key});
  final RunView v;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = v.r;
    final cells = <(String, String)>[
      if (r.distanceKm != null) ('Distance', '${r.distanceKm!.toStringAsFixed(2)} km'),
      if (v.movingPace != null) ('Avg pace', '${pace(v.movingPace)} /km'),
      if (r.movingSec != null) ('Moving time', clock(r.movingSec!)),
      ('Elapsed', hms(r.duration)),
      if (r.avgHr != null) ('Avg HR', '${r.avgHr} bpm'),
      if (r.maxHr != null) ('Max HR', '${r.maxHr} bpm'),
      if ((r.phoneSteps ?? r.stepsCounted) != null)
        ('Steps', grouped((r.phoneSteps ?? r.stepsCounted)!)),
      if (r.cadence != null) ('Cadence', '${r.cadence!.round()} spm'),
      if (r.gainM != null) ('Elevation gain', '${r.gainM!.round()} m'),
      if (r.strain != null) ('Strain', r.strain!.toStringAsFixed(1)),
    ];
    final cols = bigText(c) ? 2 : 3;
    return Surface(
      child: Column(children: [
        for (var row = 0; row * cols < cells.length; row++) ...[
          if (row > 0) const SizedBox(height: S.x4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var k = row * cols; k < row * cols + cols; k++)
              Expanded(
                child: k >= cells.length
                    ? const SizedBox.shrink()
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(cells[k].$1, style: F.over.copyWith(color: p.ink3)),
                        const SizedBox(height: 2),
                        Text(cells[k].$2,
                            style: F.n17.copyWith(color: p.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ]),
              ),
          ]),
        ],
      ]),
    );
  }
}

// ══════════════════ CALORIES ══════════════════

/// The two calorie numbers for a run or walk.
///
/// * From distance (Method 1): the least the distance costs at the user's
///   weight, running metres at 0.143, walk-break metres at 0.1, plus the
///   climb. This is the one maintenance counts for a run.
/// * From heart rate (Method 2, Keytel): what the heart rate says was burned
///   above resting, minute by minute.
///
/// Within 50 kcal of each other they are one number; further apart both are
/// shown, because the gap is itself the reading (an inefficient or hot run
/// burns above the floor).
({double? floor, ({double kcal, int measured, int slots})? hr}) runCalories(
    ActivityResult r, Profile? p) {
  final mix = r.mix;
  final floor = mix == null
      ? null
      : runFloorKcal(
          runMeters: mix.runM,
          walkMeters: mix.walkM,
          climbMeters: mix.climbM,
          weightKg: p?.weightKg);
  final hr = p == null || r.hr.isEmpty
      ? null
      : keytelActiveKcal(r.hr, r.duration.inSeconds / 60, p);
  return (floor: floor, hr: hr);
}

/// How far apart the two numbers may be and still read as one.
const double kCalorieAgree = 50;

class RunCaloriesCard extends StatelessWidget {
  const RunCaloriesCard(this.r, this.profile, {super.key});

  final ActivityResult r;
  final Profile? profile;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final cal = runCalories(r, profile);
    final floor = cal.floor, hr = cal.hr;
    final isRun = isRunType(r.activity.typeKey);
    final mix = r.mix;
    if (floor == null && hr == null) {
      return Surface(
        child: Row(children: [
          Icon(LucideIcons.flame, size: 18, color: p.ink3),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(
                'Calories need your age, height and weight in Settings → Profile.',
                style: F.cap.copyWith(color: p.ink2)),
          ),
        ]),
      );
    }
    final kg = profile?.weightKg;
    final kgText = kg == null
        ? ''
        : ' at ${kg == kg.roundToDouble() ? kg.round() : kg.toStringAsFixed(1)} kg';
    final agree = floor != null &&
        hr != null &&
        (hr.kcal - floor).abs() <= kCalorieAgree;
    final hrMin = hr == null
        ? ''
        : '${(r.duration.inSeconds / 60 * hr.measured / hr.slots).round()} of '
            '${(r.duration.inSeconds / 60).round()} min';

    Widget row(String name, double kcal, String sub) => Padding(
          padding: const EdgeInsets.only(top: S.x3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: F.body.copyWith(color: p.ink)),
                Text(sub, style: F.cap.copyWith(color: p.ink3)),
              ]),
            ),
            const SizedBox(width: S.x3),
            Text('${grouped(kcal)} kcal', style: F.n17.copyWith(color: p.ink)),
          ]),
        );

    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Calories', style: F.over.copyWith(color: p.ink3)),
        if (agree) ...[
          const SizedBox(height: S.x1),
          Wrap(spacing: S.x2, crossAxisAlignment: WrapCrossAlignment.end, children: [
            Text(grouped(floor), style: F.n34.copyWith(color: p.ink)),
            Padding(
              padding: const EdgeInsets.only(bottom: S.x1),
              child: Text('kcal', style: F.cap.copyWith(color: p.ink3)),
            ),
          ]),
          Text('Distance and heart rate agree within 50 kcal.',
              style: F.cap.copyWith(color: p.ink3)),
        ] else ...[
          if (floor != null)
            row('From distance', floor, 'The least this distance costs$kgText'),
          if (hr != null) row('From heart rate', hr.kcal, 'Your heart rate over $hrMin'),
        ],
        if (mix != null && mix.walkM >= 50 && mix.runM >= 50) ...[
          const SizedBox(height: S.x3),
          Text(
              'Running ${(mix.runM / 1000).toStringAsFixed(2)} km · walking '
              '${(mix.walkM / 1000).toStringAsFixed(2)} km',
              style: F.cap.copyWith(color: p.ink2)),
        ],
        const SizedBox(height: S.x2),
        Text(
            isRun
                ? 'Maintenance counts the distance number.'
                : 'Maintenance counts this walk in your steps.',
            style: F.over.copyWith(color: p.ink3)),
      ]),
    );
  }
}

// ══════════════════ BEST EFFORTS ══════════════════

/// This run's best efforts ranked against every earlier run.
class BestEffortsCard extends StatelessWidget {
  const BestEffortsCard(this.v, this.earlier, {super.key});

  final RunView v;

  /// Earlier runs (before this one), or null while they load.
  final List<RunSummary>? earlier;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final rows = <Widget>[];
    for (final (label, _) in kBestEffortDistances) {
      final sec = v.efforts[label];
      if (sec == null) continue;
      final past = [
        for (final e in earlier ?? const <RunSummary>[])
          ?e.efforts[label],
      ];
      final rank = earlier == null ? null : effortRank(sec, past);
      final prev = previousBest(past);
      final (String tag, Color col) = switch (rank) {
        1 => ('PR', C.yellow),
        2 => ('2nd best', C.n500),
        3 => ('3rd best', C.n500),
        _ => ('', C.n500),
      };
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x2),
        child: Row(children: [
          Expanded(
            flex: 2,
            child: Text(label, style: F.body.copyWith(color: p.ink))),
          Expanded(
            flex: 3,
            child: Text(
                '${_effortTime(sec)} · ${pace(sec / (kBestEffortDistances.firstWhere((d) => d.$1 == label).$2 / kMetersPerKm))} /km',
                style: F.cap.copyWith(color: p.ink2)),
          ),
          if (tag.isNotEmpty)
            Text(
                rank == 1 && prev != null
                    ? '$tag · ${_effortTime(prev - sec)} faster'
                    : tag,
                style: F.cap.copyWith(
                    color: rank == 1 ? p.on(col) : p.ink3,
                    fontWeight: FontWeight.w600)),
        ]),
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Section('Best efforts', Surface(child: Column(children: rows)));
  }
}

// ══════════════════ VERDICT ══════════════════

class RunVerdictCard extends StatelessWidget {
  const RunVerdictCard(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(LucideIcons.sparkles, size: 18, color: p.on(C.run)),
        const SizedBox(width: S.x3),
        Expanded(child: Text(text, style: F.body.copyWith(color: p.ink))),
      ]),
    );
  }
}

// ══════════════════ SPLITS ══════════════════

class RunSplitsCard extends StatelessWidget {
  const RunSplitsCard(this.r, {super.key});
  final ActivityResult r;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final rows = [
      for (final s in r.splits)
        if (s.km > 0) (s.km, s.sec / s.km, s.avgHr),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final fastest = rows.map((x) => x.$2).reduce(math.min);
    final slowest = rows.map((x) => x.$2).reduce(math.max);
    return Surface(
      child: Column(children: [
        Row(children: [
          SizedBox(width: 36, child: Text('KM', style: F.over.copyWith(color: p.ink3))),
          SizedBox(width: 56, child: Text('PACE', style: F.over.copyWith(color: p.ink3))),
          const Spacer(),
          Text('HR', style: F.over.copyWith(color: p.ink3)),
        ]),
        const SizedBox(height: S.x2),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x2),
            child: Row(children: [
              SizedBox(
                  width: 36,
                  child: Text(
                      rows[i].$1 >= 0.99 ? '${i + 1}' : rows[i].$1.toStringAsFixed(1),
                      style: F.cap.copyWith(color: p.ink2))),
              SizedBox(
                  width: 56,
                  child: Text(pace(rows[i].$2),
                      style: F.body.copyWith(
                          color: rows[i].$2 == fastest ? p.on(C.run) : p.ink,
                          fontWeight: FontWeight.w600))),
              Expanded(
                child: ClipRRect(
                  borderRadius: R.rPill,
                  child: SizedBox(
                    height: 8,
                    child: Stack(children: [
                      Positioned.fill(child: ColoredBox(color: p.track)),
                      FractionallySizedBox(
                        // Faster is longer, scaled so the slowest still shows.
                        widthFactor: slowest == fastest
                            ? 1.0
                            : (0.35 + 0.65 * (slowest - rows[i].$2) / (slowest - fastest))
                                .clamp(0.0, 1.0),
                        child: ColoredBox(
                            color: p.on(C.run), child: const SizedBox.expand()),
                      ),
                    ]),
                  ),
                ),
              ),
              SizedBox(
                  width: 44,
                  child: Text(rows[i].$3 == null ? '' : '${rows[i].$3}',
                      textAlign: TextAlign.right,
                      style: F.cap.copyWith(color: p.ink2))),
            ]),
          ),
      ]),
    );
  }
}

// ══════════════════ LINKED CHARTS ══════════════════

/// Pace, heart rate and elevation over the run, under one finger: drag across
/// any of them and all three, plus the map dot, follow.
class RunCharts extends StatelessWidget {
  const RunCharts(this.v, {super.key, required this.cursor, required this.onCursor});

  final RunView v;
  final double? cursor;
  final ValueChanged<double> onCursor;

  static const _bins = 160;

  String _describe(double f) {
    final i = v.pointAt(f);
    final meters = v.pace.isEmpty ? null : v.paceAt(f)?.meters;
    final pc = v.paceAt(f)?.paceSecPerKm;
    final hr = v.hrAt(f);
    final cad = v.cadenceAt(f);
    final alt = v.r.track[i].alt;
    return [
      if (meters != null) '${(meters / 1000).toStringAsFixed(2)} km',
      pc == null ? 'stopped' : '${pace(pc)} /km',
      if (hr != null) '${hr.round()} bpm',
      if (cad != null) '${cad.round()} spm',
      if (alt != null) '${alt.round()} m',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final paceV = v.paceBins(_bins);
    final hrV = v.hrBins(_bins);
    final elV = v.elevationBins(_bins);
    final cadV = v.cadenceBins(_bins);
    Widget chart(String title, String unit, List<double?> d, Color col,
        String Function(double) fmt) {
      final vals = [for (final x in d) ?x];
      final axis = AxisSpec.of(vals, ticks: 3, format: fmt);
      if (axis == null || vals.length < 2) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: S.x4),
        child: ChartFrame(
          title: title,
          unit: unit,
          height: 96,
          yAxis: axis,
          series: d,
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                painter: LineChart(d, col, axis: axis, t: animate(c, 1)),
              ),
            ),
            if (cursor != null)
              Align(
                alignment: Alignment(cursor! * 2 - 1, 0),
                child: SizedBox(
                    width: 1.5,
                    height: double.infinity,
                    child: ColoredBox(color: p.ink)),
              ),
          ]),
        ),
      );
    }

    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(cursor == null ? 'Touch and drag to read any moment' : _describe(cursor!),
            style: cursor == null
                ? F.cap.copyWith(color: p.ink3)
                : F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
        const SizedBox(height: S.x3),
        Scrubber(
          value: cursor,
          onChanged: onCursor,
          label: 'Pace, heart rate and elevation through the run',
          describe: _describe,
          step: 1 / 100,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            chart('Pace', '/km', paceV, p.on(C.run), (x) => pace(-x)),
            chart('Heart rate', 'bpm', hrV, p.on(C.heart), axisInt),
            // From the phone, a minute at a time. Around 160+ a minute is the
            // usual running-economy cue.
            chart('Cadence', 'steps/min', cadV, p.on(C.steps), axisInt),
            chart('Elevation', 'm', elV, p.on(C.teal), axisInt),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Start', style: F.over.copyWith(color: p.ink3)),
          Text(clock(v.spanSec.round()), style: F.over.copyWith(color: p.ink3)),
        ]),
      ]),
    );
  }
}

// ══════════════════ PACE ZONES ══════════════════

class PaceZonesCard extends StatelessWidget {
  const PaceZonesCard(this.shares, this.fiveKPace, {super.key});

  final List<double> shares;
  final double fiveKPace;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final bounds = paceZoneBounds(fiveKPace);
    String range(int z) {
      final (fast, slow) = bounds[z];
      if (fast == null) return '> ${pace(slow)}';
      if (slow == null) return '< ${pace(fast)}';
      return '${pace(fast)}–${pace(slow)}';
    }

    return Section(
      'Pace zones',
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Based on your predicted 5K pace of ${pace(fiveKPace)} /km',
              style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(height: S.x3),
          for (var z = 5; z >= 0; z--)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(kPaceZoneNames[z],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.cap.copyWith(color: p.ink2)),
                  ),
                  Text(range(z), style: F.over.copyWith(color: p.ink3)),
                  const SizedBox(width: S.x3),
                  Text('${(shares[z] * 100).round()}%',
                      style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: S.x1),
                ClipRRect(
                  borderRadius: R.rPill,
                  child: SizedBox(
                    height: 8,
                    child: Stack(children: [
                      Positioned.fill(child: ColoredBox(color: p.track)),
                      FractionallySizedBox(
                        widthFactor: shares[z].clamp(0.0, 1.0),
                        child: ColoredBox(
                            color: p.on(C.run),
                            child: const SizedBox.expand()),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
