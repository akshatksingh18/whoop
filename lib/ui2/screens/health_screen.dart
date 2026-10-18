// TRENDS — one page. Each core metric is a row: its name, its average over
// the chosen range, a small line, and the newest reading. Tap a row for the
// full chart.
//
// Under the rows: anything the app noticed (the illness watch and the log of
// past findings), and naps on a day that had one. Nothing else lives here —
// today's numbers are on Today, and the night is on the Sleep screen.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../build_profile.dart';
import '../../compute/findings.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'findings_log.dart';
import 'home_screen.dart';
import 'metric_detail.dart';

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
/// Colours are the Build 88 families (DESIGN.md): recovery for HRV and heart
/// rate, sleep for breathing, body for steps, step calories and wear.
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
  _Row('hrv', 'HRV', 'ms', LucideIcons.activity, C.recovery, Rising.good),
  // The lowest 30-minute average while asleep, not an awake seated reading.
  _Row(
    'resting_hr',
    'Resting HR · asleep',
    'bpm',
    LucideIcons.heart,
    C.heart,
    Rising.bad,
  ),
  _Row('resp_rate', 'Breathing rate', 'br/min', LucideIcons.wind, C.sleep),
  _Row('strain', 'Strain', '', LucideIcons.zap, C.strain),
  _Row('steps', 'Steps', 'steps', LucideIcons.footprints, C.steps),
  // Same dated walking contribution as maintenance, after run-step accounting.
  _Row('step_kcal', 'Step calories', 'kcal', LucideIcons.flame, C.body),
  _Row(
    'skin_temp',
    'Skin temperature',
    'SD',
    LucideIcons.thermometer,
    C.orange,
  ),
  _Row('wear', 'Wear time', 'min', LucideIcons.watch, C.body),
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

