// The chart painters.
//
// Two rules run through this file and neither is negotiable.
//
// 1. NOTHING IN HERE INVENTS DATA. The prototype these are ported from seeded
//    a `Random` inside several painters so the design could be seen without a
//    band attached. That is exactly the failure mode the honesty contract
//    exists to prevent, so every painter now takes the series it draws. A
//    painter given an empty series draws nothing and the screen shows a
//    `StatusCard` — it never draws a plausible-looking line.
//
// 2. A CHART WITHOUT AN AXIS IS A SHAPE. Every painter that maps a value to a
//    height takes an optional [AxisSpec]. Given one it uses exactly that
//    mapping — no padding, no auto-extent — so the gridlines and tick labels
//    `ChartFrame` prints are the same scale the curve was drawn against, and
//    two charts side by side are comparable. Without one it falls back to
//    auto-scaling its own min/max, which is fine for a sparkline and a lie
//    anywhere a number is being read off the picture.
//
// 3. EVERY PAINTER THAT CAN RECEIVE A LONG SERIES DOWNSAMPLES. A night of
//    1 Hz data is ~30 000 points on a ~350 pt wide chart. The old UI handed
//    all 30 000 to `Path`, which is ~85 segments per physical pixel: invisible
//    work, visible jank. [minMaxColumns] reduces to at most two points per
//    horizontal pixel — the column's minimum and maximum, in time order — so
//    the drawn envelope is pixel-identical to the full series and every spike
//    survives. Naive stride decimation would drop them.

import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Reduce [d] to at most two points per horizontal pixel: the minimum and the
/// maximum inside each column, emitted in the order they occur so the polyline
/// never travels backwards in time.
///
/// [width] is the paint width in logical pixels. [y] maps a sample value to a
/// canvas y. Series short enough to be drawn honestly (≤ 2 samples per column)
/// come back untouched.
///
/// This is the shared implementation — anything in lib/ui2 that turns a
/// `List<double>` into a path goes through it.
List<Offset> minMaxColumns(
  List<double> d,
  double width,
  double Function(double value) y,
) {
  final n = d.length;
  if (n == 0 || width <= 0) return const [];
  if (n == 1) return [Offset(0, y(d[0]))];

  double x(int i) => i / (n - 1) * width;

  final cols = width.floor().clamp(1, n);
  if (n <= cols * 2) {
    return [for (var i = 0; i < n; i++) Offset(x(i), y(d[i]))];
  }

  final out = <Offset>[];
  for (var c = 0; c < cols; c++) {
    final lo = (c * n / cols).floor();
    final hi = ((c + 1) * n / cols).ceil().clamp(lo + 1, n);
    var loI = lo, hiI = lo;
    for (var i = lo + 1; i < hi; i++) {
      if (d[i] < d[loI]) loI = i;
      if (d[i] > d[hiI]) hiI = i;
    }
    final first = loI < hiI ? loI : hiI;
    final second = loI < hiI ? hiI : loI;
    out.add(Offset(x(first), y(d[first])));
    if (second != first) out.add(Offset(x(second), y(d[second])));
  }
  return out;
}

/// Column maxima only — for bar charts, where a column is one bar and the
/// minimum is the baseline. Same contract as [minMaxColumns].
List<double> maxColumns(List<double> d, int cols) {
  final n = d.length;
  if (n == 0 || cols <= 0 || n <= cols) return d;
  return [
    for (var c = 0; c < cols; c++)
      d
          .sublist((c * n / cols).floor(),
              ((c + 1) * n / cols).ceil().clamp((c * n / cols).floor() + 1, n))
          .reduce(max),
  ];
}

/// ── THE Y AXIS ────────────────────────────────────────────────────────────
///
/// One object, shared by the painter that draws the curve and the [ChartFrame]
/// that prints the numbers beside it. Passing it to only one of the two is the
/// bug it exists to prevent.
///
/// [format] is what makes a duration axis print `7h 30m` and a heart-rate axis
/// print `56` without either of them needing a special painter — see [axisInt],
/// [axisHm] and [axisFixed] for the three that cover almost everything.
class AxisSpec {
  final double min, max;

  /// Gridline count, INCLUDING both ends. 3 → min, midpoint, max.
  final int ticks;

  final String Function(double) format;

