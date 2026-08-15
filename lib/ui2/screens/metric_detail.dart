// The shared metric drill-down — density 2 of 3.
//
// Glance (a row on Health) → MetricDetail (your normal range, what moves it,
// how this week compares) → Investigate (everything, in mono). There is no
// "advanced mode" switch: depth is a place you walk to, not a preference you
// set, so the same person gets the shallow read on Monday and the deep one
// when something looks wrong.
//
// Every metric goes through THIS screen. Forty bespoke detail screens is how
// the old UI ended up with forty different opinions about what a chart is.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/local_repository.dart';
import '../../models/metric.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'investigate.dart';

// ═══════════════════ the vocabulary ═══════════════════

/// What a metric key means on screen, and whether we are willing to draw it.
class MetricSpec {
  /// The alias `getChart` / `getTrend` understand (`_trendKey` maps it on).
  final String chartKey;
  final String title;
  final String unit;
  final Color color;
  final IconData icon;
  final bool higherBetter;

  /// Non-null when this metric must NOT be charted. The string is the honest
  /// reason, shown as a `StatusCard` in place of the chart.
  final String? suppress;
  final String? suppressFix;

  /// How it is computed, and who published the method. Rendered by Investigate.
  final String method;
  final String citation;

  const MetricSpec({
    required this.chartKey,
    required this.title,
    this.unit = '',
    this.color = C.blue,
    this.icon = LucideIcons.activity,
    this.higherBetter = true,
    this.suppress,
    this.suppressFix,
    this.method = '',
    this.citation = '',
  });
}

