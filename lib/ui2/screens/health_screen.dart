// HEALTH — observation-oriented. "What is happening, what is changing, is
// anything unusual?"
//
// Rows, not a wall of cards. A card is a claim that something deserves your
// attention; forty of them side by side is a claim about nothing. Overview is
// a list you scan, Trends is where change lives, Vitals is what the sensor
// measured, and Labs is what a laboratory measured — the only numbers in this
// app that are absolute.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../data/lab_catalogue.dart';
import '../../data/local_repository.dart';
import '../../models/metric.dart';
import '../profile/profile.dart';
import '../ui2.dart';
import 'circadian_detail.dart';
import 'home_screen.dart';
import 'investigate.dart';
import 'metric_detail.dart';
import 'sleep_detail.dart';

class HealthData {
  final Map<String, dynamic> today, insights, profile;
  final Map<String, List<double>> charts;
  final int daysWithData;
  final Metric need;

  const HealthData({
    this.today = const {},
    this.insights = const {},
    this.profile = const {},
    this.charts = const {},
    this.daysWithData = 0,
    this.need = Metric.empty,
  });

  Metric daily(String k) {
    final d = today['daily'];
    return metricOf(d is Map ? d[k] : null);
  }

  /// Every one of these is a real envelope from the pipeline. They are read in
  /// one place so Overview and Trends cannot disagree about the same night's
  /// confidence — which is exactly what happened while Trends passed none and
  /// took `TrendCard`'s `Conf.high` default.
  Metric get hrv {
    final b = today['hrv'];
    final rmssd = b is Map ? b['rmssd'] as num? : null;
    if (rmssd == null || b is! Map) return Metric.empty;
    return Metric.parse(
        {...b.cast<String, dynamic>(), 'value': rmssd, 'unit': 'ms'});
  }

  Metric get sleepMin {
    final b = today['sleep'];
    return metricOf(b is Map ? b['duration_min'] : null);
  }

  Metric get stress => metricOf(today['stress']);
  Metric get resp => metricOf(today['resp']);

  static Future<HealthData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final profile = await repo.getProfile();
    final days = await repo.availableDays();

    final charts = <String, List<double>>{};
    for (final k in const [
      'resting_hr',
      'hrv',
      'sleep',
      'stress',
      'resp_rate',
    ]) {
      charts[k] = seriesOf(await repo.getChart(k));
    }

    final coach = cd['sleep_coach'];
    final needEnv = coach is Map ? coach['need'] : null;
    final needSec = envValue(needEnv)?['need_sec'] as num?;

    return HealthData(
      today: today,
      insights: cd,
      profile: profile,
      charts: charts,
      daysWithData: days.length,
      need: envMetric(needEnv, needSec == null ? null : needSec / 60,
          unit: 'min'),
    );
  }
}

class VitalsData {
  final Map<String, dynamic> timeline, lungs, wear, hrv, night;
  const VitalsData({
    this.timeline = const {},
    this.lungs = const {},
    this.wear = const {},
    this.hrv = const {},
    this.night = const {},
  });

  static Future<VitalsData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    var day = (today['status'] as Map?)?['today_day']?.toString();
    final days = await repo.availableDays();
    if (days.isNotEmpty && (day == null || !days.contains(day))) day = days.first;
    if (day == null) return const VitalsData();
    return VitalsData(
      timeline: await repo.getDayTimeline(day),
      lungs: await repo.getDayLungs(day),
      wear: await repo.getDayWear(day),
      hrv: await repo.getDayHrv(day),
      night: await repo.getDaySleepV2(day),
    );
  }
}

class LabsData {
  final List<Map<String, dynamic>> results;
  final List<LabMarker> markers;
  const LabsData({this.results = const [], this.markers = const []});

  static Future<LabsData> load() async {
    final rows = await LocalDb.labResults();
    final defs = await LocalDb.labMarkerDefs();
    return LabsData(
      results: rows,
      markers: [
        ...kLabMarkers,
        for (final d in defs)
          if (!kLabMarkersByKey.containsKey(d['key']))
            LabMarker(
              key: d['key'].toString(),
              label: (d['label'] ?? d['key']).toString(),
              unit: (d['unit'] ?? '').toString(),
              category: LabCategory.blood,
              decimals: (d['decimals'] as num?)?.toInt() ?? 1,
              ranges: [
                if (d['ref_low'] is num && d['ref_high'] is num)
                  LabRefRange(
                      low: (d['ref_low'] as num).toDouble(),
                      high: (d['ref_high'] as num).toDouble()),
              ],
              custom: true,
            ),
      ],
    );
  }
}