  const AxisSpec({
    required this.min,
    required this.max,
    this.ticks = 3,
    required this.format,
  });

  /// Where [v] sits on the axis: 0 at [min], 1 at [max]. Clamped, so a sample
  /// outside the axis lands on the edge instead of off the canvas — the axis
  /// the user is reading stays the axis that was drawn.
  double t(double v) =>
      max - min <= 0 ? 0 : ((v - min) / (max - min)).clamp(0.0, 1.0);

  /// Tick values top-first, so the list is in the order the labels are stacked.
  List<double> get tickValues {
    final n = ticks < 2 ? 2 : ticks;
    return [for (var i = 0; i < n; i++) max - (max - min) * i / (n - 1)];
  }

  /// An axis over real data, rounded out to a step a human would choose —
  /// 0/25/50, not 3.7/28.4/53.1. Returns null for an empty series, which is the
  /// signal to render [ChartFrame]'s empty state rather than an empty axis.
  ///
  /// This is here so that three screens plotting the same metric cannot each
  /// invent a slightly different scale.
  static AxisSpec? of(
    Iterable<double> d, {
    int ticks = 3,
    String Function(double) format = axisInt,
    double? floor,
    double? ceil,
    double? step,
  }) {
    final v = d.toList();
    if (v.isEmpty) return null;
    final n = ticks < 2 ? 2 : ticks;
    // NB: `min`/`max` are fields on this class, so dart:math's are shadowed
    // here — reduce explicitly rather than silently passing a double.
    var lo = v.reduce((a, b) => a < b ? a : b),
        hi = v.reduce((a, b) => a > b ? a : b);
    // [floor] / [ceil] EXTEND the axis to include a meaningful anchor — pass
    // `floor: 0` for anything where zero is the real baseline. They never crop
    // the data.
    if (floor != null && floor < lo) lo = floor;
    if (ceil != null && ceil > hi) hi = ceil;
    if (hi - lo < 1e-9) {
      // A flat series still needs a readable band around it, or the line sits
      // on the floor of the chart and reads as "lowest it has ever been".
      final pad = hi.abs() < 1e-9 ? 1.0 : hi.abs() * .1;
      lo -= pad;
      hi += pad;
    }
    // [step] overrides the rounding for axes whose "nice" numbers are not
    // powers of ten: minutes want 60/120/240, not 250. The rest of the maths
    // is identical, so an override cannot produce uneven ticks.
    final s = step != null && step > 0
        ? step
        : _niceStep((hi - lo) / (n - 1));
    final base = (lo / s).floorToDouble() * s;
    var top = base + s * (n - 1);
    while (top < hi - 1e-9) {
      top += s;
    }
    return AxisSpec(
        min: base,
        // Re-derive so the ticks stay evenly spaced after any growth above.
        max: base + ((top - base) / s).round() * s,
        ticks: n,
        format: format);
  }

  /// 1 · 2 · 2.5 · 5 · 10 × a power of ten — the steps that produce labels
  /// people read without thinking.
  static double _niceStep(double raw) {
    if (raw <= 0 || !raw.isFinite) return 1;
    final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 2.5, 5.0]) {
      if (raw <= m * mag) return m * mag;
    }
    return 10 * mag;
  }

  @override
  bool operator ==(Object other) =>
      other is AxisSpec &&
      other.min == min &&
      other.max == max &&
      other.ticks == ticks &&
      other.format == format;

  @override
  int get hashCode => Object.hash(min, max, ticks, format);
}

/// `56`, `-3`. The default.
String axisInt(double v) => v.round().toString();

