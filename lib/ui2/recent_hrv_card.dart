// Recent HRV (Build 90, Akshat's option A): the last 14 nights against the
// usual range Recovery compared last night with, plus a labelled 7-night
// average, so one low night reads as one night. Shared by the Recovery page
// and the HRV page, which therefore describe a night the same way.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../compute/readiness_explain.dart' show RecentHrvView, recentHrv;
import '../data/day_label.dart' show todayLabel;
import '../data/db.dart';
import 'revision.dart';
import 'screens/home_screen.dart' show prettyDay;
import 'grammar.dart';
import 'theme.dart';

export '../compute/readiness_explain.dart' show RecentHrvView;

/// [day]'s recent-HRV view on Recovery's own series (`ln_rmssd_v2`, measured
/// nights only) and window; [day] null means the newest measured night.
/// Null when there is no night to show.
Future<RecentHrvView?> loadRecentHrv(String? day) async {
  final series = [
    for (final r in await LocalDb.metricSeries(
      'ln_rmssd_v2',
      measuredOnly: true,
    ))
      if (r['date'] is String && r['value'] is num)
        (date: r['date'] as String, value: (r['value'] as num).toDouble()),
  ];
  final at = day ?? (series.isEmpty ? null : series.last.date);
  if (at == null) return null;
  final view = recentHrv(series, at);
  return view.nights.isEmpty ? null : view;
}

/// The card, loading itself (the HRV page).
class RecentHrvSection extends StatefulWidget {
  const RecentHrvSection({super.key, this.day});
  final String? day;
  @override
  State<RecentHrvSection> createState() => _RecentHrvSectionState();
}

