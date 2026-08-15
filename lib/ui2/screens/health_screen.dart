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

import '../../data/day_label.dart';
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

  /// Timestamped. The x axis and the "how old is this number" line are both
  /// read off the points' own dates — `metric_series` has one row per DERIVED
  /// day, so the newest stored point can be a week old.
  final Map<String, List<ChartPoint>> charts;

  /// Derived days INSIDE THE LAST 30 CALENDAR DAYS — see [load].
  final int daysWithData;
  final Metric need;

  /// Non-null when the cross-day rollup was withheld — see [staleInsightsCard].
  final Map<String, dynamic>? insightsStale;

  const HealthData({
    this.today = const {},
    this.insights = const {},
    this.profile = const {},
    this.charts = const {},
    this.daysWithData = 0,
    this.need = Metric.empty,
    this.insightsStale,
  });

  /// The stored points for [key].
  List<ChartPoint> points(String key) => charts[key] ?? const [];

  /// [days] slots ending today, `null` where nothing was derived — the shape
  /// every painter in this app takes.
  List<double?> spark(String key, int days) => denseDays(points(key), days);

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

    final charts = <String, List<ChartPoint>>{};
    for (final k in const [
      'resting_hr',
      'hrv',
      'sleep',
      'stress',
      'resp_rate',
    ]) {
      charts[k] = pointsOf(await repo.getChart(k));
    }

    final coach = cd['sleep_coach'];
    final needEnv = coach is Map ? coach['need'] : null;
    final needSec = envValue(needEnv)?['need_sec'] as num?;

    // The last 30 CALENDAR days, not the newest 30 rows. `availableDays()` is
    // unbounded — every derived day since install — so `daysWithData` was the
    // whole history and `.clamp(0, 30)` painted "30 of 30" for anyone past
    // their first month, however many days they had actually missed.
    // `DateTime(y, m, d - 29)` and not `subtract(Duration(days: 29))`: the
    // duration form lands at 23:00 the day before across a DST boundary.
    final n = DateTime.now();
    final from = dayLabelOf(DateTime(n.year, n.month, n.day - 29));

    return HealthData(
      today: today,
      insights: cd,
      profile: profile,
      charts: charts,
      daysWithData: days.where((d) => d.compareTo(from) >= 0).length,
      need: envMetric(needEnv, needSec == null ? null : needSec / 60,
          unit: 'min'),
      insightsStale: staleReasonOf(cd),
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
        String value, String unit, List<double?> spark, String metricKey,
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
          spark: spark,
          conf: ConfX.of(m),
          onTap: () => go(c, MetricDetail(metricKey))));
    }

    final rhr = d.daily('resting_hr');
    row(rhr, LucideIcons.heart, C.red, 'Resting heart rate', 'Overnight',
        rhr.value == null ? '' : '${rhr.value!.round()}', 'bpm',
        d.spark('resting_hr', 24), 'resting_hr',
        whyAbsent: 'Resting heart rate is read from sleep, and no night was '
            'scored.');

    final hrvMetric = d.hrv;
    row(hrvMetric, LucideIcons.activity, C.green, 'HRV', 'RMSSD, asleep',
        hrvMetric.value == null ? '' : '${hrvMetric.value!.round()}', 'ms',
        d.spark('hrv', 24), 'hrv',
        whyAbsent: 'Beat-to-beat intervals were not clean enough last night.');

    final sleepMin = d.sleepMin;
    row(sleepMin, LucideIcons.moon, C.blue, 'Sleep', 'Last night',
        hm(sleepMin.value), '', d.spark('sleep', 24), 'sleep',
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
            'Stress',
        stressScore == null ? '' : '${stressScore.round()}',
        // 0–100, and the scale has to be on the row. Wellness has always shown
        // it for the same number.
        '/100',
        d.spark('stress', 24),
        'stress',
        whyAbsent: 'No resting stretch long enough last night.');

    final respMetric = d.resp;
    row(respMetric, LucideIcons.wind, C.teal, 'Respiratory rate', 'Asleep',
        respMetric.value == null ? '' : respMetric.value!.toStringAsFixed(1),
        'br/min',
        d.spark('resp_rate', 24), 'resp_rate',
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
                'Energy estimates need it.',
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
                        // NO dots. Confidence is a statement about a
                        // measurement, and nothing measured this — the user
                        // typed it. Three green dots on a self-report is a
                        // claim we cannot make, and `Conf.none` beside a
                        // number the user knows to be right reads as a fault.
                        conf: null);
                  }),
                ),
                const SizedBox(height: S.x3),
                const StatusCard(
                  'No weight history',
                  'Only the current value is stored.',
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
    final stale = staleInsightsCard(d.insightsStale, syncOf(c));

    /// [against] is the number the card compares the latest reading TO. Pass it
    /// and the delta is measured against that; leave it null and the delta is
    /// measured against the trailing mean of what is stored.
    ///
    /// It exists because the sleep card used to caption itself "vs your 7h 45m
    /// need" while still subtracting the 28-day AVERAGE — so the arrow and the
    /// figure under it read as sleep debt and were not. One of the two had to
    /// become true; the debt is the more useful of the pair.
    Widget trend(String key, String label, String unit, Color col, Metric m,
        {bool higherBetter = true, double? against, String? againstLabel}) {
      final pts = d.points(key);
      // Statistics off the STORED values; the painter gets the dense window.
      final s = valuesOf(pts);
      if (s.isEmpty) {
        return StatusCard(
          'No $label trend yet',
          '0 days stored.',
          icon: LucideIcons.chartLine,
        );
      }
      final prior = s.length > 1
          ? s.sublist(s.length - 1 - (s.length - 1).clamp(0, 28), s.length - 1)
          : const <double>[];
      // "vs your 28-day average" printed from the SECOND stored value, over a
      // mean of one. The window has to say how many days it actually holds.
      final mean =
          prior.isEmpty ? null : prior.reduce((a, b) => a + b) / prior.length;
      final base = against ?? mean;
      final window = against != null
          ? (againstLabel ?? '')
          : 'vs your ${prior.length}-day average';
      final delta = base == null ? 0.0 : s.last - base;
      final win = denseDays(pts, 30);
      final metricKey = key == 'sleep' ? 'sleep' : key;
      // The hero number is the newest STORED point, which after a sync gap is
      // not today's. Say when it is from rather than let the card imply now.
      final behind = daysBehind(pts.last.t) ?? 0;
      final asOf = behind <= 0 ? '' : ' · as of ${axisDay(pts.last.t)}';
      return TrendCard(
        label,
        key == 'sleep' ? hm(s.last) : _short(s.last),
        key == 'sleep' ? '' : unit,
        base == null
            ? 'no baseline'
            : (key == 'sleep' ? hm(delta.abs()) : _short(delta.abs())),
        '${base == null ? 'first readings' : window}$asOf',
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
        // `need` here is `crossday.sleep_coach.need` — the COMPUTED need. It is
        // never `sleep.need_min`, which is a hardcoded 480.
        trend('sleep', 'Time asleep', '', C.blue, d.sleepMin,
            against: d.need.value!.toDouble(),
            againstLabel: 'vs your ${hm(d.need.value)} need'),

      // Chronotype, jetlag and regularity ALL come out of the cross-day
      // rollup. When it is withheld, the section says why rather than showing
      // the cold-start "it takes a few weeks" line, which would be a lie.
      if (stale != null)
        Section('Body clock', stale)
      else
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
                    'Compares your free nights against your working nights.',
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
            // Already windowed to the last 30 calendar days by `HealthData.load`
            // — the clamp is a floor for a bad count, not the window.
            d.daysWithData.clamp(0, 30),
            30,
            'Days with a derived record in the last 30 days',
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
            // NAME THE QUANTITY. This is `skin_temp_z` — standard deviations
            // from the user's own baseline. It printed signed and unitless
            // beside a heart rate in bpm, so it read as °C; and the sleep
            // scrub's "temperature" is a THIRD quantity again (raw ADC minus
            // that day's median), which is why neither may go unlabelled.
            'SD from your own nights',
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
          'No band recordings reached this day.',
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
          'Not calibrated against a thermometer, so no °C. Shown as distance '
          'from your own recent nights.',
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
    const days = 30;
    final pts = d.points('hrv');
    // The window is thirty CALENDAR nights, dense, ending last night. The list
    // used to be the newest thirty STORED nights, which after a sync gap could
    // span two months while both axis labels — counted off the array — claimed
    // it spanned thirty. Nights with no record are holes, not joined across.
    final win = denseDays(pts, days);
    final have = [for (final v in win) ?v];
    final axis = AxisSpec.of(have, ticks: 2);
    final p = P.of(c);
    return ChartFrame(
      title: 'RMSSD, ${have.length} of the last $days nights',
      unit: 'ms',
      height: 48,
      yAxis: axis,
      xLabels: have.length < 2
          ? const []
          : ['${days - 1} nights ago', 'Last night'],
      conf: ConfX.of(d.hrv),
      empty: have.length < 2
          ? const NoData(message: 'One night is not a trend yet')
          : null,
      series: win,
      child: CustomPaint(
        size: Size.infinite,
        painter: LineChart(win, p.on(C.green), t: animate(c, 1), axis: axis),
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
          // Flexible, and the qualifier wraps. This column sized to its natural
          // width, so a qualifier that names its quantity properly — "SD from
          // your own nights" rather than a bare, unitless "vs your own nights"
          // — pushed the row 11 pt past the card at 2x text.
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value, style: F.n17.copyWith(color: p.ink)),
              Text(unit,
                  textAlign: TextAlign.end,
                  style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
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
          'Nothing logged yet.',
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
        Text('Last panel ${lastDraw ?? ''} · logged by hand',
            style: F.over.copyWith(color: p.ink3)),
      ],
      const SizedBox(height: S.x4),
      BigButton('Add a result',
          icon: LucideIcons.plus,
          color: C.blue,
          soft: true,
          onTap: () => _addLab(c, l)),
      const SizedBox(height: S.x4),
      // The app never prints "abnormal" anywhere, so it does not need to say
      // it does not. What the user cannot know without being told is that the
      // range shown here is not the range their own lab used.
      Text('Ranges differ by lab. Use the one on your report.',
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
              // Unlabelled it announces only its current value — a marker
              // name, with no statement of what the field is.
              Semantics(
                label: 'Marker',
                child: DropdownButton<LabMarker>(
                  isExpanded: true,
                  value: marker,
                  items: [
                    for (final m in l.markers)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (m) => setLocal(() => marker = m ?? marker),
                ),
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