/// `7h 30m`, `45m`, `8h` — for an axis measured in MINUTES.
String axisHm(double minutes) {
  final t = minutes.round(), h = t ~/ 60, m = t % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// One decimal — skin temperature, kilograms, pace.
String axisFixed(double v) => v.toStringAsFixed(1);

/// Smoothing is only honest below this many points. Above it the polyline is
/// already sub-pixel and a cubic through min/max pairs invents overshoot that
/// is not in the data.
const _kSmoothMax = 120;

({double min, double range}) _extent(List<double> d) {
  final mx = d.reduce(max), mn = d.reduce(min);
  return (min: mn, range: (mx - mn).abs() < 1e-6 ? 1.0 : mx - mn);
}

/// The trend line. Sparkline in a row, hero curve in a card.
///
/// [t] is a 0…1 draw-in progress — pass `animate(context, t)` so reduced
/// motion lands on a fully drawn chart instead of a partial one.
class LineChart extends CustomPainter {
  final List<double> d;
  final Color color;
  final bool fill, dots;
  final double t;

  /// [dotInk] is the knockout at the centre of the head dot; pass the surface
  /// the chart sits on. Defaults to nothing, which draws a solid dot.
  final Color? dotInk;

  /// The shared scale. Given one, the curve is drawn edge to edge against
  /// exactly the axis the frame labels — no 14% breathing room, because a
  /// gridline that says 60 has to be where 60 is. Without one the chart
  /// auto-scales, which is correct for a sparkline and nothing else.
  final AxisSpec? axis;

  LineChart(this.d, this.color,
      {this.fill = true,
      this.dots = false,
      this.t = 1,
      this.dotInk,
      this.axis});

  @override
  void paint(Canvas cv, Size s) {
    if (d.length < 2 || s.width <= 0) return;
    final a = axis;
    final pad = s.height * .14;
    final e = a == null ? _extent(d) : null;
    double y(double v) => a != null
        ? s.height - a.t(v) * s.height
        : s.height - pad - (v - e!.min) / e.range * (s.height - pad * 2);

    final all = minMaxColumns(d, s.width, y);
    final n = (all.length * t.clamp(0, 1)).round().clamp(2, all.length);
    final pts = all.sublist(0, n);

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (d.length <= _kSmoothMax) {
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1], b = pts[i], m = (a.dx + b.dx) / 2;
        path.cubicTo(m, a.dy, m, b.dy, b.dx, b.dy);
      }
    } else {
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    }

    if (fill) {
      final f = Path.from(path)
        ..lineTo(pts.last.dx, s.height)
        ..lineTo(0, s.height)
        ..close();
      cv.drawPath(
        f,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: .24), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & s),
      );
    }
    cv.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    if (dots) {
      cv.drawCircle(pts.last, 4.5, Paint()..color = color);
      // The prototype knocked this out in hard white, which is a hole in a
      // dark card. It knocks out the surface it is drawn on.
      if (dotInk != null) cv.drawCircle(pts.last, 2, Paint()..color = dotInk!);
    }
  }

  @override
  bool shouldRepaint(covariant LineChart o) =>
      o.d != d || o.t != t || o.color != color || o.axis != axis;
}

/// Discrete buckets — days of a week, minutes in a zone.
class Bars extends CustomPainter {
  final List<double> d;
  final Color color, track;
  final int highlight;
  final double t;

  /// The shared scale, measured from [AxisSpec.min] as the baseline. Without
  /// it every bar chart normalises to its OWN tallest bar, so a 40-minute week
  /// and a 400-minute week draw the identical picture.
  final AxisSpec? axis;

  Bars(this.d, this.color, this.track,
      {this.highlight = -1, this.t = 1, this.axis});

  @override
  void paint(Canvas cv, Size s) {
    if (d.isEmpty || s.width <= 0) return;
    // A bar narrower than ~2pt is not a bar. Aggregate to what fits.
    final v = maxColumns(d, (s.width / 3).floor().clamp(1, d.length));
    final a = axis;
    final mx = a == null ? v.reduce(max) : 0.0;
    if (a == null && mx <= 0) return;
    final bw = s.width / v.length;
    // An aggregated axis can no longer address the caller's index, so the
    // highlight is dropped rather than pointed at the wrong bar.
    final hl = v.length == d.length ? highlight : -1;
    for (var i = 0; i < v.length; i++) {
      final h = (a == null ? v[i] / mx : a.t(v[i])) * s.height * t.clamp(0, 1);
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * bw + bw * .2, s.height - h, bw * .6, max(h, 2)),
          const Radius.circular(3),
        ),
        Paint()
          ..color =
              (hl < 0 || i == hl) ? color : color.withValues(alpha: .35),
      );
    }
  }

  @override
  bool shouldRepaint(covariant Bars o) =>
      o.d != d || o.t != t || o.highlight != highlight || o.axis != axis;
}

/// The score dial. One value, one arc.
class Ring extends CustomPainter {
  final double v;
  final Color color, track;
  final double stroke, t;