class _RecentHrvSectionState extends State<RecentHrvSection>
    with RevisionReload {
  RecentHrvView? _view;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Build 91 (Codex audit F08): re-read when new nights land or the page
  // moves to another day, like the chart above it; a failed read keeps what
  // is shown rather than blanking it.
  @override
  void reload() => _load();

  @override
  void didUpdateWidget(RecentHrvSection old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day) _load();
  }

  void _load() {
    final t = beginRead(#recentHrv);
    loadRecentHrv(widget.day).then((v) {
      if (stillNewest(#recentHrv, t)) setState(() => _view = v);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext c) => _view == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: S.x4),
          child: RecentHrvCard(_view!),
        );
}

class RecentHrvCard extends StatelessWidget {
  const RecentHrvCard(this.view, {super.key, this.sharedWith = 'Recovery'});

  final RecentHrvView view;

  /// The other page that reads the same nights and window.
  final String sharedWith;

  /// One plain sentence for the night against the band and the week.
  ///
  /// Build 91 (Codex audit F08): "last night" only for today's view (an
  /// older day names its date), and the 7-night average's side is judged on
  /// its own, never borrowed from the night.
  static String sentence(RecentHrvView v, {String? today}) {
    final last = v.last, band = v.usual, avg = v.before;
    final current = v.day == (today ?? todayLabel());
    final when = current ? 'last night' : 'on ${prettyDay(v.day)}';
    if (last == null) {
      return current
          ? 'No HRV measured last night.'
          : 'No HRV measured for ${prettyDay(v.day)}.';
    }
    final ms = '${last.round()} ms $when';
    if (band == null) {
      return '$ms. Your usual range appears after 14 measured nights.';
    }
    final range = '${band.lo.round()}–${band.hi.round()}';
    String sideOf(double x) =>
        x < band.lo ? 'below' : (x > band.hi ? 'above' : 'inside');
    final side = sideOf(last);
    if (side == 'inside') return '$ms, inside your usual $range.';
    if (avg == null) return '$ms, $side your usual $range.';
    final avgSide = sideOf(avg);
    // Build 91: judged on the nights BEFORE this one. A 7-night average that includes a single crash can sit below
    // the band and wrongly read as "several nights".
    final week = 'The nights before averaged ${avg.round()} ms,';
    if (avgSide == 'inside') {
      return '$ms, $side your usual $range. $week inside it: '
          'one night, not a trend yet.';
    }
    if (avgSide == side) {
      return '$ms, $side your usual $range. $week $side it too: '
          'several nights, not one.';
    }
    return '$ms, $side your usual $range. $week $avgSide it.';
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final col = p.on(C.recovery);
    return Surface(
      semanticLabel: 'Recent HRV. ${sentence(view)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent HRV',
                  style: F.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'last ${view.nights.length} '
                '${view.nights.length == 1 ? 'night' : 'nights'}',
                style: F.cap.copyWith(color: p.ink2),
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          ExcludeSemantics(
            child: SizedBox(
              height: 132,
              child: CustomPaint(
                painter: _RecentHrvPainter(
                  view,
                  line: col,
                  band: col.withValues(alpha: .14),
                  alert: p.on(C.alert),
                  dotFill: p.card,
                  text: F.over.copyWith(color: p.ink2),
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: S.x1),
          Wrap(
            spacing: S.x3,
            runSpacing: S.x1,
            children: [
              if (view.usual != null)
                _Legend(
                  swatch: Container(
                    width: 14,
                    height: 9,
                    decoration: BoxDecoration(
                      color: col.withValues(alpha: .2),
                      borderRadius: R.rSm,
                    ),
                  ),
                  label: 'usual range, last 28 nights',
                ),
              _Legend(
                swatch: CustomPaint(
                  size: const Size(16, 3),
                  painter: _DashPainter(col),
                ),
                label: '7-night average',
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          Text(
            sentence(view),
            style: F.body.copyWith(color: p.ink, height: 1.4),
          ),
          const SizedBox(height: S.x1),
          Text(
            'Same nightly HRV and 28-night window as $sharedWith.',
            style: F.cap.copyWith(color: p.ink2),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.swatch, required this.label});
  final Widget swatch;
  final String label;
  @override
  Widget build(BuildContext c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      swatch,
      const SizedBox(width: S.x1),
      Flexible(
        child: Text(label, style: F.cap.copyWith(color: P.of(c).ink2)),
      ),
    ],
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + 5, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _RecentHrvPainter extends CustomPainter {
  _RecentHrvPainter(
    this.v, {
    required this.line,
    required this.band,
    required this.alert,
    required this.dotFill,
    required this.text,
  });

  final RecentHrvView v;
  final Color line, band, alert, dotFill;
  final TextStyle text;

  @override
  void paint(Canvas canvas, Size size) {
    final n = v.nights;
    if (n.isEmpty) return;
    const labelW = 28.0, bottom = 16.0, top = 6.0;
    final w = size.width - labelW;
    final h = size.height - bottom - top;
    final values = [
      for (final x in n) x.ms,
      if (v.usual != null) ...[v.usual!.lo, v.usual!.hi],
    ];
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    final pad = math.max(2.0, (hi - lo) * .12);
    lo -= pad;
    hi += pad;
    double y(double ms) => top + (hi - ms) / (hi - lo) * h;
    double x(int i) => n.length == 1 ? w / 2 : i * w / (n.length - 1);

    void label(String s, Offset at) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: text),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at);
      tp.dispose();
    }

    if (v.usual case final u?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, y(u.hi), w, y(u.lo)),
          const Radius.circular(3),
        ),
        Paint()..color = band,
      );
      label('${u.hi.round()}', Offset(w + 4, y(u.hi) - 6));
      label('${u.lo.round()}', Offset(w + 4, y(u.lo) - 6));
    }

    // Nightly line, faint, under the dots.
    final path = Path();
    for (var i = 0; i < n.length; i++) {
      i == 0 ? path.moveTo(x(i), y(n[i].ms)) : path.lineTo(x(i), y(n[i].ms));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = line.withValues(alpha: .55),
    );

    // 7-night average (geometric, as the card's sentence), dashed.
    final avg = <Offset>[];
    for (var i = 0; i < n.length; i++) {
      final from = math.max(0, i - 6);
      final logs = [for (var j = from; j <= i; j++) math.log(n[j].ms)];
      avg.add(
        Offset(x(i), y(math.exp(logs.reduce((a, b) => a + b) / logs.length))),
      );
    }
    final dash = Paint()
      ..color = line
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < avg.length; i++) {
      final a = avg[i - 1], b = avg[i];
      final len = (b - a).distance;
      for (var t = 0.0; t < len; t += 9) {
        final s = a + (b - a) * (t / len);
        final e = a + (b - a) * (math.min(t + 5, len) / len);
        canvas.drawLine(s, e, dash);
      }
    }

    for (var i = 0; i < n.length; i++) {
      final last = i == n.length - 1 && v.lastDate == n[i].date;
      final out =
          v.usual != null && (n[i].ms < v.usual!.lo || n[i].ms > v.usual!.hi);
      final c = Offset(x(i), y(n[i].ms));
      canvas.drawCircle(
        c,
        last ? 5 : 3,
        Paint()..color = last && out ? alert : dotFill,
      );
      canvas.drawCircle(
        c,
        last ? 5 : 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = last && out ? alert : line,
      );
    }
    String md(String d) {
      const m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final p = DateTime.parse(d);
      return '${m[p.month - 1]} ${p.day}';
    }

    label(md(n.first.date), Offset(0, size.height - 13));
    if (n.length > 1) {
      final s = v.lastDate == n.last.date ? 'last night' : md(n.last.date);
      final tp = TextPainter(
        text: TextSpan(text: s, style: text),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w - tp.width, size.height - 13));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_RecentHrvPainter old) => old.v != v;
}
