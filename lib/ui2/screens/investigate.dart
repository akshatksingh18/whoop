// INVESTIGATE — density 3 of 3.
//
// The workbench. Everything the pipeline actually produced for one metric, in
// fixed pitch, with the method and its citation underneath. Nothing here is
// styled to reassure: a number that is absent is absent, and a number that is
// relative says so on its own row.
//
// There is no "advanced mode" toggle anywhere in this app. This screen is
// reached by walking here, which is the same thing without a setting to
// forget.

import 'dart:convert' show jsonDecode;
import 'dart:math' show sqrt;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'metric_detail.dart';

class InvestigateData {
  final String? day;
  final int? algoVersion;

  /// Where this day came from — `null` when the bundle was derived on this
  /// device from band records, otherwise the importer that wrote it.
  final String? importedFrom;
  final Map<String, dynamic> hrv; // getDayHrv
  final Map<String, dynamic> heart; // getDayHeart

  /// `respiration.cvhr_apnea` — the whole envelope, because the note is the
  /// difference between a screen that abstained and a screen that ran and
  /// counted nothing.
  final Object? cvhr;

  /// The stored `prsa_dc` series, dated. Deceleration capacity is the one
  /// HRV-family number with hard outcome evidence behind it and its only
  /// reader was a single row in the table below.
  final List<ChartPoint> dcPoints;

  /// The stored `irregular_rhythm_flag` series (1/0 per DERIVED day). A day
  /// with no row and a day the screen abstained are the same absence here, and
  /// nothing downstream guesses which.
  final List<ChartPoint> rhythmPoints;
  final int? coveragePct;
  final int? windowStart, windowEnd;
  final List<double> series;

  const InvestigateData({
    this.day,
    this.algoVersion,
    this.importedFrom,
    this.hrv = const {},
    this.heart = const {},
    this.cvhr,
    this.dcPoints = const [],
    this.rhythmPoints = const [],
    this.coveragePct,
    this.windowStart,
    this.windowEnd,
    this.series = const [],
  });

  static Future<InvestigateData> load(LocalRepository repo, String key) async {
    final today = await repo.getToday();
    var day = (today['status'] as Map?)?['today_day']?.toString();
    final days = await repo.availableDays();
    if (days.isNotEmpty && (day == null || !days.contains(day))) day = days.first;
    if (day == null) return const InvestigateData();

    final spec = specOf(key);
    final hrv = await repo.getDayHrv(day);
    final heart = await repo.getDayHeart(day);
    final wear = await repo.getDayWear(day);
    final lungs = await repo.getDayLungs(day);
    final row = await LocalDb.dayResult(day);
    final win = lungs['sleep_window'];
    final series =
        spec.suppress != null ? const <double>[] : seriesOf(await repo.getChart(spec.chartKey));
    final hrvish = key == 'hrv' || key == 'rmssd_whole';
    final dc = hrvish
        ? pointsOf(await repo.getChart('prsa_dc'))
        : const <ChartPoint>[];
    final rhythm = hrvish
        ? pointsOf(await repo.getChart('irregular_rhythm_flag'))
        : const <ChartPoint>[];

    // An imported day says so. `imported`/`source` are written by the importers
    // onto the bundle itself; a day derived here has neither.
    String? importedFrom;
    final payload = row?['payload_json'];
    if (payload is String && payload.contains('"imported"')) {
      final b = jsonDecode(payload);
      if (b is Map && b['imported'] == true) {
        importedFrom = b['source']?.toString() ?? 'an import';
      }
    }

    return InvestigateData(
      day: day,
      algoVersion: (row?['algo_version'] as num?)?.toInt(),
      importedFrom: importedFrom,
      hrv: hrv,
      heart: heart,
      cvhr: lungs['cvhr'],
      dcPoints: dc,
      rhythmPoints: rhythm,
      coveragePct: (wear['coverage_pct'] as num?)?.toInt(),
      windowStart: win is Map ? (win['start'] as num?)?.toInt() : null,
      windowEnd: win is Map ? (win['end'] as num?)?.toInt() : null,
      series: series,
    );
  }
}

class Investigate extends StatefulWidget {
  final String metricKey;
  final InvestigateData? data;
  const Investigate(this.metricKey, {super.key, this.data});