  Ring(this.v, this.color, this.track, {this.stroke = 10, this.t = 1});

  @override
  void paint(Canvas cv, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = min(s.width, s.height) / 2 - stroke / 2;
    if (r <= 0) return;
    cv.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    final sweep = 2 * pi * v.clamp(0, 1) * t.clamp(0, 1);
    if (sweep <= 0) return;
    cv.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -pi / 2,
          endAngle: 3 * pi / 2,
          colors: [color.withValues(alpha: .55), color],
          transform: const GradientRotation(-pi / 2),
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant Ring o) => o.v != v || o.t != t;
}

/// The small flat ring used in macro/nutrient clusters.
class MacroRing extends CustomPainter {
  final double v;
  final Color color, track;

  MacroRing(this.v, this.color, this.track);

  @override
  void paint(Canvas cv, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = min(s.width, s.height) / 2 - 4;
    if (r <= 0) return;
    cv.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = track,
    );
    final sweep = 2 * pi * v.clamp(0, 1);
    if (sweep <= 0) return;
    cv.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant MacroRing o) => o.v != v;
}

/// The four sleep lanes, top to bottom: awake, REM, light, deep.
enum SleepStage { awake, rem, light, deep }

extension SleepStageX on SleepStage {
  /// The name that goes in the legend. Four lanes of four colours with nothing
  /// naming them is the single least readable chart in the app.
  String get label => const ['Awake', 'REM', 'Light', 'Deep'][index];
}

/// Hypnogram — conventional lanes, minimum 2pt wide so a 30 s arousal in an
/// eight-hour night is still a visible mark rather than a rounding error.
///
/// [stages] is one entry per epoch, in order. It comes from the stager; this
/// painter has no opinion about what a night looks like.
class Hypnogram extends CustomPainter {
  final List<SleepStage> stages;
  final double t;

  Hypnogram(this.stages, {this.t = 1});

  static const cols = <SleepStage, Color>{
    SleepStage.awake: C.orange,
    SleepStage.rem: C.teal,
    SleepStage.light: C.sky,
    SleepStage.deep: C.blue,
  };

  /// Hand straight to `ChartFrame.legend`. Derived from [cols] rather than
  /// retyped, so a lane can never be recoloured without its key following.
  static List<(String, Color)> get legend =>
      [for (final s in SleepStage.values) (s.label, cols[s]!)];

  @override
  void paint(Canvas cv, Size s) {
    if (stages.isEmpty) return;
    final lane = s.height / 4, w = s.width / stages.length;
    final n =
        (stages.length * t.clamp(0, 1)).round().clamp(1, stages.length);
    for (var i = 0; i < n; i++) {
      final st = stages[i];
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              i * w, st.index * lane + 2, max(w - .8, 2), lane - 5),
          const Radius.circular(2),
        ),
        Paint()..color = cols[st]!,
      );
    }
  }

  @override
  bool shouldRepaint(covariant Hypnogram o) => o.t != t || o.stages != stages;
}

/// Time-in-zone as one stacked bar. [z] is five fractions summing to ≤ 1.
class ZoneBar extends CustomPainter {
  final List<double> z;

  ZoneBar(this.z);

  static const cols = [C.blueSoft, C.blue, C.green, C.orange, C.red];

  /// Five bands of colour mean nothing without their numbers. Derived from
  /// [cols] for the same reason [Hypnogram.legend] is.
  static List<(String, Color)> get legend =>
      [for (var i = 0; i < cols.length; i++) ('Zone ${i + 1}', cols[i])];

  @override
  void paint(Canvas cv, Size s) {
    var x = 0.0;
    for (var i = 0; i < z.length && i < cols.length; i++) {
      final w = z[i] * s.width;
      if (w <= .5) continue;
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, max(w - 2, 1), s.height),
          const Radius.circular(3),
        ),
        Paint()..color = cols[i],
      );
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant ZoneBar o) => o.z != z;
}

/// Actogram — hour of day (rows) × date (columns). The circadian view.
///
/// [days] is one entry per day, each a 24-slot list of 0…1 intensity, or null
/// where nothing was recorded. A null day paints nothing — a gap in the record
/// reads as a gap, not as a night of no sleep.
class Actogram extends CustomPainter {
  final List<List<double>?> days;
  final Color color;