const _specs = <String, MetricSpec>{
  'resting_hr': MetricSpec(
    chartKey: 'resting_hr',
    title: 'Resting heart rate',
    unit: 'bpm',
    color: C.red,
    icon: LucideIcons.heart,
    higherBetter: false,
    method: 'The lowest sustained sleeping heart rate of the night, taken over '
        'a rolling window of the overnight series. Not a spot reading, and not '
        'a daytime minimum.',
    citation: 'Nocturnal heart-rate minimum; personal baseline, not population',
  ),
  'hrv': MetricSpec(
    chartKey: 'hrv',
    title: 'HRV',
    unit: 'ms',
    color: C.green,
    icon: LucideIcons.activity,
    method: 'RMSSD over the longest artefact-free window during sleep. Beat '
        'timing is recovered from the band\'s 1 Hz records and corrected by '
        'the Lipponen–Tarvainen method before any statistic is taken. '
        'Pulse-derived, so this is PRV: real and trendable, but not ECG HRV.',
    citation: 'Task Force 1996 · Lipponen & Tarvainen 2019',
  ),
  'readiness': MetricSpec(
    chartKey: 'recovery',
    title: 'Readiness',
    color: C.green,
    icon: LucideIcons.batteryCharging,
    // The weights are DATA — `readiness_glassbox` emits one per input and the
    // Readiness screen renders them. Repeating them as prose here meant two
    // surfaces could disagree about the same composite, silently, forever.
    method: 'A weighted composite of a handful of inputs, each scored against '
        'your own history. Every input\'s weight, and whether last night had '
        'enough history to use it, is listed on the Readiness screen. Missing '
        'inputs are re-weighted, never zero-filled.',
    citation: 'Plews 2013 (lnRMSSD) · Hopkins smallest-worthwhile-change gate',
  ),
  'resp_rate': MetricSpec(
    chartKey: 'resp_rate',
    title: 'Respiratory rate',
    unit: 'br/min',
    color: C.teal,
    icon: LucideIcons.wind,
    higherBetter: false,
    method: 'Breathing rate recovered from respiratory sinus arrhythmia — the '
        'periodic modulation breathing imposes on beat timing — over a grid of '
        'candidate rates.',
    citation: 'Pimentel 2017',
  ),
  'sleep': MetricSpec(
    chartKey: 'sleep',
    title: 'Time asleep',
    unit: 'min',
    color: C.blue,
    icon: LucideIcons.moon,
    method: 'Total sleep time from the wrist z-angle sleep window, staged by a '
        'combined actigraphy and heart-rate model.',
    citation: 'van Hees 2015 · Webster / Cole–Kripke rescoring',
  ),
  'efficiency': MetricSpec(
    chartKey: 'efficiency',
    title: 'Sleep efficiency',
    unit: '%',
    color: C.blue,
    icon: LucideIcons.bedDouble,
    method: 'Time asleep as a fraction of time in bed.',
    citation: 'AASM sleep-accounting definitions',
  ),
  'deep': MetricSpec(
    chartKey: 'deep',
    title: 'Deep sleep',
    unit: 'min',
    color: C.blue,
    icon: LucideIcons.moon,
    method: 'A low-confidence overlay: a wrist sensor cannot see slow-wave '
        'activity, so deep sleep here is heart-rate flatness inside NREM.',
    citation: 'Cole–Kripke wake spine + HRV overlay',
  ),
  'rem': MetricSpec(
    chartKey: 'rem',
    title: 'REM sleep',
    unit: 'min',
    color: C.teal,
    icon: LucideIcons.moon,
    method: 'Staged from beat-timing variability and movement. A wrist sensor '
        'separates REM from light sleep only approximately.',
    citation: 'Webster / Cole–Kripke rescoring + HRV staging',
  ),
  'steps': MetricSpec(
    chartKey: 'steps',
    title: 'Steps',
    unit: 'steps',
    color: C.green,
    icon: LucideIcons.footprints,
    method: 'Counted, never modelled. A step count comes from a gait-capable '
        'counter: the band\'s 100 Hz pedometer while it streams, or your '
        'phone\'s. There is no 1 Hz estimate — walking cadence sits above what '
        'one sample a second can resolve, so a day with no counter behind it '
        'reports no steps rather than a guess.',
    citation: 'AN-2554 pedometer · phone pedometer (HealthKit / Health Connect)',
  ),
  'calories': MetricSpec(
    chartKey: 'calories',
    title: 'Active energy',
    unit: 'kcal',
    color: C.orange,
    icon: LucideIcons.flame,
    method: 'Heart-rate-to-energy regression over the waking span, anchored on '
        'your weight, age and sex. An estimate, and sensitive to all three.',
    citation: 'Keytel 2005 · Harris–Benedict / Mifflin BMR floor',
  ),
  'strain': MetricSpec(
    chartKey: 'strain',
    title: 'Strain',
    color: C.purple,
    icon: LucideIcons.zap,
    method: 'Cardiovascular load over the day, compressed onto a 0–21 scale.',
    citation: 'Banister TRIMP family · log-compressed',
  ),
  'trimp': MetricSpec(
    chartKey: 'trimp',
    title: 'Training load',
    color: C.purple,
    icon: LucideIcons.dumbbell,
    method: 'Training impulse: time in each heart-rate zone, weighted by the '
        'physiological cost of that zone.',
    citation: 'Banister 1975 · Edwards 1993',
  ),
  'stress': MetricSpec(
    chartKey: 'stress',
    title: 'Stress',
    color: C.purple,
    icon: LucideIcons.brain,
    higherBetter: false,
    method: 'Baevsky stress index over a resting window: a histogram measure of '
        'how tightly beat intervals cluster. There is deliberately no fallback '
        'when the resting window is missing.',
    citation: 'Baevsky 2008',
  ),
  'dip': MetricSpec(
    chartKey: 'dip',
    title: 'Nocturnal HR dip',
    unit: '%',
    color: C.indigo,
    icon: LucideIcons.trendingDown,
    method: 'How far sleeping heart rate falls below the waking average.',
    citation: 'Nocturnal dipping literature; personal baseline',
  ),
  'hrr': MetricSpec(
    chartKey: 'hrr',
    title: 'Heart-rate recovery',
    unit: 'bpm',
    color: C.red,
    icon: LucideIcons.heartPulse,
    method: 'The drop in heart rate over the 60 seconds after a bout ends, '
        'averaged across the day\'s bouts.',
    citation: 'Cole 1999 (HRR-60)',
  ),
  'lf_hf': MetricSpec(
    chartKey: 'lf_hf',
    title: 'LF / HF',
    color: C.purple,
    icon: LucideIcons.audioWaveform,
    method: 'The ratio of low- to high-frequency power in beat-interval '
        'variability, from a Lomb–Scargle periodogram (the series is unevenly '
        'sampled, so an FFT would be wrong).',
    citation: 'Laguna 1998 · Bigger 1992',
  ),
  'hrv_cv': MetricSpec(
    chartKey: 'hrv_cv',
    title: 'HRV stability',
    unit: '%',
    color: C.green,
    icon: LucideIcons.activity,
    higherBetter: false,
    method: 'Night-to-night coefficient of variation of RMSSD.',
    citation: 'Within-user dispersion',
  ),
  'brv': MetricSpec(
    chartKey: 'brv',
    title: 'Breathing variability',
    color: C.teal,
    icon: LucideIcons.wind,
    higherBetter: false,
    method: 'Coefficient of variation of per-window respiratory rate across '
        'the night.',
    citation: 'Within-user dispersion',
  ),
  'wear': MetricSpec(
    chartKey: 'wear',
    title: 'Wear time',
    unit: 'min',
    color: C.green,
    icon: LucideIcons.watch,
    method: 'Minutes with a band record present. The band logs to flash only '
        'while it is on a wrist, so record presence IS wear.',
    citation: 'Record-presence, not heart-rate validity',
  ),

  // ── charted nowhere, on purpose ──
  'skin_temp': MetricSpec(
    chartKey: 'skin_temp',
    title: 'Skin temperature',
    color: C.orange,
    icon: LucideIcons.thermometer,
    higherBetter: false,
    suppress: 'This is a deviation, not a temperature — and worse, the same '
        'stored series carries three different units depending on where a '
        'night came from: a unitless score from the band, degrees Celsius from '
        'a WHOOP CSV, and WHOOP\'s own index from a cloud export. A line '
        'across mixed units would be wrong in a way you could not see.',
    suppressFix: 'Tonight\'s deviation is still shown on Vitals',
    method: 'The night\'s mean raw sensor reading, expressed as distance from '
        'your own recent nights. There is no conversion to degrees anywhere in '
        'the path.',
    citation: 'Relative only — uncalibrated ADC',
  ),
  // `spo2`, `odi_per_hour` and `strain_effort` used to live here as cards that
  // existed only to explain that they were empty. A metric this app does not
  // produce has no entry, no card and no key. See docs/internal/UI_ROADMAP.md.
  'rmssd_whole': MetricSpec(
    chartKey: 'rmssd_whole',
    title: 'RMSSD, whole night',
    unit: 'ms',
    color: C.green,
    icon: LucideIcons.activity,
    suppress: 'A single value for last night. It is never written to the daily '
        'series, so there is no history to chart — only tonight.',
    method: 'RMSSD across the entire sleep period rather than the cleanest '
        'window inside it.',
    citation: 'Task Force 1996',
  ),
  'stress_si': MetricSpec(
    chartKey: 'stress_si',
    title: 'Stress index',
    color: C.purple,
    icon: LucideIcons.brain,
    higherBetter: false,
    suppress: 'A single value for last night, with no stored history.',
    method: 'Raw Baevsky stress index, before it is banded onto 0–100.',
    citation: 'Baevsky 2008',
  ),
  'brv_slope': MetricSpec(
    chartKey: 'brv_slope',
    title: 'Breathing-rate drift',
    color: C.teal,
    icon: LucideIcons.wind,
    suppress: 'A single value for last night, with no stored history.',
    method: 'Slope of respiratory rate across the night.',
    citation: 'Within-night trend',
  ),
};

