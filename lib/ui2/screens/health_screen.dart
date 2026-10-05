// TRENDS — one page. Each core metric is a row: its name, its average over
// the chosen range, a small line, and the newest reading. Tap a row for the
// full chart.
//
// Under the rows: anything the app noticed (the illness watch and the log of
// past findings), and naps on a day that had one. Nothing else lives here —
// today's numbers are on Today, and the night is on the Sleep screen.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../compute/findings.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'findings_log.dart';
import 'home_screen.dart';
import 'metric_detail.dart';
import 'readiness_detail.dart';

/// One trend row: the `getChart` key, what to call it, its unit, its colour,
/// and which way is good news.
class _Row {
  final String key, label, unit;
  final IconData icon;
  final Color color;
  final Rising rising;
  const _Row(
    this.key,
    this.label,
    this.unit,
    this.icon,
    this.color, [
    this.rising = Rising.neither,
  ]);
}

/// The metrics this page follows, in the order a person asks about them.
const _rows = <_Row>[
  _Row(
    'recovery',
    'Recovery',
    '',
    LucideIcons.batteryCharging,
    C.green,
    Rising.good,
  ),
  _Row('sleep', 'Sleep', 'min', LucideIcons.moon, C.sleep, Rising.good),
  _Row('hrv', 'HRV', 'ms', LucideIcons.activity, C.teal, Rising.good),
  _Row(
    'resting_hr',
    'Resting heart rate',
    'bpm',
    LucideIcons.heart,
    C.heart,
    Rising.bad,
  ),
  _Row('strain', 'Strain', '', LucideIcons.zap, C.strain),
  _Row('steps', 'Steps', 'steps', LucideIcons.footprints, C.steps),
  // Same dated walking contribution as maintenance, after run-step accounting.
  _Row('step_kcal', 'Step calories', 'kcal', LucideIcons.flame, C.green),
  _Row('resp_rate', 'Breathing rate', 'br/min', LucideIcons.wind, C.teal),
  _Row(
    'skin_temp',
    'Skin temperature',
    'SD',
    LucideIcons.thermometer,
    C.orange,
  ),
  _Row('wear', 'Wear time', 'min', LucideIcons.watch, C.indigo),
];

/// True when [resp] has a value on at least half of the nights in [sleep]
/// over the 30 days ending [now], and on at least one.
///
/// Breathing rate comes from beat-to-beat timing overnight and is withheld on
/// any night its 5-minute windows disagree, so on some wrists it is missing
/// most nights. A row that mostly says nothing is noise; readiness still uses
/// the nights it does measure.
bool breathingMeasuredOften(
  List<ChartPoint> sleep,
  List<ChartPoint> resp,
  DateTime now,
) {
  final since =
      DateTime(now.year, now.month, now.day - 29).millisecondsSinceEpoch ~/
      1000;
  final nights = sleep.where((p) => p.t >= since).length;
  final measured = resp.where((p) => p.t >= since).length;
  return measured > 0 && measured * 2 >= nights;
}

/// The ranges offered, in days.
const _windows = [7, 30, 90];
const _windowLabels = ['Week', 'Month', '3 months'];

class HealthData {
  final Map<String, dynamic> today;

  /// Timestamped. A row's window and its "newest reading" are both read off
  /// the points' own dates — `metric_series` has one row per DERIVED day, so
  /// the newest stored point can be days old.
  final Map<String, List<ChartPoint>> charts;

  /// The newest derived day's naps.
  final int? napMin;
  final int? napCount;
  final String napDay;

  /// Everything the app has noticed, newest first — see findings.dart.
  final List<Finding> findings;

  const HealthData({
    this.today = const {},
    this.charts = const {},
    this.napMin,
    this.napCount,
    this.napDay = '',
    this.findings = const [],
  });

  List<ChartPoint> points(String key) => charts[key] ?? const [];

  /// Whether the breathing-rate row earns its place: shown only when the last
  /// 30 days measured it on at least half of the nights slept.
  bool get breathingShown => breathingMeasuredOften(
    points('sleep'),
    points('resp_rate'),
    DateTime.now(),
  );

  /// Skin temperature earns a Trends row once 7 of the last 30 nights have a
  /// reading; before that its chart would be a handful of dots.
  bool get skinTempShown {
    final now = DateTime.now();
    final since =
        DateTime(now.year, now.month, now.day - 29).millisecondsSinceEpoch ~/
        1000;
    return points('skin_temp').where((p) => p.t >= since).length >= 7;
  }

