// READINESS — the one composite, taken apart.
//
// Two producers meet on this screen and the copy says so rather than blending
// them: the headline number is the weighted composite, and the breakdown is a
// parallel percentile view of the same four inputs. Presenting the second as
// if it decomposed the first would be a small lie that is very hard to catch.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/local_repository.dart';
import '../../models/metric.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'investigate.dart';
import 'metric_detail.dart';

class ReadinessData {
  final Metric readiness;
  final String narrative;
  final List<Map<String, dynamic>> breakdown;
  final int inputsUsed;
  final Metric glassbox;
  final List<double> series;

  const ReadinessData({
    this.readiness = Metric.empty,
    this.narrative = '',
    this.breakdown = const [],
    this.inputsUsed = 0,
    this.glassbox = Metric.empty,
    this.series = const [],
  });

  static Future<ReadinessData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final chart = await repo.getChart('recovery');

    final daily = today['daily'];
    final gb = cd['readiness_glassbox'];
    final v = envValue(gb) ?? const <String, dynamic>{};
    final bd = v['breakdown'];

    return ReadinessData(
      readiness: metricOf(daily is Map ? daily['readiness'] : null),
      narrative: (v['narrative'] ?? '').toString(),
      breakdown: [
        for (final e in (bd is List ? bd : const []))
          if (e is Map) e.cast<String, dynamic>(),
      ],
      inputsUsed: (v['inputs_used'] as num?)?.toInt() ?? 0,
      glassbox: envMetric(gb, v['score'] as num?),
      series: seriesOf(chart),
    );
  }
}

class ReadinessDetail extends StatefulWidget {
  final ReadinessData? data;
  const ReadinessDetail({super.key, this.data});

  @override
  State<ReadinessDetail> createState() => _ReadinessDetailState();
}

class _ReadinessDetailState extends State<ReadinessDetail> {
  ReadinessData? _d;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _d = widget.data;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final d = await ReadinessData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d ?? const ReadinessData();
    final v = d.readiness.value;
    final band = readinessBand(v);

    return detailScaffold(c, 'Readiness', [
      if (_loading && _d == null) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else ...[
        if (v == null)
          StatusCard.forMetric('Readiness is not scored', d.readiness,
                  why: 'The composite needs a night of beat-to-beat data and '
                      'enough of your own history to know what normal is.') ??
              const SizedBox.shrink()
        else
          Surface(
            child: Column(children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(
                    size: const Size(150, 150),
                    painter: Ring(d.readiness.normalized(100), band.color,
                        p.track,
                        stroke: 14, t: animate(c, 1)),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${v.round()}', style: F.n48.copyWith(color: p.ink)),
                    Text(band.label, style: F.cap.copyWith(color: p.ink3)),
                  ]),
                ]),
              ),
              if (d.narrative.isNotEmpty) ...[
                const SizedBox(height: S.x5),
                Text(d.narrative,
                    textAlign: TextAlign.center,
                    style: F.body.copyWith(color: p.ink2, height: 1.5)),
              ],
            ]),
          ),

        if (d.breakdown.isNotEmpty) ...[
          Section('What went into it', _breakdown(c, p, d)),
          const SizedBox(height: S.x4),
          Surface(
            elevation: 0,
            color: p.card2,
            child: Row(children: [
              ConfDots(ConfX.of(d.readiness), size: 6),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(
                  '${d.inputsUsed} of ${d.breakdown.length} inputs had enough '
                  'history last night. Missing inputs are re-weighted across '
                  'the rest, never counted as zero.',
                  style: F.cap.copyWith(color: p.ink3, height: 1.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: S.x3),
          Text(
              'The score above is a weighted composite. The rows are a parallel '
              'view of the same ${d.breakdown.length} inputs, each ranked '
              'against your own history — they explain the direction, not the '
              'arithmetic. A row marked "within your usual spread" moved by '
              'less than the smallest change this measurement can tell apart '
              'from noise.',
              style: F.over.copyWith(color: p.ink3, height: 1.5)),
        ] else if (v != null)
          Section(
            'What went into it',
            const StatusCard(
              'No breakdown yet',
              'Each input is ranked against your own history, and that ranking '
                  'needs about two weeks of nights before it means anything.',
              icon: LucideIcons.listTree,
            ),
          ),

        // The header used to say "Last 90 days" over a chart of five points.
        // It says what is drawn.
        Section(
          _historyTitle(d),
          d.series.isEmpty
              ? const StatusCard(
                  'No readiness history',
                  'One score is stored per day, and no day has produced one yet.',
                  icon: LucideIcons.chartLine,
                )
              : Surface(child: _history(c, d)),
        ),
        const SizedBox(height: S.x5),
        investigateRow(c, () => go(c, const Investigate('readiness'))),
      ],
    ]);
  }

  /// At most the last 90 stored scores — and no more days than exist.
  List<double> _window(ReadinessData d) =>
      d.series.length <= 90 ? d.series : d.series.sublist(d.series.length - 90);

  String _historyTitle(ReadinessData d) {
    final n = _window(d).length;
    return n == 0 ? 'History' : 'Last $n day${n == 1 ? '' : 's'}';
  }

  Widget _history(BuildContext c, ReadinessData d) {
    final win = _window(d);
    // Readiness is a 0–100 score and the axis says so — auto-scaling turned a
    // 71-to-76 week into a chart that looked like a collapse and a recovery.
    const axis = AxisSpec(min: 0, max: 100, ticks: 3, format: axisInt);
    return ChartFrame(
      title: 'Readiness',
      unit: '/100',
      height: 120,
      yAxis: axis,
      xLabels: ['${win.length} day${win.length == 1 ? '' : 's'} ago', 'Today'],
      conf: ConfX.of(d.readiness),
      child: CustomPaint(
        size: Size.infinite,
        painter: LineChart(win, C.green, dots: false, t: animate(c, 1),
            axis: axis),
      ),
    );
  }

  Widget _breakdown(BuildContext c, P p, ReadinessData d) {
    final rows = d.breakdown;
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          _row(p, rows[i]),
        ],
      ]),
    );
  }

  Widget _row(P p, Map<String, dynamic> r) {
    final key = r['label']?.toString() ?? '';
    final weight = (r['weight'] as num?) ?? 0;
    final contribution = (r['weighted_contribution'] as num?);
    final used = r['used'] == true;
    final pastMdc = r['past_mdc'] == true;
    // The temperature input is a raw sensor deviation, not a calibrated
    // temperature, and it is 10% of the score. It gets said, every time.
    final caveat = key == 'temp' ? ' · relative, uncalibrated' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(driverLabel(key), style: F.body.copyWith(color: p.ink)),
            Text(
                '${(weight * 100).round()}% weight'
                '${used ? '' : ' · not available'}$caveat'
                // An unlabelled glyph is not an explanation. This is the
                // smallest-worthwhile-change gate, so it says what it means.
                '${used && !pastMdc ? ' · within your usual spread' : ''}',
                style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
        const SizedBox(width: S.x3),
        if (!used)
          const ConfDots(Conf.none)
        else
          Text(
            contribution == null
                ? '—'
                : '${contribution >= 0 ? '+' : '−'}'
                    '${contribution.abs().toStringAsFixed(1)}',
            style: F.n17.copyWith(
                color: p.on(contribution == null || contribution >= 0
                    ? C.green
                    : C.orange)),
          ),
      ]),
    );
  }
}