MetricSpec specOf(String key) =>
    _specs[key] ??
    MetricSpec(chartKey: key, title: key.replaceAll('_', ' '));

/// Which cross-day percentile block and journal outcome, if any, belongs to
/// this metric. Only four outcomes are correlated by the journal engine.
const _outcomeOf = {
  'hrv': 'rmssd',
  'resting_hr': 'rhr',
  'readiness': 'readiness',
  'efficiency': 'efficiency',
};

// ═══════════════════ the screen ═══════════════════

class MetricData {
  /// DATED points, not bare values. `metric_series` holds one row per DERIVED
  /// day rather than one per calendar day, so a compacted list lets 22 stored
  /// days masquerade as 30 continuous ones — the chart then joins straight
  /// across a sync gap and calls the newest stored point "Today".
  final List<ChartPoint> series;
  final Map<String, dynamic>? percentile;
  final List<Map<String, dynamic>> movers;

  /// Days this install actually has a derived record for. Nothing prunes
  /// `day_result` or `metric_series`, so this is the true horizon — and it is
  /// what decides which range buttons exist.
  final int daysAvailable;

  /// Today's own envelope for this metric, when today carries one. The chart
  /// points are bare numbers; the tier has to come from somewhere real.
  final Metric latest;

  const MetricData({
    this.series = const [],
    this.percentile,
    this.movers = const [],
    this.daysAvailable = 0,
    this.latest = Metric.empty,
  });

