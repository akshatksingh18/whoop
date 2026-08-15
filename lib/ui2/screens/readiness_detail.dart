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

  /// DENSE — one slot per calendar day, `null` where no score was stored. The
  /// chart under it is dated, and `seriesOf` (values only) cannot date
  /// anything: a five-point series from five scattered weeks used to be drawn
  /// as five consecutive days.
  final List<double?> series;

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
      series: denseDays(pointsOf(chart), 90),
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
                  why: 'Needs a night of beat-to-beat data, plus your own '
                      'history to compare it to.') ??
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
                    painter: Ring(d.readiness.normalized(100), p.on(band.color),
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
                  '${d.inputsUsed}/${d.breakdown.length} inputs · missing ones '
                  're-weighted, never zeroed',
                  style: F.cap.copyWith(color: p.ink3, height: 1.5),
                ),
              ),
            ]),
          ),
        ] else if (v != null)
          Section(
            'What went into it',
            const StatusCard(
              'No breakdown yet',
              'Ranking each input against your own history takes about two '
                  'weeks of nights.',
              icon: LucideIcons.listTree,
            ),
          ),

        // The header used to say "Last 90 days" over a chart of five points.
        // It says what is drawn.
        Section(
          _historyTitle(d),
          !d.series.any((v) => v != null)
              ? const StatusCard(
                  'No readiness history',
                  '0 days scored.',
                  fix: 'Wear the band overnight',
                  icon: LucideIcons.chartLine,
                )
              : Surface(child: _history(c, d)),
        ),
        const SizedBox(height: S.x5),
        investigateRow(c, () => go(c, const Investigate('readiness'))),
      ],
    ]);
  }

  /// The last 90 CALENDAR days, trimmed to start at the first day that
  /// actually has a score — so the x labels span real dates and the empty run
  /// before the first sync is not drawn as ninety missing days.
  List<double?> _window(ReadinessData d) {
    final first = d.series.indexWhere((v) => v != null);
    return first <= 0 ? d.series : d.series.sublist(first);
  }

  String _historyTitle(ReadinessData d) {
    final n = d.series.any((v) => v != null) ? _window(d).length : 0;
    return n == 0 ? 'History' : 'Last $n day${n == 1 ? '' : 's'}';
  }

  Widget _history(BuildContext c, ReadinessData d) {
    final win = _window(d);
    // Readiness is a 0–100 score and the axis says so — auto-scaling turned a
    // 71-to-76 week into a chart that looked like a collapse and a recovery.
    const axis = AxisSpec(min: 0, max: 100, ticks: 3, format: axisInt);
    final p = P.of(c);
    return ChartFrame(
      title: 'Readiness',
      unit: '/100',
      height: 120,
      yAxis: axis,
      xLabels: ['${win.length} day${win.length == 1 ? '' : 's'} ago', 'Today'],
      conf: ConfX.of(d.readiness),
      series: win,
      child: CustomPaint(
        size: Size.infinite,
        painter: LineChart(win, p.on(C.green), dots: false, t: animate(c, 1),
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
                '${used ? '' : ' · not available'}'
                '${used && contribution == null ? ' · contribution not reported' : ''}'
                '$caveat'
                // An unlabelled glyph is not an explanation. This is the
                // smallest-worthwhile-change gate, so it says what it means.
                '${used && !pastMdc ? ' · within your usual spread' : ''}',
                style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
        const SizedBox(width: S.x3),
        // No contribution number means no number — three grey dots, the same
        // absence affordance an unused input gets. The branch that printed a
        // bare em-dash here was unreachable from the producer
        // (`readiness_glassbox.dart` types `weightedContribution` as a
        // non-null double) but it was still the one place in the app that
        // could render one, and the sub-line above says which case it is.
        if (!used || contribution == null)
          const ConfDots(Conf.none)
        else
          Text(
            '${contribution >= 0 ? '+' : '−'}'
            '${contribution.abs().toStringAsFixed(1)}',
            style: F.n17.copyWith(
                color: p.on(contribution >= 0 ? C.green : C.orange)),
          ),
      ]),
    );
  }
}