  @override
  State<Investigate> createState() => _InvestigateState();
}

class _InvestigateState extends State<Investigate> {
  InvestigateData? _d;
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
      final d = await InvestigateData.load(repo, widget.metricKey);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final spec = specOf(widget.metricKey);
    final d = _d ?? const InvestigateData();
    final hrvish = widget.metricKey == 'hrv' || widget.metricKey == 'rmssd_whole';

    return detailScaffold(c, spec.title, sub: 'INVESTIGATE', [
      if (_loading) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else ...[
        if (hrvish) ..._hrvPanels(c, d) else ..._genericPanels(c, spec, d),
        if (widget.metricKey == 'resp_rate') ..._cvhrPanels(d),
        const SizedBox(height: S.x3),
        MonoTable('Provenance', [
          ('Day', d.day ?? '—'),
          ('Coverage', d.coveragePct == null ? '—' : '${d.coveragePct} %'),
          if (d.windowStart != null)
            ('Sleep window',
                '${clockOfTs(d.windowStart)} – ${clockOfTs(d.windowEnd)}'),
          // Asserted as "wrist optical · this device" for every day, including
          // days that were read out of somebody else's export.
          ('Source',
              d.importedFrom == null
                  ? 'Band records · derived on this phone'
                  : 'Imported · ${d.importedFrom}'),
          ('Algorithm version',
              d.algoVersion == null ? '—' : 'v${d.algoVersion}'),
        ]),
        const SizedBox(height: S.x5),
        _method(c, spec),
      ],
    ]);
  }

  // ── HRV: time, frequency, non-linear ──
  List<Widget> _hrvPanels(BuildContext c, InvestigateData d) {
    final time = envValue(d.hrv['hrv_time']) ?? const {};
    final freq = envValue(d.hrv['hrv_freq']) ?? const {};
    final freqNote = metricOf(d.hrv['hrv_freq']).note;
    // TWO DIFFERENT SHAPES, and this file read both as the same one. The
    // sleep-window screen is a PLAIN map (`sd1`, `sd2`, `flag`, `confidence`);
    // the 24-hour screen is an envelope whose `.value` carries the full set
    // (`sd1_ms`, `sd2_ms`, `sd1_sd2`, `pnn_pct`, `n_beats`). Reading the first
    // through `envValue` returned nothing, so every Poincaré row on this
    // screen has been silently empty.
    final irr = d.heart['irregular'] is Map
        ? (d.heart['irregular'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final irr24 = envValue(d.heart['irregular_24h']) ?? const {};
    final dc = envValue(d.hrv['prsa_dc']) ?? const {};
    final ac = envValue(d.hrv['prsa_ac']) ?? const {};
    final hrvBlock = d.heart['hrv'];
    final cv = hrvBlock is Map ? metricOf(hrvBlock['cv']).value : null;

    // A real minus sign, not a hyphen: acceleration capacity is negative by
    // definition and a hyphen in a numeric column reads as a dash.
    String fx(num v, int dp) => v.toStringAsFixed(dp).replaceFirst('-', '\u2212');
    String ms(Object? v) => v is num ? '${fx(v, 1)} ms' : '—';
    String ms2(Object? v) => v is num ? '${fx(v, 1)} ms\u00b2' : '—';
    String pct(Object? v) => v is num ? '${fx(v, 1)} %' : '—';
    String plain(Object? v) => v is num ? fx(v, 2) : '—';

    final beats = time['n_beats'] ?? irr['n_beats'] ?? irr24['n_beats'];

    return [
      MonoTable('Time domain', [
        ('RMSSD', ms(time['rmssd_ms'] ?? d.hrv['rmssd'])),
        ('SDNN', ms(time['sdnn_ms'] ?? d.hrv['sdnn'])),
        ('SDANN', ms(time['sdann_ms'])),
        ('SDNN index', ms(time['sdnn_index_ms'])),
        ('pNN50', pct(time['pnn50_pct'])),
        ('ln RMSSD', plain(d.hrv['ln_rmssd'])),
        ('Your baseline RMSSD', ms(d.hrv['baseline'])),
        ('Stability (CV)', pct(cv)),
      ]),
      const SizedBox(height: S.x3),
      // ms² is correct AGAIN: `lombScargle` now returns physical PSD (ms²/Hz)
      // and the bands are Welch-averaged, verified against a synthetic at
      // total 652.1 vs SDNN² 651.0. It previously returned variance-normalised
      // power, so the same label sat over numbers three orders of magnitude
      // small. Every row here self-drops when its key is absent — ULF and a
      // too-short session now return null rather than a fabricated zero, and
      // MonoTable removes the row rather than dashing it.
      MonoTable('Frequency domain', [
        ('ULF power', ms2(freq['ulf'])),
        ('VLF power', ms2(freq['vlf'])),
        ('LF power', ms2(freq['lf'])),
        ('HF power', ms2(freq['hf'])),
        ('Total power', ms2(freq['total'])),
        ('LF / HF', plain(freq['lf_hf'])),
        ('LF, normalised', plain(freq['nu_lf'])),
        ('HF, normalised', plain(freq['nu_hf'])),
        // An ABSENT spectrum is not an ungated one. `envValue` returns null for
        // an absent envelope, so `== true ? : 'no'` collapsed "never computed"
        // into a confident negative — and it left a one-row table reading
        // "HF gated no" directly above the card saying there is no spectrum.
        ('HF gated', freq['hf_gated'] == null
            ? '—'
            : (freq['hf_gated'] == true ? 'yes' : 'no')),
      ]),
      const SizedBox(height: S.x3),
      if (freq['total'] == null)
        StatusCard(
          'No frequency-domain spectrum for this night',
          // THE ESTIMATOR'S OWN REASON. `total` goes null for three different
          // reasons and the envelope note distinguishes them; "too short" was
          // printed for all three, so a full 8 h night that failed the artifact
          // gate sent the user to look at their sleep duration instead of
          // their strap fit — contradicting the "HF gated yes" row above it.
          freqNote?.isNotEmpty == true
              ? freqNote!
              : 'The recording was too short to resolve the bands.',
        ),
      const SizedBox(height: S.x3),
      MonoTable('Non-linear', [
        ('SD1, sleep', ms(irr['sd1'])),
        ('SD2, sleep', ms(irr['sd2'])),
        ('SD1, 24 h', ms(irr24['sd1_ms'])),
        ('SD2, 24 h', ms(irr24['sd2_ms'])),
        ('SD1 / SD2, 24 h', plain(irr24['sd1_sd2'])),
        // The screen's own threshold, stated rather than baked into a label
        // the stored key cannot confirm.
        ('Successive intervals over 70 ms', pct(irr24['pnn_pct'])),
        // A screen that never RAN is not a screen that ran and found nothing.
        // `irregularBeatScreen` abstains below 500 clean beats or over 30%
        // artifact — the common case for a barely-worn day — and both rows
        // printed "clear" for it, i.e. a negative arrhythmia screen for a day
        // the screen was explicitly suppressed. MonoTable drops the em-dash.
        ('Irregular-rhythm flag, sleep',
            irr['flag'] == null ? '—' : (irr['flag'] == true ? 'raised' : 'clear')),
        ('Irregular-rhythm flag, 24 h',
            irr24['flag'] == null ? '—' : (irr24['flag'] == true ? 'raised' : 'clear')),
        ('Deceleration capacity', ms(dc['capacity_ms'])),
        ('Acceleration capacity', ms(ac['capacity_ms'])),
        ('DC anchors', dc['anchors'] == null ? '—' : thousands(dc['anchors'] as num)),
      ]),
      if (d.dcPoints.isNotEmpty) ...[
        const SizedBox(height: S.x3),
        _dcTrend(c, d, beats),
      ],
      if (d.rhythmPoints.isNotEmpty) ...[
        const SizedBox(height: S.x3),
        _rhythmStrip(c, d),
      ],
      const SizedBox(height: S.x3),
      // Beats analysed is the only MEASURED row this table ever had; the other
      // three were constants sitting under a heading that made them look
      // measured. They are in the method note at the bottom of the screen.
      MonoTable('Signal quality', [
        ('Beats analysed', beats == null ? '—' : thousands(beats as num)),
        ('Beats analysed, 24 h',
            irr24['n_beats'] == null ? '—' : thousands(irr24['n_beats'] as num)),
      ]),
    ];
  }

  /// CV-03 — deceleration capacity as a trend. UNCOLOURED, and that is the
  /// whole design: DC has real outcome evidence behind it (Bauer 2006) and the
  /// strata are ECG post-MI, while our beats are pulse arrivals. PRSA anchors
  /// on decelerations, and pulse-arrival jitter attenuates DC by an amount that
  /// varies with signal quality night to night — so a rising line can be a
  /// cleaner-signal line. No colour, no threshold, no reference range, ever.
  /// The beat count goes on the card because the artifact gate is load-bearing.
  Widget _dcTrend(BuildContext c, InvestigateData d, Object? beats) {
    final p = P.of(c);
    final win = denseDays(d.dcPoints, 30);
    final vals = [for (final v in win) ?v];
    final axis = AxisSpec.of(vals, ticks: 3, format: axisFixed);
    return Surface(
      child: ChartFrame(
        title: 'Deceleration capacity',
        unit: 'ms',
        height: 110,
        yAxis: axis,
        xLabels: const ['29 days ago', 'Today'],
        series: win,
        footnote: 'Your own nights only — no reference range, and none exists '
            'for pulse arrivals. Night-to-night signal quality moves this line '
            'on its own'
            '${beats is num ? ', and last night was ${thousands(beats)} beats' : ''}.',
        child: CustomPaint(
          size: Size.infinite,
          // p.ink3, not an accent. A colour here would be a verdict.
          painter: LineChart(win, p.ink3,
              fill: false, dots: true, dotInk: p.card, t: animate(c, 1),
              axis: axis),
        ),
      ),
    );
  }

  /// CV-10 — the irregular-rhythm SCREEN, night by night.
  ///
  /// Three states and they must look like three states: a filled square is a
  /// day the screen ran, darker when it raised its flag, and an OUTLINE is a
  /// day it did not run at all. `metric_series` stores one value per day, so a
  /// day with no record and a day the screen abstained on are the same absence
  /// — the copy says "did not run" and does not guess which.
  ///
  /// Screening, not detection. Wrist optical cannot separate an ectopic beat
  /// from a dropped beat from a motion artifact, so there is no percentage of
  /// abnormal beats here and no AF, PVC or ectopy vocabulary anywhere near it.
  /// The footnote is permanent, not a tooltip: a clear strip means nothing.
  Widget _rhythmStrip(BuildContext c, InvestigateData d) {
    final p = P.of(c);
    const weeks = 12;
    final grid = _weekGrid(d.rhythmPoints, weeks);
    final ran = d.rhythmPoints.length;
    final raised = d.rhythmPoints.where((e) => e.v >= 1).length;
    return Surface(
      child: ChartFrame(
        title: 'Irregular-rhythm screen',
        unit: 'one square per day',
        height: 96,
        xLabels: const ['12 weeks ago', 'This week'],
        legend: [('Screen ran', p.on(C.purple))],
        footnote: 'Ran on $ran day${ran == 1 ? '' : 's'}, raised its flag on '
            '$raised. An outlined square is a day it did not run. A clear '
            'strip is not a negative result: this is a screen on pulse '
            'timing, and it cannot tell an ectopic beat from a dropped beat '
            'from the band moving on your wrist.',
        child: CustomPaint(
          size: Size.infinite,
          painter: HeatMap(grid, p.on(C.purple), p.line),
        ),
      ),
    );
  }

  /// [pts] as calendar weeks — one column per week, Monday at the top, the last
  /// column being the week that contains today. `null` is a day with no stored
  /// value, which [HeatMap] draws as an outline rather than a fainter fill.
  static List<List<double?>> _weekGrid(List<ChartPoint> pts, int weeks) {
    final tail = 7 - DateTime.now().weekday; // days left in the current week
    final all = [
      ...denseDays(pts, weeks * 7 - tail),
      ...List<double?>.filled(tail, null),
    ];
    return [for (var w = 0; w < weeks; w++) all.sublist(w * 7, w * 7 + 7)];
  }

  // ── breathing-disturbance texture ──
  //
  // The screen already counted the cycles; it accumulated each one's depth and
  // width and threw everything but the two means away. The quartiles are the
  // shape those means hide: a night of a few deep dips and a night of many
  // shallow ones share a mean.
  //
  // Numbers, no adjectives, no interpretation, no category — and Investigate
  // only. Nothing here is a sleep-apnea finding and no copy anywhere near it
  // names a breathing disorder or a mechanism.
  List<Widget> _cvhrPanels(InvestigateData d) {
    final v = envValue(d.cvhr);
    final note = metricOf(d.cvhr).note;
    if (v == null) {
      // ABSTAINED, not "nothing found". The screen hard-gates on beat count and
      // artifact fraction, and zero cycles over six observed hours is a
      // different night from a screen that never ran.
      return [
        const SizedBox(height: S.x3),
        StatusCard(
          'The cycle screen did not run for this night',
          note?.isNotEmpty == true
              ? note!
              : 'Not enough clean beats to run it.',
          icon: LucideIcons.wind,
        ),
      ];
    }

    String q(Object? qs, String unit, int dp) {
      if (qs is! List || qs.length < 3) return '—';
      final xs = [for (final e in qs) if (e is num) e];
      if (xs.length < 3) return '—';
      return '${xs.map((e) => e.toStringAsFixed(dp)).join(' · ')} $unit';
    }

    final hours = v['analyzed_hours'] as num?;
    return [
      const SizedBox(height: S.x3),
      MonoTable('Heart-rate cycles', [
        ('Cycles counted', v['cycle_count'] == null
            ? '—'
            : thousands(v['cycle_count'] as num)),
        ('Observed hours analysed',
            hours == null ? '—' : '${hours.toStringAsFixed(2)} h'),
        ('Cycles per observed hour', v['cvhr_per_hour'] == null
            ? '—'
            : (v['cvhr_per_hour'] as num).toStringAsFixed(2)),
        ('Mean cycle length', v['mean_width_sec'] == null
            ? '—'
            : '${(v['mean_width_sec'] as num).toStringAsFixed(1)} s'),
        ('Mean dip depth', v['mean_depth_ms'] == null
            ? '—'
            : '${(v['mean_depth_ms'] as num).toStringAsFixed(1)} ms'),
        // p25 · p50 · p75 of the SAME per-cycle lists the means come from.
        ('Cycle length, quartiles', q(v['width_quartiles_sec'], 's', 1)),
        ('Dip depth, quartiles', q(v['depth_quartiles_ms'], 'ms', 1)),
      ]),
    ];
  }

  // ── anything else: what the series itself looks like ──
  List<Widget> _genericPanels(
      BuildContext c, MetricSpec spec, InvestigateData d) {
    if (spec.suppress != null) {
      return [
        StatusCard('Nothing computed for this key', spec.suppress!,
            icon: spec.icon),
      ];
    }
    final s = d.series;
    if (s.isEmpty) {
      return [
        StatusCard(
          'No stored series',
          'Nothing stored for ${spec.title.toLowerCase()} yet.',
          icon: spec.icon,
        ),
      ];
    }
    final sorted = [...s]..sort();
    final mean = s.reduce((a, b) => a + b) / s.length;
    final sd = s.length < 2
        ? 0.0
        : sqrt(s.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            (s.length - 1));
    String n(double v) => v.abs() >= 100
        ? v.round().toString()
        : v.toStringAsFixed(2);

    return [
      MonoTable('Series', [
        // DERIVED days, not calendar days. `metric_series` gets a row only on a
        // day that derives, so "Days stored 40" under "one value per calendar
        // day" read as 40 days of continuous coverage.
        ('Days derived', '${s.length}'),
        ('Latest', n(s.last)),
        ('Mean', n(mean)),
        ('Median', n(sorted[sorted.length ~/ 2])),
        ('SD', n(sd)),
        ('Min', n(sorted.first)),
        ('Max', n(sorted.last)),
        ('Unit', spec.unit.isEmpty ? 'unitless' : spec.unit),
        ('Storage', 'one value per derived day'),
      ]),
    ];
  }

  Widget _method(BuildContext c, MetricSpec spec) {
    final p = P.of(c);
    return Surface(
      elevation: 0,
      color: p.card2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('METHOD', style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x2),
        Text(spec.method.isEmpty ? 'Not documented.' : spec.method,
            style: F.cap.copyWith(color: p.ink2, height: 1.6)),
        if (spec.citation.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          Text(spec.citation,
              style: F.over.copyWith(color: p.ink3, fontFamily: 'Menlo')),
        ],
      ]),
    );
  }
}