  static Future<MetricData> load(LocalRepository repo, String key) async {
    final spec = specOf(key);
    if (spec.suppress != null) return const MetricData();
    final chart = await repo.getChart(spec.chartKey);
    final days = await repo.availableDays();
    final today = await repo.getToday();
    final outcome = _outcomeOf[key];

    Map<String, dynamic>? pct;
    var movers = const <Map<String, dynamic>>[];
    if (outcome != null) {
      final cd = await repo.getInsights();
      final all = cd['percentiles'];
      final one = all is Map ? all[outcome] : null;
      pct = envValue(one);
      final j = await repo.getJournalInsights(range: '90d');
      final ins = j['insights'];
      movers = [
        for (final e in (ins is List ? ins : const []))
          if (e is Map && e['outcome'] == outcome) e.cast<String, dynamic>(),
      ];
    }
    return MetricData(
      series: pointsOf(chart),
      percentile: pct,
      movers: movers,
      daysAvailable: days.length,
      latest: todayMetric(today, key),
    );
  }
}

/// Today's envelope for a metric key, or `Metric.empty` when today does not
/// carry one. Most keys are scalars under `daily`; four live in their own
/// blocks and one of those is keyed by its own name rather than `value`.
Metric todayMetric(Map<String, dynamic> today, String key) {
  switch (key) {
    case 'hrv':
      final b = today['hrv'];
      final rmssd = b is Map ? b['rmssd'] as num? : null;
      if (rmssd == null || b is! Map) return Metric.empty;
      return Metric.parse(
          {...b.cast<String, dynamic>(), 'value': rmssd, 'unit': 'ms'});
    case 'sleep':
      final b = today['sleep'];
      return metricOf(b is Map ? b['duration_min'] : null);
    case 'resp_rate':
      return metricOf(today['resp']);
    case 'stress':
      return metricOf(today['stress']);
    case 'skin_temp':
      return metricOf(today['skin_temp']);
  }
  final daily = today['daily'];
  return metricOf(daily is Map ? daily[key] : null);
}

class MetricDetail extends StatefulWidget {
  final String metricKey;
  final MetricData? data;
  const MetricDetail(this.metricKey, {super.key, this.data});

  @override
  State<MetricDetail> createState() => _MetricDetailState();
}

class _MetricDetailState extends State<MetricDetail> {
  static const _windows = [7, 30, 182, 365];
  static const _labels = ['7 days', '30 days', '6 months', 'Year'];
  int _range = 1;
  MetricData? _d;
  bool _loading = true;

  /// How many range buttons this install has data behind.
  ///
  /// Nothing prunes the derived series, so the honest horizon is the life of
  /// the install — but offering "Year" to someone with three weeks is offering
  /// a button that can only ever show three weeks under a label that says a
  /// year. A range appears once there are enough days to fill it; the shortest
  /// one always appears, because it is where a new user starts.
  int _offered(MetricData d) {
    var n = 1;
    for (var i = 1; i < _windows.length; i++) {
      if (d.daysAvailable >= _windows[i]) n = i + 1;
    }
    return n;
  }

  /// The reason the next range up is not there yet, in its own words.
  String? _lockedNote(MetricData d) {
    final n = _offered(d);
    if (n >= _windows.length) return null;
    return '${_labels[n]} needs ${_windows[n]} days of history. '
        'You have ${d.daysAvailable}.';
  }