  Actogram(this.days, this.color);

  @override
  void paint(Canvas cv, Size s) {
    if (days.isEmpty) return;
    final cw = s.width / days.length, ch = s.height / 24;
    for (var d = 0; d < days.length; d++) {
      final day = days[d];
      if (day == null) continue;
      for (var h = 0; h < 24 && h < day.length; h++) {
        final v = day[h].clamp(0.0, 1.0);
        if (v <= 0) continue;
        cv.drawRect(
          Rect.fromLTWH(d * cw, h * ch, cw + .4, ch),
          Paint()..color = color.withValues(alpha: .22 + v * .68),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant Actogram o) => o.days != days;
}

/// Week × weekday grid. [values] is week-major, 7 per week; null = no data,
/// which paints the empty track rather than a low value.
class HeatMap extends CustomPainter {
  final List<List<double?>> weeks;
  final Color color, track;

  HeatMap(this.weeks, this.color, this.track);

  @override
  void paint(Canvas cv, Size s) {
    if (weeks.isEmpty) return;
    final cw = s.width / weeks.length, ch = s.height / 7;
    for (var w = 0; w < weeks.length; w++) {
      for (var d = 0; d < 7 && d < weeks[w].length; d++) {
        final v = weeks[w][d];
        cv.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * cw + 1, d * ch + 1, cw - 2.5, ch - 2.5),
            const Radius.circular(2),
          ),
          Paint()
            ..color = v == null
                ? track
                : color.withValues(alpha: .18 + v.clamp(0.0, 1.0) * .74),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant HeatMap o) => o.weeks != weeks;
}

/// Power spectral density — the LF/HF plot behind HRV. [psd] is the computed
/// spectrum; [split] is the fraction of the x-axis where LF becomes HF.
class Spectrum extends CustomPainter {
  final List<double> psd;
  final double split;
  final Color lf, hf;

  Spectrum(this.psd, {this.split = .28, this.lf = C.blue, this.hf = C.purple});

  /// Two colours that mean two different bands of a frequency axis — the one
  /// chart in here nobody reads correctly without a key.
  List<(String, Color)> get legend => [('LF power', lf), ('HF power', hf)];

  @override
  void paint(Canvas cv, Size s) {
    if (psd.isEmpty) return;
    final v = maxColumns(psd, (s.width / 3).floor().clamp(1, psd.length));
    final mx = v.reduce(max);
    if (mx <= 0) return;
    final bw = s.width / v.length;
    for (var i = 0; i < v.length; i++) {
      final f = i / v.length;
      final h = v[i] / mx * s.height;
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * bw, s.height - h, max(bw - .8, 1), h),
          const Radius.circular(1),
        ),
        Paint()..color = (f < split ? lf : hf).withValues(alpha: .85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant Spectrum o) => o.psd != psd;
}

/// Several signals stacked over one shared night timeline — HR, movement,
/// SpO₂ relative, whatever the screen has. Each lane is independently scaled,
/// because they are different units and a shared axis would be a lie.
class NightStack extends CustomPainter {
  final List<List<double>> series;
  final List<Color> colors;

  /// One axis per lane, in the same order as [series]; a null entry (or a
  /// short list) leaves that lane auto-scaled. Different units genuinely need
  /// different axes — what they must not do is each invent a new one every
  /// time the data shifts, which is what makes a lane look dramatic on a quiet
  /// night. Pin the ones the screen labels.
  final List<AxisSpec?>? axes;

  NightStack(this.series, this.colors, {this.axes});

  @override
  void paint(Canvas cv, Size s) {
    if (series.isEmpty || s.width <= 0) return;
    final h = s.height / series.length;
    for (var k = 0; k < series.length; k++) {
      final d = series[k];
      if (d.length < 2) continue;
      final a = (axes != null && k < axes!.length) ? axes![k] : null;
      final e = a == null ? _extent(d) : null;
      double y(double v) => a != null
          ? k * h + h - 6 - a.t(v) * (h - 14)
          : k * h + h - 6 - (v - e!.min) / e.range * (h - 14);
      final pts = minMaxColumns(d, s.width, y);
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      cv.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = colors[k % colors.length],
      );
    }
  }

  @override
  bool shouldRepaint(covariant NightStack o) =>
      o.series != series || o.axes != axes;
}