  static Future<HealthData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final days = await repo.availableDays();

    final charts = <String, List<ChartPoint>>{};
    for (final r in _rows) {
      if (r.key == 'step_kcal') continue;
      charts[r.key] = pointsOf(await repo.getChart(r.key));
    }
    final movement = await stepCalorieModels(repo, charts['steps']!, days: 90);
    charts['step_kcal'] = movement.budget;
    charts['step_kcal_acsm'] = movement.acsm;

    String labelAt(int t) =>
        dayLabelOf(DateTime.fromMillisecondsSinceEpoch(t * 1000));
    final ready = {for (final p in charts['recovery']!) labelAt(p.t): p.v};
    final irregular = {
      for (final p in pointsOf(await repo.getChart('irregular_rhythm_flag')))
        if (p.v == 1) labelAt(p.t),
    };

    // The newest DERIVED day, not today: today has usually not derived yet.
    final napDay = days.isEmpty ? todayLabel() : days.first;
    Map<String, dynamic> naps;
    try {
      naps = await repo.getDayNaps(napDay);
    } catch (_) {
      naps = const {};
    }

    return HealthData(
      today: today,
      charts: charts,
      napMin: (naps['nap_min'] as num?)?.round(),
      napCount: (naps['naps'] as List?)?.length,
      napDay: napDay,
      findings: findingsHistory(cd, readiness: ready, irregularDays: irregular),
    );
  }
}

class HealthScreen extends StatefulWidget {
  /// Injected only by goldens and tests; production always loads.
  final HealthData? data;

  /// Which range to open on (index into week / month / 3 months).
  final int range;