  Widget _ranges(BuildContext c, MetricData d, Color color) {
    final p = P.of(c);
    final n = _offered(d);
    final note = _lockedNote(d);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SubTabs(_labels.sublist(0, n), _range.clamp(0, n - 1),
          (i) => setState(() => _range = i),
          color: color),
      if (note != null) ...[
        const SizedBox(height: S.x2),
        Text(note, style: F.over.copyWith(color: p.ink3)),
      ],
    ]);
  }

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
      final d = await MetricData.load(repo, widget.metricKey);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final spec = specOf(widget.metricKey);
    final d = _d ?? const MetricData();

    final all = d.series;
    final win = _windows[_range.clamp(0, _offered(d) - 1)];
    // Dense: one slot per calendar day in the window, `null` where no day
    // derived. The painter breaks the line at a null rather than joining over
    // it, and the axis labels can be dated because the slots ARE the dates.
    final series = denseDays(all, win);
    final vals = [for (final v in series) ?v];

    return detailScaffold(c, spec.title, [
      if (spec.suppress != null) ...[
        const SizedBox(height: S.x2),
        StatusCard(
          'Not shown as a trend',
          spec.suppress!,
          fix: spec.suppressFix ?? '',
          icon: spec.icon,
        ),
        const SizedBox(height: S.x5),
        investigateRow(c, () => go(c, Investigate(widget.metricKey))),
      ] else if (vals.isEmpty) ...[
        _ranges(c, d, spec.color),
        const SizedBox(height: S.x5),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          StatusCard(
            'No history for ${spec.title.toLowerCase()} yet',
            'This chart is built from one value per day, and no day in this '
                'window produced one.',
            fix: 'Wear the band overnight to start the series',
            icon: spec.icon,
          ),
        const SizedBox(height: S.x5),
        investigateRow(c, () => go(c, Investigate(widget.metricKey))),
      ] else ...[
        _ranges(c, d, spec.color),
        const SizedBox(height: S.x5),
        _hero(c, spec, all, series, vals, d.latest),
        Section('Your normal range', _range3(c, spec, vals, d.percentile)),
        if (d.movers.isNotEmpty)
          Section('What moves it', _movers(c, d.movers)),
        const SizedBox(height: S.x5),
        investigateRow(c, () => go(c, Investigate(widget.metricKey))),
      ],
    ]);
  }

  // ── value → context → trend → confidence ──
  Widget _hero(BuildContext c, MetricSpec spec, List<ChartPoint> all,
      List<double?> series, List<double> vals, Metric latest) {
    final p = P.of(c);
    final now = vals.last;
    // How old the number under the headline actually is. `metric_series` only
    // gets a row on a day that derives, so after a sync gap the newest stored
    // point can be days old — and it was being printed as though it were this
    // morning's.
    final behind = all.isEmpty ? null : daysBehind(all.last.t);
    // Trailing 28 days EXCLUDING the newest — the same window the data layer's
    // own baseline uses. Comparing a reading against a mean that contains it is
    // how a baseline quietly chases the value it is supposed to anchor.
    final vAll = valuesOf(all);
    final prior = vAll.length > 1
        ? vAll.sublist(vAll.length - 1 - (vAll.length - 1).clamp(0, 28),
            vAll.length - 1)
        : const <double>[];
    final base =
        prior.isEmpty ? null : prior.reduce((a, b) => a + b) / prior.length;
    final delta = base == null ? null : now - base;
    final good = delta == null
        ? true
        : (delta >= 0) == spec.higherBetter || delta.abs() < 0.0001;

    return Surface(
      child: Column(children: [
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_fmt(spec, now), style: F.n48.copyWith(color: p.ink)),
              const SizedBox(width: S.x2),
              Text(spec.unit, style: F.body.copyWith(color: p.ink3)),
              const Spacer(),
              // Every metric on this screen used to claim three filled dots.
              // When today carries no envelope for this key there is no tier
              // to show, so nothing is shown — Conf.none would be a claim too.
              if (!latest.isEmpty) ConfDots(ConfX.of(latest), size: 6),
            ]),
        if (behind != null && behind > 0) ...[
          const SizedBox(height: S.x1),
          Text(
              behind == 1
                  ? 'Measured yesterday, not today'
                  : 'Measured $behind days ago, not today',
              style: F.cap.copyWith(color: p.ink3)),
        ],
        if (delta != null) ...[
          const SizedBox(height: S.x2),
          Row(children: [
            Icon(
                delta >= 0
                    ? LucideIcons.arrowUpRight
                    : LucideIcons.arrowDownRight,
                size: 15,
                color: p.on(good ? C.green : C.orange)),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                '${_fmt(spec, delta.abs())} ${delta >= 0 ? 'above' : 'below'} '
                'your ${prior.length}-day average',
                style: F.cap.copyWith(color: p.on(good ? C.green : C.orange)),
              ),
            ),
          ]),
        ],
        const SizedBox(height: S.x5),
        Builder(builder: (c) {
          // One axis, shared by the labels and the curve. `min` unit metrics
          // print `7h 30m` on the gridlines rather than `450`.
          final axis = AxisSpec.of(vals,
              ticks: 3,
              format: spec.unit == 'min'
                  ? axisHm
                  : (spec.unit == 'steps' || spec.unit == 'kcal'
                      ? (v) => thousands(v)
                      : (vals.every((v) => v.abs() >= 10)
                          ? axisInt
                          : axisFixed)),
              floor: spec.unit == '%' ? 0 : null);
          return ChartFrame(
            title: spec.title,
            unit: spec.unit.isEmpty ? 'score' : spec.unit,
            height: 150,
            yAxis: axis,
            // The window IS the span now: `series` has one slot per calendar
            // day whether or not that day derived, so both edges are dates
            // rather than array positions. It used to read the length of a
            // compacted list, which meant a chart spanning two months labelled
            // its left edge "30 days ago".
            xLabels: [
              '${series.length} day${series.length == 1 ? '' : 's'} ago',
              'Today',
            ],
            // The dots are already beside the big number two rows up; twice on
            // one card reads as two different claims.
            series: series,
            child: CustomPaint(
              size: Size.infinite,
              // Fill only when the axis genuinely starts at zero. Shaded to a
              // baseline of 52 bpm, a 52→60 week reads as a mountain — the
              // truncated-axis form with the truncation hidden.
              painter: LineChart(series, p.on(spec.color),
                  fill: axis?.min == 0,
                  dots: series.length <= 40,
                  t: animate(c, 1),
                  dotInk: p.card,
                  axis: axis),
            ),
          );
        }),
      ]),
    );
  }

  Widget _range3(BuildContext c, MetricSpec spec, List<double> win,
      Map<String, dynamic>? pct) {
    final p = P.of(c);
    final sorted = [...win]..sort();
    final lo = sorted.first, hi = sorted.last;
    final mid = sorted[sorted.length ~/ 2];
    final band = pct?['label']?.toString();
    final rank = (pct?['percentile_of_you'] as num?);

    return Surface(
      child: Column(children: [
        Row(children: [
          Expanded(child: _stat(p, _fmt(spec, lo), 'Lowest')),
          Expanded(child: _stat(p, _fmt(spec, mid), 'Typical')),
          Expanded(child: _stat(p, _fmt(spec, hi), 'Highest')),
        ]),
        const SizedBox(height: S.x4),
        Text(
          rank == null
              ? 'From ${win.length} of your own days. Never a population average.'
              : 'Today sits at the ${_ordinal(rank.round())} percentile of your '
                  'own history${band == null ? '' : ' — $band'}.',
          style: F.cap.copyWith(color: p.ink3, height: 1.5),
        ),
      ]),
    );
  }

  String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return '$n${const ['th', 'st', 'nd', 'rd'][n % 10 < 4 ? n % 10 : 0]}';
  }

  Widget _stat(P p, String v, String l) => Column(children: [
        Text(v, style: F.n24.copyWith(color: p.ink)),
        const SizedBox(height: 3),
        Text(l, style: F.over.copyWith(color: p.ink3)),
      ]);

  /// Journal ↔ metric rank correlations. These are ASSOCIATIONS in your own
  /// history, which is why the copy says "on days you logged" and never
  /// "because".
  Widget _movers(BuildContext c, List<Map<String, dynamic>> movers) {
    final p = P.of(c);
    final rows = movers.take(5).toList();
    return Column(children: [
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: p.line, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x3),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rows[i]['tag']?.toString() ?? '',
                            style: F.body.copyWith(color: p.ink)),
                        Text(
                            '${rows[i]['n_with'] ?? 0} days with · '
                            '${rows[i]['n_without'] ?? 0} without',
                            style: F.over.copyWith(color: p.ink3)),
                      ]),
                ),
                Text(
                  _signed(rows[i]['delta'] as num?, rows[i]['unit']?.toString()),
                  style: F.body.copyWith(
                      color: p.on(rows[i]['helped'] == true ? C.green : C.orange),
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: S.x3),
      Text(
          'These are patterns in your own logs, not causes. A day you tagged is '
          'different from a day you did not in more ways than the tag.',
          style: F.over.copyWith(color: p.ink3, height: 1.5)),
    ]);
  }

  String _signed(num? v, String? unit) {
    if (v == null) return '';
    final s = v.abs() >= 10 ? v.abs().round().toString() : v.abs().toStringAsFixed(1);
    return '${v >= 0 ? '+' : '−'}$s${unit == null || unit.isEmpty ? '' : ' $unit'}';
  }

  String _fmt(MetricSpec spec, double v) {
    if (spec.unit == 'min') return hm(v);
    if (spec.unit == 'steps' || spec.unit == 'kcal') return thousands(v);
    if (v.abs() >= 100) return v.round().toString();
    if (v.abs() >= 10) return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
    return v.toStringAsFixed(1);
  }
}