class HealthScreen extends StatefulWidget {
  final HealthData? data;
  final VitalsData? vitals;
  final LabsData? labs;

  /// Which sub-tab to open on. Goldens use it; production always starts at 0.
  final int tab;

  const HealthScreen(
      {super.key, this.data, this.vitals, this.labs, this.tab = 0});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  static const _tabs = ['Overview', 'Trends', 'Vitals', 'Labs'];
  late int _tab = widget.tab;

  HealthData? _d;
  VitalsData? _v;
  LabsData? _l;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _d = widget.data;
    _v = widget.vitals;
    _l = widget.labs;
    if (widget.data != null) {
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
      final d = await HealthData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadVitals() async {
    final repo = repoOf(context);
    if (repo == null || _v != null) return;
    try {
      final v = await VitalsData.load(repo);
      if (mounted) setState(() => _v = v);
    } catch (_) {/* the tab renders its absent states */}
  }

  Future<void> _loadLabs() async {
    if (_l != null) return;
    try {
      final l = await LabsData.load();
      if (mounted) setState(() => _l = l);
    } catch (_) {/* the tab renders its absent states */}
  }

  void _select(int i) {
    setState(() => _tab = i);
    if (i == 2) _loadVitals();
    if (i == 3) _loadLabs();
  }

  @override
  Widget build(BuildContext c) {
    final d = _d ?? const HealthData();
    return ListView(padding: pad, children: [
      const ScreenTitle('Health'),
      SubTabs(_tabs, _tab, _select, color: C.blue),
      const SizedBox(height: S.x5),
      if (_loading && _d == null)
        const Padding(
          padding: EdgeInsets.only(top: S.x8),
          child: Center(child: CircularProgressIndicator()),
        )
      else
        switch (_tab) {
          0 => _overview(c, d),
          1 => _trends(c, d),
          2 => _vitals(c, d),
          _ => _labs(c),
        },
    ]);
  }

  // ─────────────── OVERVIEW ───────────────
  Widget _overview(BuildContext c, HealthData d) {
    final p = P.of(c);
    final rows = <Widget>[];
    final gaps = <Widget>[];

    void row(Metric m, IconData icon, Color col, String name, String sub,
        String value, String unit, List<double> spark, String metricKey,
        {String? whyAbsent}) {
      if (m.isEmpty) {
        final s = StatusCard.forMetric('No ${name.toLowerCase()}', m,
            why: whyAbsent ?? '');
        if (s != null) gaps.add(s);
        return;
      }
      rows.add(MetricRow(icon, col, name, value,
          sub: sub,
          unit: unit,
          spark: spark.length > 24 ? spark.sublist(spark.length - 24) : spark,
          conf: ConfX.of(m),
          onTap: () => go(c, MetricDetail(metricKey))));
    }

    final rhr = d.daily('resting_hr');
    row(rhr, LucideIcons.heart, C.red, 'Resting heart rate', 'Overnight',
        rhr.value == null ? '' : '${rhr.value!.round()}', 'bpm',
        d.charts['resting_hr'] ?? const [], 'resting_hr',
        whyAbsent: 'Resting heart rate is read from sleep, and no night was '
            'scored.');

    final hrvMetric = d.hrv;
    row(hrvMetric, LucideIcons.activity, C.green, 'HRV', 'RMSSD, asleep',
        hrvMetric.value == null ? '' : '${hrvMetric.value!.round()}', 'ms',
        d.charts['hrv'] ?? const [], 'hrv',
        whyAbsent: 'Beat-to-beat intervals were not clean enough last night.');

    final sleepMin = d.sleepMin;
    row(sleepMin, LucideIcons.moon, C.blue, 'Sleep', 'Last night',
        hm(sleepMin.value), '', d.charts['sleep'] ?? const [], 'sleep',
        whyAbsent: 'No sleep period long enough to score was recorded.');

    final stressBlock = d.today['stress'];
    final stressScore =
        stressBlock is Map ? (stressBlock['score'] as num?) : null;
    row(
        d.stress,
        LucideIcons.brain,
        C.purple,
        'Stress',
        (stressBlock is Map ? stressBlock['level']?.toString() : null) ??
            'Autonomic tension',
        stressScore == null ? '' : '${stressScore.round()}',
        // 0–100, and the scale has to be on the row. Wellness has always shown
        // it for the same number.
        '/100',
        d.charts['stress'] ?? const [],
        'stress',
        whyAbsent: 'No resting window long enough to read autonomic tension '
            'last night. There is deliberately no substitute number.');

    final respMetric = d.resp;
    row(respMetric, LucideIcons.wind, C.teal, 'Respiratory rate', 'Asleep',
        respMetric.value == null ? '' : respMetric.value!.toStringAsFixed(1),
        'br/min',
        d.charts['resp_rate'] ?? const [], 'resp_rate',
        whyAbsent: 'Breathing rate is recovered from beat timing during sleep.');

    final illness = d.today['illness'];
    final state = illness is Map ? illness['state']?.toString() : null;
    // The CUSUM watch runs on NOCTURNAL RESTING HEART RATE ALONE. The copy here
    // used to name skin temperature as a second firing signal; the detector has
    // never been given a temperature series. `z` is its own standardised
    // deviation, so the sentence can say how far out the night sat.
    final illnessZ = illness is Map ? (illness['z'] as num?) : null;
    final weight = (d.profile['weight_kg'] as num?);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rows.isNotEmpty)
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              rows[i],
            ],
          ]),
        ),
      for (final g in gaps) ...[const SizedBox(height: S.x3), g],

      // Illness watch — computed every rollup, read by nothing until now.
      if (state != null && state != 'green') ...[
        const SizedBox(height: S.x4),
        Observation(
          state == 'red'
              ? 'Several nights in a row are away from your normal'
              : 'Last night sat outside your normal range',
          'Your nocturnal resting heart rate is tracking above your own '
              'baseline${illnessZ == null ? '' : ', '
                  '${illnessZ.abs().toStringAsFixed(1)} standardised deviations '
                  '${illnessZ >= 0 ? 'above' : 'below'} it'}. This watch reads '
              'that one signal; it names a pattern, and it does not name a '
              'cause.',
          'Worth noting if it continues past a couple of days.',
        ),
      ],

      Section(
        'Body composition',
        weight == null
            ? StatusCard(
                'No weight recorded',
                'Weight is used to estimate energy expenditure, and none is '
                    'set on your profile.',
                fix: 'Add it in Profile',
                icon: LucideIcons.scale,
                onFix: () => go(c, const ProfileHome()),
              )
            : Column(children: [
                Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Builder(builder: (c) {
                    // Whatever the user chose two screens away in Settings —
                    // this row used to print kg regardless.
                    final u = unitsOf(c);
                    final (v, unit) = u == null
                        ? (weight.toStringAsFixed(1), 'kg')
                        : splitUnit(u.weight(weight));
                    return MetricRow(LucideIcons.scale, C.teal, 'Weight', v,
                        unit: unit,
                        sub: 'From your profile',
                        // A number the user typed in themselves is the one
                        // thing on this screen that is not an estimate.
                        conf: Conf.high);
                  }),
                ),
                const SizedBox(height: S.x3),
                const StatusCard(
                  'No weight history',
                  'Only one current value is stored, so there is no trend to '
                      'draw and no change to report.',
                  icon: LucideIcons.chartLine,
                ),
              ]),
      ),
    ]);
  }

  // ─────────────── TRENDS ───────────────
  Widget _trends(BuildContext c, HealthData d) {
    final p = P.of(c);
    final cd = d.insights;
    final chrono = envValue(cd['chronotype']) ?? const {};
    final sjl = envValue(cd['social_jetlag']) ?? const {};
    final reg = envValue(cd['regularity']) ?? const {};
    final sjlH = sjl['abs_hours'] as num?;
    final sri = reg['sri'] as num?;

    Widget trend(String key, String label, String unit, Color col, Metric m,
        {bool higherBetter = true, String window = 'vs your 28-day average'}) {
      final s = d.charts[key] ?? const [];
      if (s.isEmpty) {
        return StatusCard(
          'No $label trend yet',
          'One value is stored per day and none have been produced.',
          icon: LucideIcons.chartLine,
        );
      }
      final prior = s.length > 1
          ? s.sublist(s.length - 1 - (s.length - 1).clamp(0, 28), s.length - 1)
          : const <double>[];
      final base =
          prior.isEmpty ? null : prior.reduce((a, b) => a + b) / prior.length;
      final delta = base == null ? 0.0 : s.last - base;
      final win = s.length <= 30 ? s : s.sublist(s.length - 30);
      final metricKey = key == 'sleep' ? 'sleep' : key;
      return TrendCard(
        label,
        key == 'sleep' ? hm(s.last) : _short(s.last),
        key == 'sleep' ? '' : unit,
        base == null
            ? 'no baseline'
            : (key == 'sleep' ? hm(delta.abs()) : _short(delta.abs())),
        base == null ? 'first readings' : window,
        win,
        col,
        up: delta >= 0,
        good: (delta >= 0) == higherBetter,
        // The tier of the latest reading, not `TrendCard`'s `Conf.high`
        // default — every trend on this tab used to claim three dots.
        conf: ConfX.of(m),
        onTap: () => go(c, MetricDetail(metricKey)),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      trend('resting_hr', 'Resting heart rate', 'bpm', C.red,
          d.daily('resting_hr'),
          higherBetter: false),
      const SizedBox(height: S.x3),
      trend('hrv', 'HRV', 'ms', C.green, d.hrv),
      const SizedBox(height: S.x3),
      if (d.need.value == null)
        trend('sleep', 'Time asleep', '', C.blue, d.sleepMin)
      else
        trend('sleep', 'Time asleep', '', C.blue, d.sleepMin,
            window: 'vs your ${hm(d.need.value)} need'),

      Section(
        'Body clock',
        Surface(
          onTap: () => go(c, const CircadianDetail()),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Text('Chronotype, jetlag and regularity',
                    style: F.cap.copyWith(color: p.ink2)),
              ),
              Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
            ]),
            const SizedBox(height: S.x4),
            if (chrono.isEmpty && sjlH == null && sri == null)
              Text(
                  'Measured by comparing your free nights against your working '
                  'nights. It takes a few weeks of both.',
                  style: F.cap.copyWith(color: p.ink3, height: 1.5))
            else
              InlineMetrics([
                if (chrono['type_label'] != null)
                  ('CHRONOTYPE', chrono['type_label'].toString(), C.indigo),
                if (sjlH != null)
                  ('SOCIAL JETLAG', _hoursHm(sjlH), C.orange),
                if (sri != null)
                  ('REGULARITY', '${sri.round()} / 100', C.green),
              ]),
          ]),
        ),
        action: 'Explore',
        onAction: () => go(c, const CircadianDetail()),
      ),

      Section(
        'Consistency',
        Surface(
          child: Consistency(
            d.daysWithData.clamp(0, 30),
            30,
            'Days with a derived record in the last month',
            C.domHealth,
          ),
        ),
      ),
    ]);
  }

  String _short(double v) =>
      v.abs() >= 100 ? v.round().toString() : v.toStringAsFixed(1);

  String _hoursHm(num h) {
    final m = (h * 60).round();
    return m < 60 ? '${m}m' : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  // ─────────────── VITALS ───────────────
  Widget _vitals(BuildContext c, HealthData d) {
    final p = P.of(c);
    final v = _v;
    if (v == null) {
      return const Padding(
        padding: EdgeInsets.only(top: S.x8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final highs = v.timeline['highs'];
    num? high(String k) {
      final e = highs is Map ? highs[k] : null;
      return e is Map ? e['v'] as num? : null;
    }

    final lo = high('low_hr'), hi = high('peak_hr');
    final respBlock = v.lungs['resp'];
    final resp = respBlock is Map ? respBlock['value'] as num? : null;
    final worn = v.wear['worn_min'] as num?;
    final coverage = v.wear['coverage_pct'] as num?;
    final skinTemp = metricOf(d.today['skin_temp']);
    final rmssd = v.hrv['rmssd'] as num?;
    final night = v.night;

    final rows = <Widget>[
      // HR extremes and wear minutes are the recording itself — the min and max
      // of the stored series, and the count of stored minutes. No estimator
      // stands behind them, so there is no envelope to read and no tier to
      // borrow; they are measurements. Everything below them reads its own.
      if (lo != null && hi != null)
        _vital(p, LucideIcons.heart, C.red, 'Heart rate',
            '${lo.round()} – ${hi.round()}', 'bpm today', Conf.high),
      if (resp != null)
        _vital(p, LucideIcons.wind, C.teal, 'Respiratory rate',
            resp.toStringAsFixed(1), 'breaths / min',
            ConfX.of(metricOf(respBlock))),
      if (skinTemp.value != null)
        _vital(
            p,
            LucideIcons.thermometer,
            C.orange,
            'Skin temperature deviation',
            '${skinTemp.value! >= 0 ? '+' : '−'}'
                '${skinTemp.value!.abs().toStringAsFixed(2)}',
            'vs your own nights',
            ConfX.of(skinTemp)),
      if (worn != null)
        _vital(p, LucideIcons.watch, C.green, 'Wear time', hm(worn),
            // `83.33333333333333% of the day` shipped. It is a percentage.
            coverage == null ? 'today' : '${coverage.round()}% of the day',
            Conf.high),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Measured continuously while the band is on your wrist.',
          style: F.cap.copyWith(color: p.ink3)),
      const SizedBox(height: S.x4),
      if (rows.isEmpty)
        StatusCard(
          'Nothing measured for this day',
          'Vitals come from the band\'s own recordings, and none reached this '
              'day.',
          fix: syncOf(c) == null ? '' : 'Sync the band',
          icon: LucideIcons.watch,
          onFix: syncOf(c),
        )
      else
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              rows[i],
            ],
          ]),
        ),

      if (skinTemp.value != null) ...[
        const SizedBox(height: S.x4),
        StatusCard(
          'Skin temperature is relative, not a temperature',
          'This sensor is not calibrated against a thermometer, so there is no '
              'honest way to print a °C figure. What is shown is how far last '
              'night sits from your own recent nights.',
          fix: 'How this is computed',
          icon: LucideIcons.thermometer,
          onFix: () => go(c, const MetricDetail('skin_temp')),
        ),
      ],

      Section(
        'Deep dives',
        Column(children: [
          if (rmssd != null)
            DeepDiveCard('Heart rate variability', '${rmssd.round()}', 'ms',
                'Time, frequency and non-linear', C.green,
                preview: _hrvPreview(c, d),
                onTap: () => go(c, const Investigate('hrv'))),
          if (rmssd != null) const SizedBox(height: S.x3),
          if (night['duration_min'] is num)
            DeepDiveCard('Sleep architecture', hm(night['duration_min'] as num),
                '', 'Explore the night', C.blue,
                onTap: () => go(c, const SleepDetail())),
        ]),
      ),
    ]);
  }

  /// The HRV preview inside the deep-dive card. Framed like every other chart:
  /// what it is, what it is measured in, what the heights mean, and how far
  /// back it reaches — all read off the series actually drawn.
  Widget _hrvPreview(BuildContext c, HealthData d) {
    final all = d.charts['hrv'] ?? const <double>[];
    final s = all.length > 30 ? all.sublist(all.length - 30) : all;
    final axis = AxisSpec.of(s, ticks: 2);
    return ChartFrame(
      title: 'RMSSD, last ${s.length} night${s.length == 1 ? '' : 's'}',
      unit: 'ms',
      height: 48,
      yAxis: axis,
      xLabels: s.length < 2
          ? const []
          : ['${s.length} nights ago', 'Last night'],
      conf: ConfX.of(d.hrv),
      empty: s.length < 2
          ? const NoData(message: 'One night is not a trend yet')
          : null,
      child: CustomPaint(
        size: Size.infinite,
        painter: LineChart(s, C.green, t: animate(c, 1), axis: axis),
      ),
    );
  }

  Widget _vital(P p, IconData i, Color col, String name, String value,
          String unit, Conf conf) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Icon(i, size: 18, color: p.on(col)),
          const SizedBox(width: S.x3),
          Expanded(child: Text(name, style: F.body.copyWith(color: p.ink))),
          const SizedBox(width: S.x2),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value,
                style: F.n17.copyWith(color: p.ink)),
            Text(unit, style: F.over.copyWith(color: p.ink3)),
          ]),
          const SizedBox(width: S.x3),
          ConfDots(conf),
        ]),
      );

  // ─────────────── LABS ───────────────
  Widget _labs(BuildContext c) {
    final p = P.of(c);
    final l = _l;
    if (l == null) {
      return const Padding(
        padding: EdgeInsets.only(top: S.x8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final sex = (_d?.profile['sex'])?.toString();
    // Newest draw per marker. `labResults` is already taken_on DESC.
    final latest = <String, Map<String, dynamic>>{};
    for (final r in l.results) {
      latest.putIfAbsent(r['marker'].toString(), () => r);
    }
    final byKey = {for (final m in l.markers) m.key: m};
    // A stored result with no number is not a measurement — it is dropped, the
    // way MonoTable drops an empty row. A bare em-dash in a lab column reads as
    // "the assay failed", which is a claim about your blood.
    final rows = latest.values.where((r) => r['value'] is num).toList()
      ..sort((a, b) => (byKey[a['marker']]?.label ?? '')
          .compareTo(byKey[b['marker']]?.label ?? ''));
    final lastDraw = l.results.isEmpty ? null : l.results.first['taken_on'];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rows.isEmpty)
        const StatusCard(
          'No lab results yet',
          'Blood work is the only absolute measurement in this app — a '
              'laboratory calibrates against a standard, and a wrist sensor '
              'does not. Nothing has been entered.',
          icon: LucideIcons.testTube,
        )
      else ...[
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              _lab(p, byKey[rows[i]['marker'].toString()], rows[i], sex),
            ],
          ]),
        ),
        const SizedBox(height: S.x3),
        Text('Last panel ${lastDraw ?? ''} · entered by hand',
            style: F.over.copyWith(color: p.ink3)),
      ],
      const SizedBox(height: S.x4),
      BigButton('Add a result',
          icon: LucideIcons.plus,
          color: C.blue,
          soft: true,
          onTap: () => _addLab(c, l)),
      const SizedBox(height: S.x4),
      Text(
          'Every laboratory publishes its own reference interval, from its own '
          'assay and its own local population. The range on your own report is '
          'the one that applies to you — a value outside the one shown here is '
          '"outside the typical range", not "abnormal".',
          style: F.over.copyWith(color: p.ink3, height: 1.6)),
    ]);
  }

  Widget _lab(P p, LabMarker? m, Map<String, dynamic> r, String? sex) {
    final v = (r['value'] as num?)?.toDouble();
    final unit = (r['unit'] ?? m?.unit ?? '').toString();
    final range = m?.rangeFor(sex);
    final inRange = v == null || m == null ? null : m.inRange(v, sex: sex);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            // No interval means NO OPINION — a grey dot, never a green one.
            color: inRange == null
                ? p.ink3
                : (inRange ? p.on(C.green) : p.on(C.orange)),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m?.label ?? r['marker'].toString(),
                style: F.body.copyWith(color: p.ink)),
            Text(
                range == null
                    ? 'No reference interval · ${r['taken_on']}'
                    : 'Typical ${_num(range.low)}–${_num(range.high)} · '
                        '${r['taken_on']}',
                style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
        const SizedBox(width: S.x2),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(v == null ? '' : (m?.format(v) ?? v.toString()),
                  style: F.n17.copyWith(
                      color: inRange == false ? p.on(C.orange) : p.ink)),
              const SizedBox(width: 3),
              Text(unit, style: F.over.copyWith(color: p.ink3)),
            ]),
      ]),
    );
  }

  String _num(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  /// Deliberately plain. Entering blood work is a rare, careful act; it does
  /// not need a designed flow, it needs the marker, the number and the date.
  Future<void> _addLab(BuildContext c, LabsData l) async {
    var marker = l.markers.first;
    final value = TextEditingController();
    final now = DateTime.now();
    final takenOn = TextEditingController(
        text: '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}');

    final ok = await showDialog<bool>(
      context: c,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setLocal) => AlertDialog(
          title: const Text('Add a result'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<LabMarker>(
                isExpanded: true,
                value: marker,
                items: [
                  for (final m in l.markers)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) => setLocal(() => marker = m ?? marker),
              ),
              TextField(
                controller: value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Value (${marker.unit})'),
              ),
              TextField(
                controller: takenOn,
                decoration:
                    const InputDecoration(labelText: 'Date drawn (YYYY-MM-DD)'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dc).pop(false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.of(dc).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final v = double.tryParse(value.text.trim());
    final date = takenOn.text.trim();
    if (v == null || DateTime.tryParse(date) == null) return;
    await LocalDb.putLabResult(
      marker: marker.key,
      takenOn: date,
      value: v,
      unit: marker.unit,
    );
    _l = null;
    await _loadLabs();
  }
}
