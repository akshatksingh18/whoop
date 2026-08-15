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
  final int? coveragePct;
  final int? windowStart, windowEnd;
  final List<double> series;

  const InvestigateData({
    this.day,
    this.algoVersion,
    this.importedFrom,
    this.hrv = const {},
    this.heart = const {},
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
                  ? 'Band records · derived on this device'
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
        ('HF gated', freq['hf_gated'] == true ? 'yes' : 'no'),
      ]),
      const SizedBox(height: S.x3),
      if (freq['total'] == null)
        const StatusCard(
          'No frequency-domain spectrum for this night',
          'The bands are Welch-averaged over segments long enough to resolve '
              'each one, so a short or broken recording returns nothing rather '
              'than a number computed off too few beats.',
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
        ('Irregular-rhythm flag, sleep', irr['flag'] == true ? 'raised' : 'clear'),
        ('Irregular-rhythm flag, 24 h', irr24['flag'] == true ? 'raised' : 'clear'),
        ('Deceleration capacity', ms(dc['capacity_ms'])),
        ('Acceleration capacity', ms(ac['capacity_ms'])),
        ('DC anchors', dc['anchors'] == null ? '—' : thousands(dc['anchors'] as num)),
      ]),
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
          'Nothing has been written for ${spec.title.toLowerCase()} yet, so '
              'there is nothing to take apart.',
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
        ('Days stored', '${s.length}'),
        ('Latest', n(s.last)),
        ('Mean', n(mean)),
        ('Median', n(sorted[sorted.length ~/ 2])),
        ('SD', n(sd)),
        ('Min', n(sorted.first)),
        ('Max', n(sorted.last)),
        ('Unit', spec.unit.isEmpty ? 'unitless' : spec.unit),
        ('Storage', 'one value per calendar day'),
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