/// The ranges offered, in days: the same list every metric screen uses.
const _windows = kRangeDays;
const _windowLabels = kRangeLabels;

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
    if (!kShowSkinTemp) return false;
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

  /// Which range to open on (index into [kRangeDays]); 7 days by default.
  final int range;

  const HealthScreen({super.key, this.data, this.range = 1});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> with RevisionReload {
  late int _range = widget.range;

  void _reselected() {
    if (shellReselect.value.$1 != ShellDomain.health || !mounted) return;
    if (_range != widget.range) setState(() => _range = widget.range);
  }

  @override
  void dispose() {
    shellReselect.removeListener(_reselected);
    super.dispose();
  }

  HealthData? _d;
  bool _loading = true, _failed = false;

  /// Build 90 (D5): up to three favourite metrics, shown first; the full
  /// list stays below, unchanged. Kept on this phone only.
  static const _pinKey = 'trends.pinned';
  static const _maxPinned = 3;
  List<String> _pinned = const [];

  Future<void> _loadPins() async {
    try {
      final v = (await SharedPreferences.getInstance()).getStringList(_pinKey);
      if (mounted && v != null) {
        setState(() => _pinned = v.take(_maxPinned).toList());
      }
    } catch (_) {}
  }

  Future<void> _savePins(List<String> v) async {
    setState(() => _pinned = v);
    try {
      await (await SharedPreferences.getInstance()).setStringList(_pinKey, v);
    } catch (_) {}
  }

  Future<void> _editPins(BuildContext c, List<_Row> shown) async {
    var picked = [..._pinned];
    // Build 94 (Codex N17): a pinned metric hidden by its coverage gate is
    // listed too, so its slot can be freed instead of filling one unseen.
    final hidden = [
      for (final r in _rows)
        if (_pinned.contains(r.key) && !shown.contains(r)) r,
    ];
    final rows = [...shown, ...hidden];
    String label(_Row r) =>
        hidden.contains(r) ? '${r.label} · not shown now' : r.label;
    await showModalBottomSheet<void>(
      context: c,
      useSafeArea: true,
      isScrollControlled: true,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (sc) => StatefulBuilder(
        builder: (sc, set) {
          final p = P.of(sc);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(S.x5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Pin up to three', style: F.head.copyWith(color: p.ink)),
                const SizedBox(height: S.x1),
                Text(
                  'Pinned metrics show first. Every metric stays in the list.',
                  style: F.cap.copyWith(color: p.ink2),
                ),
                const SizedBox(height: S.x3),
                for (final r in rows)
                  Pressable(
                    semanticLabel: picked.contains(r.key)
                        ? '${label(r)}, pinned'
                        : label(r),
                    onTap: () => set(() {
                      if (picked.contains(r.key)) {
                        picked.remove(r.key);
                      } else if (picked.length < _maxPinned) {
                        picked.add(r.key);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.x3),
                      child: Row(
                        children: [
                          Icon(
                            picked.contains(r.key)
                                ? LucideIcons.squareCheck
                                : LucideIcons.square,
                            size: 20,
                            color: picked.contains(r.key)
                                ? p.on(C.blue)
                                : p.ink3,
                          ),
                          const SizedBox(width: S.x3),
                          Expanded(
                            child: Text(
                              label(r),
                              style: F.body.copyWith(color: p.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: S.x3),
                BigButton(
                  'Done',
                  color: C.blue,
                  onTap: () => Navigator.of(sc).pop(),
                ),
              ],
            ),
          );
        },
      ),
    );
    await _savePins(picked);
  }

  /// "Oct 8 – 14" for the range ending today.
  String _dates(int win) {
    final t = DateTime.parse(todayLabel());
    final f = DateTime(t.year, t.month, t.day - (win - 1));
    return f.month == t.month
        ? '${formatShortDate(f)} – ${t.day}'
        : '${formatShortDate(f)} – ${formatShortDate(t)}';
  }

  @override
  void initState() {
    super.initState();
    _loadPins();
    shellReselect.addListener(_reselected);
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

    final pinControl = _d == null
        ? null
        : TextButton.icon(
            onPressed: () => _editPins(c, rows),
            icon: const Icon(LucideIcons.pin, size: 16),
            label: Text(
              _pinned.isEmpty ? 'Pin favourites' : 'Edit pins',
              style: F.cap.copyWith(color: p.on(C.blue)),
            ),
          );

    return RefreshIndicator(
      onRefresh: () => pullToRefresh(c, _load),
      child: ListView(
        padding: pad,
        children: [
          // Build 88 header (DESIGN.md): what the numbers are, above the title.
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x1, S.x3, S.x1, S.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Build 90: the range's real dates, not only its length.
                Text(
                  win == 1
                      ? 'Today'
                      // One line at 390 pt (Build 90 audit: the longer
                      // "daily averages, measured days only" wrapped).
                      : '${_dates(win)} · averages of measured days',
                  style: F.body.copyWith(color: p.onGround),
                ),
                if (bigText(c)) ...[
                  Text('Trends', style: F.display.copyWith(color: p.ink)),
                  if (pinControl != null)
                    Align(alignment: Alignment.centerRight, child: pinControl),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Trends',
                          style: F.display.copyWith(color: p.ink),
                        ),
                      ),
                      ?pinControl,
                    ],
                  ),
              ],
            ),
          ),
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
          else if (_failed)
            StatusCard(
              'Trends could not be read',
              _d == null
                  ? 'Try again to load your records.'
                  : 'Previous readings are still shown below.',
              fix: l?.healthTryAgain ?? 'Try again',
              icon: LucideIcons.databaseZap,
              onFix: () {
                setState(() => (_loading = true, _failed = false));
                _load();
              },
            ),
          if (_d != null) ...[
            if (rows.where((r) => _pinned.contains(r.key)).toList()
                case final pins when pins.isNotEmpty) ...[
              Section(
                'Pinned',
                Surface(
                  pad: const EdgeInsets.fromLTRB(S.x5, S.x2, S.x5, S.x2),
                  child: Column(
                    children: [
                      for (var i = 0; i < pins.length; i++) ...[
                        if (i > 0) Divider(color: p.line, height: 1),
                        _trendRow(
                          c,
                          p,
                          pins[i],
                          d.points(pins[i].key),
                          win,
                          alternate: d.points('step_kcal_acsm'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: S.x4),
            ],
            for (final group in const [
              ('Recovery and sleep', ['recovery', 'sleep']),
              ('Heart and breathing', ['hrv', 'resting_hr', 'resp_rate']),
              ('Activity and wear', ['strain', 'steps', 'step_kcal', 'wear']),
              ('Body', ['skin_temp']),
            ])
              if (rows
                      .where(
                        (r) =>
                            group.$2.contains(r.key) &&
                            !_pinned.contains(r.key),
                      )
                      .toList()
                  case final grouped when grouped.isNotEmpty) ...[
                Surface(
                  pad: const EdgeInsets.fromLTRB(S.x5, S.x4, S.x5, S.x2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        group.$1,
                        style: F.body.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      for (var i = 0; i < grouped.length; i++) ...[
                        if (i > 0) Divider(color: p.line, height: 1),
                        _trendRow(
                          c,
                          p,
                          grouped[i],
                          d.points(grouped[i].key),
                          win,
                          alternate: d.points('step_kcal_acsm'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: S.x3),
              ],
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
    // The range travels with the tap: a 3-month row opens the 3-month view.
    final range = _windows.indexOf(win);
    void open() => go(
      c,
      MetricDetail(r.key == 'recovery' ? 'readiness' : r.key, range: range),
    );

    // Build 88: the chart follows the range (DESIGN.md).
    final style = win <= 7
        ? RangeStyle.bars
        : win <= 30
        ? RangeStyle.lineAvg
        : RangeStyle.weeklyBand;
    if (vals.isEmpty) {
      return MetricLine(
        label: r.label,
        color: r.color,
        absentWhy: win == 1 ? 'not yet today' : 'no data in this range',
        onTap: open,
      );
    }

    if (r.key == 'step_kcal') {
      final secondary = denseDays(alternate, win);
      final paired = secondary.whereType<double>().toList();
      final budget = vals.reduce((a, b) => a + b) / vals.length;
      final movement = paired.length == vals.length
          ? paired.reduce((a, b) => a + b) / paired.length
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricLine(
            label: r.label,
            values: win == 1 ? const [] : dense,
            style: style,
            color: r.color,
            value: budget.round().toString(),
            unit: 'kcal · Budget',
            sub: vals.length < win ? '${vals.length}/$win days' : null,
            onTap: open,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: S.x3),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                '${movement == null ? 'Movement estimate unavailable' : 'Movement estimate ${movement.round()} kcal'} · runs excluded',
                softWrap: false,
                style: F.cap.copyWith(color: p.ink3),
              ),
            ),
          ),
        ],
      );
    }
    // The number IS the range: today's value on Today, otherwise the daily
    // average over the measured days in the range. It used to be the newest
    // reading in every range, so switching ranges changed nothing.
    final mean = vals.reduce((a, b) => a + b) / vals.length;
    final sub = vals.length < win ? '${vals.length}/$win days' : null;
    return MetricLine(
      label: r.label,
      // One day is not a chart; the value carries it.
      values: win == 1 ? const [] : dense,
      color: r.color,
      style: style,
      value: _fmt(r, mean),
      unit: r.key == 'strain' ? 'estimate' : unit,
      sub: sub,
      onTap: open,
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