// ═══════════════════ shared detail chrome ═══════════════════

/// Every detail screen is the same frame: a back bar, then a scroll. Keeping it
/// in one function is the reason the back affordance is in the same place on
/// all of them.
Widget detailScaffold(BuildContext c, String title, List<Widget> body,
    {String sub = '', Widget? trailing}) {
  final p = P.of(c);
  return Scaffold(
    backgroundColor: p.bg,
    body: SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          child: NavBar(title,
              sub: sub,
              trailing: trailing,
              onBack: () => Navigator.of(c).maybePop()),
        ),
        Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x12),
              children: body),
        ),
      ]),
    ),
  );
}

/// The one door into density 3. Deliberately plain: it is a workbench entrance,
/// not a feature.
Widget investigateRow(BuildContext c, VoidCallback onTap) {
  final p = P.of(c);
  return Pressable(
    onTap: onTap,
    semanticLabel: 'Investigate: raw readings, method and sensor quality',
    child: Container(
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
      child: Row(children: [
        Icon(LucideIcons.cpu, size: 17, color: p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Investigate',
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            Text('Raw readings, method, sensor quality',
                style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
        Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
      ]),
    ),
  );
}

/// A two-column legend. Used by the hypnogram and the overnight stack.
class Legend extends StatelessWidget {
  final List<(String, Color)> items;
  const Legend(this.items, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Wrap(
      spacing: S.x4,
      runSpacing: S.x2,
      children: [
        for (final e in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: e.$2, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(e.$1, style: F.over.copyWith(color: p.ink2)),
          ]),
      ],
    );
  }
}

/// The mono table Investigate is built from — label left, value right, both in
/// a fixed-pitch face so columns line up and nothing pretends to be prose.
class MonoTable extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const MonoTable(this.title, this.rows, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // A row with nothing behind it is dropped, not dashed. On a workbench an
    // em-dash reads as "we tried and got nothing", which is indistinguishable
    // from "this metric does not apply to this night".
    final present = [for (final r in rows) if (r.$2 != '—' && r.$2.isNotEmpty) r];
    if (present.isEmpty) return const SizedBox.shrink();
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x3),
        for (final r in present)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(r.$1,
                        style: F.cap
                            .copyWith(color: p.ink3, fontFamily: 'Menlo')),
                  ),
                  const SizedBox(width: S.x3),
                  Flexible(
                    child: Text(r.$2,
                        textAlign: TextAlign.right,
                        style: F.cap.copyWith(
                            color: p.ink,
                            fontFamily: 'Menlo',
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
          ),
      ]),
    );
  }
}