  const HealthScreen({super.key, this.data, this.range = 0});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> with RevisionReload {
  late int _range = widget.range;
  HealthData? _d;
  bool _loading = true, _failed = false;

  @override
  void initState() {
    super.initState();
    _d = widget.data;
    if (widget.data != null) {
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  bool get revisionReloads => widget.data == null;

  @override
  void reload() => _load();

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final t = beginRead(#day);
    try {
      final d = await HealthData.load(repo);
      if (stillNewest(#day, t)) {
        setState(() => (_d = d, _loading = false, _failed = false));
      }
    } catch (_) {
      if (stillNewest(#day, t)) {
        setState(() => (_loading = false, _failed = true));
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = _d ?? const HealthData();
    final win = _windows[_range];
    final rows = [
      for (final r in _rows)
        if ((r.key != 'resp_rate' || d.breathingShown) &&
            (r.key != 'skin_temp' || d.skinTempShown))
          r,
    ];

    return RefreshIndicator(
      onRefresh: () => pullToRefresh(c, _load),
      child: ListView(
        padding: pad,
        children: [
          const ScreenTitle('Trends'),
          SubTabs(
            _windowLabels,
            _range,
            (i) => setState(() => _range = i),
            color: C.blue,
          ),
          const SizedBox(height: S.x4),
          if (_loading && _d == null)
            const Padding(
              padding: EdgeInsets.only(top: S.x8),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed && _d == null)
            StatusCard(
              'Trends could not be read',
              'Nothing was deleted. The read went wrong.',
              fix: l?.healthTryAgain ?? 'Try again',
              icon: LucideIcons.databaseZap,
              onFix: () {
                setState(() => (_loading = true, _failed = false));
                _load();
              },
            )
          else ...[
            Surface(
              pad: const EdgeInsets.symmetric(horizontal: S.x4),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) Divider(color: p.line, height: 1),
                    _trendRow(
                      c,
                      p,
                      rows[i],
                      d.points(rows[i].key),
                      win,
                      alternate: d.points('step_kcal_acsm'),
                    ),
                  ],
                ],
              ),
            ),
            ..._observations(c, d),
            // Naps moved into Sleep, beside the night they belong to.
          ],
        ],
      ),
    );
  }

  /// A value at the precision its unit carries. Skin temperature is a signed
  /// distance from the user's own nights, so it keeps its sign.
  String _fmt(_Row r, double v) => r.key == 'skin_temp'
      ? '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)}'
      : r.key == 'strain'
      ? v.toStringAsFixed(1)
      : r.key == 'recovery'
      ? v.round().toString()
      : metricValue(r.unit, v);

  Widget _trendRow(
    BuildContext c,
    P p,
    _Row r,
    List<ChartPoint> pts,
    int win, {
    List<ChartPoint> alternate = const [],
  }) {
    final dense = denseDays(pts, win);
    final vals = [for (final v in dense) ?v];
    // "7,559 steps" beside a row already called Steps says it twice.
    final unit = r.key == 'steps' ? '' : unitBeside(r.unit);
    final open = r.key == 'recovery'
        ? () => go(c, const ReadinessDetail())
        : () => go(c, MetricDetail(r.key));

    if (vals.isEmpty) {
      return Pressable(
        onTap: open,
        semanticLabel: '${r.label}, no data in this range',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Row(
            children: [
              Icon(r.icon, size: 18, color: p.ink3),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(r.label, style: F.body.copyWith(color: p.ink)),
              ),
              Text('No data yet', style: F.cap.copyWith(color: p.ink3)),
            ],
          ),
        ),
      );
    }

    if (r.key == 'step_kcal') {
      final secondary = denseDays(alternate, win);
      final paired = secondary.whereType<double>().toList();
      return Pressable(
        onTap: open,
        semanticLabel: 'Walking calorie estimates, open today and history',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(r.label, style: F.body.copyWith(color: p.ink)),
              const SizedBox(height: S.x2),
              CaloriePair(
                budget: vals.last,
                acsm: secondary.last,
                compact: true,
                note:
                    'Latest recorded day · active walking energy; runs excluded.',
              ),
              Text(
                'Average Budget ${_fmt(r, vals.reduce((a, b) => a + b) / vals.length)} · ACSM ${paired.length == vals.length ? _fmt(r, paired.reduce((a, b) => a + b) / paired.length) : "unavailable"} kcal over ${vals.length} days',
                style: F.over.copyWith(color: p.ink3),
              ),
            ],
          ),
        ),
      );
    }
    final mean = vals.reduce((a, b) => a + b) / vals.length;
    final latest = vals.last;
    return Pressable(
      onTap: open,
      semanticLabel:
          '${r.label}, latest ${_fmt(r, latest)} $unit, '
          'average ${_fmt(r, mean)} $unit over ${vals.length} days',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Icon(r.icon, size: 18, color: p.on(r.color)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.label,
                    style: F.body.copyWith(color: p.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Avg ${_fmt(r, mean)} $unit'.trim(),
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ],
              ),
            ),
            // One point is not a line; and at accessibility sizes the reading
            // gets the width instead.
            if (vals.length > 1 && !bigText(c)) ...[
              const SizedBox(width: S.x2),
              SizedBox(
                width: 72,
                height: 26,
                child: CustomPaint(
                  painter: LineChart(
                    dense,
                    p.on(r.color),
                    fill: false,
                    t: animate(c, 1),
                  ),
                ),
              ),
            ],
            const SizedBox(width: S.x3),
            Text(_fmt(r, latest), style: F.n17.copyWith(color: p.ink)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(unit, style: F.over.copyWith(color: p.ink3)),
            ],
          ],
        ),
      ),
    );
  }

  /// The illness watch when it is live, otherwise the newest past finding,
  /// with the full log one tap away. Nothing at all on an ordinary day with
  /// an empty log.
  List<Widget> _observations(BuildContext c, HealthData d) {
    final l = AppLocalizations.of(c);
    final illness = d.today['illness'];
    final state = illness is Map ? illness['state']?.toString() : null;
    final day = illness is Map ? illness['date']?.toString() : null;
    final dd = day == null ? null : DateTime.tryParse(day);
    final behind = dd == null ? null : calendarDaysBetween(dd, DateTime.now());

    // The watch reads nocturnal resting heart rate only, so the copy names
    // that one signal and no cause.
    final card = state == null || state == 'green'
        ? null
        : Observation(
            state == 'red'
                ? 'Several nights in a row are above your normal'
                : (behind == null || behind <= 0
                      ? 'Last night was above your normal'
                      : '${prettyDay(day)} was above your normal'),
            'Your sleeping heart rate has been running high.',
            advice:
                l?.healthIllnessAdvice ??
                'Worth noting if it continues past a couple of days.',
            onTap: () => go(c, const MetricDetail('resting_hr')),
          );
    if (card == null && d.findings.isEmpty) return const [];
    return [
      Section(
        'Noticed',
        card ??
            Surface(
              onTap: () => go(c, FindingsLog(d.findings)),
              child: FindingRow(d.findings.first),
            ),
        action: d.findings.isEmpty ? null : (l?.healthSeeAll ?? 'See all'),
        onAction: d.findings.isEmpty
            ? null
            : () => go(c, FindingsLog(d.findings)),
      ),
    ];
  }
}
