// The shared metric drill-down — the deepest level the app shows.
//
// Glance (a row on Health) → MetricDetail (your normal range, what moves it,
// how this week compares). The raw-figures "Nerd stats" layer was removed from
// the personal build: this screen is the end of the walk.
//
// Every metric goes through THIS screen. Forty bespoke detail screens is how
// the old UI ended up with forty different opinions about what a chart is.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../build_profile.dart';
import '../../data/db.dart' show LocalDb;
import '../../compute/day_upkeep.dart';
import '../../compute/profile.dart' show Profile, stepCalories, acsmActiveKcal;
import '../../gps/run_history.dart' show loadRuns;
import '../activity/day_strain.dart';
import '../../data/day_label.dart';
import '../../data/recovery_movers.dart'
    show kMoverOutcomes, loadRecoveryMovers;
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'day_steps.dart';
import 'day_timeline.dart'
    show DayGraph, DayHeartCard, DayTimelineScreen, dayGraph;
import 'home_screen.dart';
import 'journal_compose.dart' show OsTextField;
import 'readiness_detail.dart';
import 'sleep_detail.dart';

/// The one range list Trends and every metric screen share, in days. Trends
/// passes its choice into the metric it opens, so a 3-month view opens a
/// 3-month detail; changing range inside a metric affects that screen only.
const kRangeDays = [1, 7, 30, 90];
const kRangeLabels = ['Today', '7 days', '30 days', '3 months'];

// ═══════════════════ the vocabulary ═══════════════════

/// Days a "normal range" needs before it is shown.
const int kNormalRangeMinDays = 7;

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

  /// How it is computed, and who published the method.
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
    method:
        'The lowest sustained sleeping heart rate of the night, taken over '
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
    method:
        'RMSSD over the longest artefact-free window during sleep. Beat '
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
    method:
        'A weighted composite of a handful of inputs, each scored against '
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
    method:
        'Breathing rate recovered from respiratory sinus arrhythmia — the '
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
    method:
        'Total sleep time from the wrist z-angle sleep window, staged by a '
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
    color: C.sleep,
    icon: LucideIcons.moon,
    method:
        'A low-confidence overlay: a wrist sensor cannot see slow-wave '
        'activity, so deep sleep here is heart-rate flatness inside NREM.',
    citation: 'Cole–Kripke wake spine + HRV overlay',
  ),
  'rem': MetricSpec(
    chartKey: 'rem',
    title: 'REM sleep',
    unit: 'min',
    color: C.teal,
    icon: LucideIcons.moon,
    method:
        'Staged from beat-timing variability and movement. A wrist sensor '
        'separates REM from light sleep only approximately.',
    citation: 'Webster / Cole–Kripke rescoring + HRV staging',
  ),
  'step_kcal': MetricSpec(
    chartKey: 'step_kcal',
    title: 'Step calories',
    unit: 'kcal',
    icon: LucideIcons.flame,
    color: C.green,
    method:
        'Budget: counted steps × the day’s weight (Weyand). ACSM: the same '
        'walking by distance. Steps taken in runs are priced with the run. '
        'This is the walking part of maintenance; resting is separate.',
  ),
  'steps': MetricSpec(
    chartKey: 'steps',
    title: 'Steps',
    unit: 'steps',
    color: C.green,
    icon: LucideIcons.footprints,
    method:
        'Counted, never modelled. A step count comes from a gait-capable '
        'counter: the band\'s 100 Hz pedometer while it streams, or your '
        'phone\'s. Each stretch of the day is counted by whichever of the two '
        'was actually recording it, and a stretch both covered is counted '
        'once, so a session never takes the day from the sensor that carried '
        'the rest of it. There is no 1 Hz estimate — walking cadence sits above what '
        'one sample a second can resolve, so a day with no counter behind it '
        'reports no steps rather than a guess.',
    citation:
        'AN-2554 pedometer · phone pedometer (HealthKit / Health Connect)',
  ),
  'calories': MetricSpec(
    chartKey: 'calories',
    title: 'Active energy',
    unit: 'kcal',
    color: C.orange,
    icon: LucideIcons.flame,
    method:
        'Heart-rate-to-energy regression over the waking span, anchored on '
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
    method:
        'Training impulse: time in each heart-rate zone, weighted by the '
        'physiological cost of that zone.',
    citation: 'Banister 1975 · Edwards 1993',
  ),
  'stress': MetricSpec(
    chartKey: 'stress',
    title: 'Stress',
    color: C.purple,
    icon: LucideIcons.brain,
    higherBetter: false,
    method:
        'Baevsky stress index over a resting window: a histogram measure of '
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
    method:
        'The drop in heart rate over the 60 seconds after a bout ends, '
        'averaged across the day\'s bouts.',
    citation: 'Cole 1999 (HRR-60)',
  ),
  'lf_hf': MetricSpec(
    chartKey: 'lf_hf',
    title: 'LF / HF',
    color: C.purple,
    icon: LucideIcons.audioWaveform,
    method:
        'The ratio of low- to high-frequency power in beat-interval '
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
    method:
        'Coefficient of variation of per-window respiratory rate across '
        'the night.',
    citation: 'Within-user dispersion',
  ),
  // Both of these were written to `metric_series` on every derive since v55 and
  // had no spec, so nothing could open them — `specOf` fell through to a
  // generic entry titled "nap min". They are 17/17 on real data.
  'nap_min': MetricSpec(
    chartKey: 'nap_min',
    title: 'Daytime sleep',
    unit: 'min',
    color: C.indigo,
    icon: LucideIcons.moon,
    method:
        'Minutes of sleep detected OUTSIDE the main night: the same wrist '
        'z-angle window detector the night uses, confirmed by a heart-rate dip. '
        'Naps are counted separately and never folded into time asleep.',
    citation: 'van Hees 2015 window detection + nocturnal HR dip',
  ),
  'active_min': MetricSpec(
    chartKey: 'active_min',
    title: 'Movement minutes',
    unit: 'min',
    color: C.green,
    icon: LucideIcons.activity,
    method:
        'Minutes whose acceleration sits above a movement floor. That floor '
        'is pooled from your own recent days once there are enough of them, and '
        'a population one before that. This is activity VOLUME, not locomotion: '
        'steps are counted by a pedometer and are never derived from it.',
    citation: 'ENMO over a personal dynamic-range floor',
  ),
  'wear': MetricSpec(
    chartKey: 'wear',
    title: 'Wear time',
    unit: 'min',
    color: C.green,
    icon: LucideIcons.watch,
    method:
        'Minutes with a band record present. The band logs to flash only '
        'while it is on a wrist, so record presence IS wear.',
    citation: 'Record-presence, not heart-rate validity',
  ),

  // ── charted nowhere, on purpose ──
  'skin_temp': MetricSpec(
    chartKey: 'skin_temp',
    title: 'Skin temperature',
    unit: 'SD',
    color: C.orange,
    icon: LucideIcons.thermometer,
    higherBetter: false,
    suppress:
        'A deviation, not a temperature. Imported nights carry different '
        'units, so they are not charted together.',
    suppressFix: 'Shown tonight on Vitals',
    method:
        'The night\'s mean raw sensor reading, expressed as distance from '
        'your own recent nights. There is no conversion to degrees anywhere in '
        'the path.',
    citation: 'Relative only — uncalibrated ADC',
  ),
  // `spo2`, `odi_per_hour` and `strain_effort` used to live here as cards that
  // existed only to explain that they were empty. A metric this app does not
  // produce has no entry, no card and no key. See docs/internal/UI_ROADMAP.md.
  //
  // `rmssd_whole`, `stress_si` and `brv_slope` used to live here too, on the
  // same mistake in a quieter form: three fully written specs — title, unit,
  // colour, method, citation — whose whole rendered content was a card saying
  // they cannot be charted. Each is a bundle scalar and none of the three keys
  // is ever written to `metric_series`, so the series behind them is 0 rows and
  // always was. Nothing in the tree ever constructed them, the Explore
  // catalogue excludes them by name, and a spec that can only ever explain its
  // own emptiness is the absent-forever rule again. `stress` and `brv` are the
  // charted forms of two of the three and they stay.
};

MetricSpec specOf(String key) =>
    _specs[key] ?? MetricSpec(chartKey: key, title: key.replaceAll('_', ' '));

/// Which cross-day percentile block and journal outcome, if any, belongs to
/// this metric. Only four outcomes are correlated by the journal engine.
const _outcomeOf = {
  'hrv': 'rmssd',
  'resting_hr': 'rhr',
  'readiness': 'readiness',
  'efficiency': 'efficiency',
  'sleep': 'tst_min',
};

// ═══════════════════ the screen ═══════════════════

class MetricData {
  /// DATED points, not bare values. `metric_series` holds one row per DERIVED
  /// day rather than one per calendar day, so a compacted list lets 22 stored
  /// days masquerade as 30 continuous ones — the chart then joins straight
  /// across a sync gap and calls the newest stored point "Today".
  final List<ChartPoint> series;

  /// L4 — THE DENOMINATOR. Worn minutes for the same days, off the same
  /// `getChart` call. A long trend drawn without it is an attendance chart
  /// wearing a physiology label: it cannot make a sparse month comparable, only
  /// refuse to pretend one is.
  final List<ChartPoint> wear;
  final Map<String, dynamic>? percentile;
  final List<Map<String, dynamic>> movers;

  /// Days this install actually has a derived record for. Nothing prunes
  /// `day_result` or `metric_series`, so this is the true horizon — and it is
  /// what decides which range buttons exist.
  final int daysAvailable;

  /// Noon stamps on the days where the algorithm version CHANGED — the days
  /// either side were not produced the same way.
  ///
  /// `getChart` has attached this to every result all along and the only thing
  /// reading it was the briefing engine, so a trend drew straight through a
  /// release boundary. This export holds three versions of the same days and
  /// readiness moved across them: 2026-08-08 went 43.8 → 47.9.
  final List<int> algoBreaks;
  final List<ChartPoint> acsmSeries;

  /// The daily step-goal target, read from the profile. Only ever loaded for
  /// `key == 'steps'` — every other metric leaves it at the default and never
  /// draws it.
  final int stepGoal;

  const MetricData({
    this.series = const [],
    this.acsmSeries = const [],
    this.wear = const [],
    this.percentile,
    this.movers = const [],
    this.daysAvailable = 0,
    this.algoBreaks = const [],
    this.stepGoal = kDefaultStepGoal,
  });

  static Future<MetricData> load(
    LocalRepository repo,
    String key, {
    int calorieDays = 30,
  }) async {
    final spec = specOf(key);
    if (metricSuppressed(key)) return const MetricData();
    final chart = key == 'step_kcal'
        ? await repo.getChart('steps')
        : await repo.getChart(spec.chartKey);
    final models = key == 'step_kcal'
        ? await stepCalorieModels(repo, pointsOf(chart), days: calorieDays)
        : null;
    final points = models?.budget ?? pointsOf(chart);
    // Skin temperature charts only nights this band measured: an imported
    // night's deviation is another device's units (the reason the upstream
    // build hides the trend outright).
    final imported = key == 'skin_temp'
        ? await LocalDb.importedDates()
        : const <String>{};
    final days = await repo.availableDays();
    final outcome = _outcomeOf[key];
    final stepGoal = key == 'steps'
        ? ((await repo.getProfile())['step_goal'] as num?)?.toInt() ??
              kDefaultStepGoal
        : kDefaultStepGoal;

    Map<String, dynamic>? pct;
    var movers = const <Map<String, dynamic>>[];
    if (outcome != null) {
      final cd = await repo.getInsights();
      final all = cd['percentiles'];
      final one = all is Map ? all[outcome] : null;
      pct = envValue(one);
      if (kPersonalSideload) {
        // The personal build keeps no journal: patterns come from meals,
        // workouts, strain, steps and bedtime it already logs (build 81).
        movers = kMoverOutcomes.containsKey(outcome)
            ? await loadRecoveryMovers(
                outcome,
                profile: await repo.getProfile(),
              )
            : const [];
      } else {
        final j = await repo.getJournalInsights(range: '90d');
        final ins = j['insights'];
        movers = [
          for (final e in (ins is List ? ins : const []))
            if (e is Map && e['outcome'] == outcome) e.cast<String, dynamic>(),
        ];
      }
    }
    return MetricData(
      acsmSeries: models?.acsm ?? const [],
      series: [
        for (final p in points)
          if (imported.isEmpty ||
              !imported.contains(
                dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)),
              ))
            p,
      ],
      wear: pointsOf({'points': chart['wear']}),
      percentile: pct,
      movers: movers,
      daysAvailable: days.length,
      algoBreaks: [
        for (final b in (chart['algo_breaks'] as List? ?? const []))
          if (b is Map && b['t'] is num) (b['t'] as num).round(),
      ],
      stepGoal: stepGoal,
    );
  }
}

Future<List<ChartPoint>> stepCaloriePoints(
  LocalRepository repo,
  List<ChartPoint> steps,
) async => (await stepCalorieModels(repo, steps)).budget;

Future<({List<ChartPoint> budget, List<ChartPoint> acsm})> stepCalorieModels(
  LocalRepository repo,
  List<ChartPoint> steps, {
  int days = 365,
  DateTime? at,
}) async {
  final profile = Profile.fromMap(await repo.getProfile());
  final out = <ChartPoint>[], acsm = <ChartPoint>[];
  final runs = await loadRuns(repo);
  final now = at ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final cutoff = DateTime(
    now.year,
    now.month,
    now.day - days.clamp(1, 365) + 1,
  );
  for (final point in steps) {
    final instant = DateTime.fromMillisecondsSinceEpoch(point.t * 1000);
    final date = dayLabelOf(instant), day = DateTime.parse(date);
    if (day.isBefore(cutoff) || day.isAfter(today)) continue;
    final upkeep = await DayUpkeep.read(
      repo,
      date,
      profile,
      eaten: 0,
      runs: runs,
    );
    final budget =
        upkeep.parts?.steps ??
        stepCalories(upkeep.walkedSteps, upkeep.profile.weightKg);
    if (budget != null) out.add((t: point.t, v: budget));
    final secondary =
        upkeep.acsmParts?.steps ??
        (upkeep.walkingMeters == null
            ? null
            : acsmActiveKcal(
                runMeters: 0,
                walkMeters: upkeep.walkingMeters!,
                weightKg: upkeep.profile.weightKg,
              ));
    if (secondary != null) acsm.add((t: point.t, v: secondary));
  }
  return (budget: out, acsm: acsm);
}

class TodaySignalDetail extends StatefulWidget {
  const TodaySignalDetail(this.metricKey, {super.key});
  final String metricKey;
  @override
  State<TodaySignalDetail> createState() => _TodaySignalDetailState();
}

class _TodaySignalDetailState extends State<TodaySignalDetail>
    with RevisionReload {
  List<ChartPoint> _points = const [];
  List<double?> _wear = const [];
  DayGraph? _heart;
  String? _date;
  bool _loading = true, _failed = false;
  int? _pick;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void reload() => _load();
  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    final t = beginRead(#signal);
    try {
      var points = const <ChartPoint>[];
      var wear = const <double?>[];
      DayGraph? heart;
      String? date;
      if (widget.metricKey == 'resting_hr') {
        heart = dayGraph(await repo.getDayTimeline(todayLabel()));
      } else if (widget.metricKey == 'hrv') {
        final d = await repo.getDayHrv(todayLabel());
        date = d['date'] as String?;
        points = pointsOf({'points': d['timeline']});
      } else {
        final d = await repo.getDayWear(todayLabel());
        date = d['date'] as String?;
        final segs = d['segments'];
        if (segs is List) {
          final measured = List<bool>.filled(24, false);
          final minutes = List<double>.filled(24, 0);
          for (final seg in segs) {
            if (seg is! Map || seg['start'] is! num || seg['end'] is! num)
              continue;
            final start = (seg['start'] as num).toInt(),
                end = (seg['end'] as num).toInt();
            for (var at = start; at < end;) {
              final local = DateTime.fromMillisecondsSinceEpoch(at * 1000);
              final next =
                  DateTime(
                    local.year,
                    local.month,
                    local.day,
                    local.hour + 1,
                  ).millisecondsSinceEpoch ~/
                  1000;
              final until = next > at
                  ? (next < end ? next : end)
                  : (at + 60).clamp(at + 1, end);
              measured[local.hour] = true;
              if (seg['on'] == true || seg['on'] == 1)
                minutes[local.hour] += (until - at) / 60;
              at = until;
            }
          }
          wear = [for (var h = 0; h < 24; h++) measured[h] ? minutes[h] : null];
        }
      }
      if (stillNewest(#signal, t))
        setState(
          () => (
            _points = points,
            _wear = wear,
            _heart = heart,
            _date = date,
            _loading = false,
            _failed = false,
          ),
        );
    } catch (_) {
      if (stillNewest(#signal, t))
        setState(() => (_loading = false, _failed = true));
    }
  }

  @override
  Widget build(BuildContext c) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed)
      return StatusCard(
        'Daily chart could not load',
        'Your saved measurements are intact.',
        fix: 'Retry',
        onFix: _load,
      );
    if (widget.metricKey == 'resting_hr') {
      return _heart?.hasCurve == true
          ? DayHeartCard(_heart!)
          : const SizedBox.shrink();
    }
    final isWear = widget.metricKey == 'wear';
    if ((isWear && _wear.isEmpty) || (!isWear && _points.isEmpty))
      return const SizedBox.shrink();
    // HRV is placed into real minute slots, retaining recording gaps. A
    // compact list would turn missing windows into continuous variability.
    final start = _points.isEmpty ? 0 : _points.first.t;
    final end = _points.isEmpty ? 0 : _points.last.t;
    final values = isWear
        ? _wear
        : List<double?>.filled((end - start) ~/ 60 + 1, null);
    if (!isWear) {
      for (final p in _points) values[(p.t - start) ~/ 60] = p.v;
    }
    final last = isWear
        ? latestDaySlot(_date, values.length)
        : values.length - 1;
    if (isWear)
      for (var slot = last + 1; slot < values.length; slot++)
        values[slot] = null;
    final axis = AxisSpec.of(values.whereType<double>(), floor: 0);
    final i = _pick?.clamp(0, last);
    String time(int slot) => isWear
        ? '${slot.toString().padLeft(2, '0')}:00'
        : clockOfTs(start + slot * 60);
    final title =
        '${isWear ? 'Wear by hour' : 'HRV through the night'}'
        '${_date != null && _date != todayLabel() ? ' · ${prettyDay(_date)}' : ''}';
    final unit = isWear ? 'min' : 'ms';
    return Surface(
      child: ChartFrame(
        title: title,
        unit: unit,
        height: 150,
        series: values,
        yAxis: axis,
        xLabels: isWear
            ? const ['00:00', '12:00', '24:00']
            : [
                time(0),
                time((values.length - 1) ~/ 2),
                time(values.length - 1),
              ],
        readout: i == null
            ? null
            : '${time(i)} · ${values[i]?.round().toString() ?? 'not recorded'}${values[i] == null ? '' : ' $unit'}',
        footnote: isWear
            ? 'Recorded wear time; gaps are unmeasured.'
            : 'Rolling 5-minute RMSSD from measured beat timing. Gaps are unmeasured.',
        child: Scrubber(
          maxValue: values.length <= 1 ? 1 : last / (values.length - 1),
          value: i == null
              ? null
              : (values.length == 1 ? 0 : i / (values.length - 1)),
          onChanged: (v) =>
              setState(() => _pick = (v * (values.length - 1)).round()),
          label: title,
          describe: (v) {
            final slot = (v * (values.length - 1)).round();
            return '${time(slot)} · ${values[slot]?.round().toString() ?? 'not recorded'} $unit';
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: isWear
                ? Bars(values, P.of(c).on(C.indigo), axis: axis, cursor: i)
                : LineChart(values, P.of(c).on(C.teal), axis: axis, cursor: i),
          ),
        ),
      ),
    );
  }
}

class MetricDetail extends StatefulWidget {
  final String metricKey;
  final MetricData? data;

  /// Index into [kRangeDays]: the range the screen opens on, normally the one
  /// chosen on Trends.
  final int range;

  /// A day to open on, selected in the day row. Links from a dated screen
  /// (a night on Sleep, a readiness input) pass it so the metric shows that
  /// same day, never just "now".
  final String? day;
  const MetricDetail(
    this.metricKey, {
    super.key,
    this.data,
    this.range = 0,
    this.day,
  });

  /// The metric at [day]: Today when it is today, otherwise the shortest range
  /// that contains it, with that day selected.
  factory MetricDetail.at(String metricKey, String? day) {
    final behind = day == null
        ? 0
        : calendarDaysBetween(DateTime.parse(day), DateTime.now());
    final range = kRangeDays.indexWhere((w) => behind < w);
    return MetricDetail(
      metricKey,
      range: range < 0 ? kRangeDays.length - 1 : range,
      day: behind <= 0 ? null : day,
    );
  }

  @override
  State<MetricDetail> createState() => _MetricDetailState();
}

class _MetricDetailState extends State<MetricDetail> with RevisionReload {
  // Today is its own window, not the left edge of the 7-day one. Asking "what
  // is it right now" and "what has it been lately" are different questions,
  // and a range list that starts at 7 days made the first one unanswerable.
  static const _windows = kRangeDays;

  /// TODAY. A tile on Home shows today's number, so the screen behind that tap
  /// opens on today's number — anything else is a different question than the
  /// one that was asked.
  ///
  /// It used to open on 30 days, and worse, on the WIDEST range the install had
  /// data for: the clamp below meant three weeks of history landed you on 7
  /// days and three months on 30, so the default moved as the install aged and
  /// was never today. The range switcher is still here and still remembers
  /// nothing between visits — a default is where a screen starts, not a
  /// preference.
  late int _range = widget.range.clamp(0, _windows.length - 1);
  MetricData? _d;
  final _calorieCache = <(LocalRepository, int, int, String), MetricData>{};
  bool _loading = true;
  bool _failed = false;

  /// The slot the user has put a finger on, as an index into the DENSE window.
  /// Null until they touch the chart. A window change clears it: slot 12 of a
  /// 30-day window is not slot 12 of a year.
  int? _pick;

  /// Every range is always offered, as on Trends. A short history simply
  /// shows "n of 90 days" under the average rather than hiding the button.
  int _offered(MetricData d) => _windows.length;

  Widget _ranges(BuildContext c, MetricData d, Color color) =>
      SubTabs(kRangeLabels, _range, (i) {
        setState(() => (_range = i, _pick = null));
        if (widget.metricKey == 'step_kcal' && widget.data == null) _load();
      }, color: color);

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
    final token = beginRead(#metric);
    try {
      AppState? app;
      try {
        app = context.read<AppState>();
      } catch (_) {
        /* Isolated fixtures. */
      }
      final key = (
        repo,
        app?.insightsRevision.value ?? -1,
        _windows[_range],
        todayLabel(),
      );
      final useCache = widget.metricKey == 'step_kcal' && app != null;
      // Cache only this screen's visible windows, keyed by committed input revision.
      // Keep repository/day identity: restore, rollover or a new profile cannot reuse it.
      final d =
          (useCache ? _calorieCache[key] : null) ??
          await MetricData.load(
            repo,
            widget.metricKey,
            calorieDays: _windows[_range],
          );
      if (useCache && app.insightsRevision.value == key.$2) {
        _calorieCache.removeWhere(
          (k, _) => k.$1 != repo || k.$2 != key.$2 || k.$4 != key.$4,
        );
        _calorieCache[key] = d;
      }
      if (stillNewest(#metric, token))
        setState(() => (_d = d, _loading = false, _failed = false));
    } catch (_) {
      if (stillNewest(#metric, token))
        setState(() => (_loading = false, _failed = true));
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
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
      // Resting heart rate is the NIGHT's number; this is what the chest is
      // doing this second. Two different quantities, so the live one gets its
      // own card above the trend rather than a second figure on the same card,
      // where it would read as a correction to the headline.
      // `data == null` is the LIVE path: every fixture and golden injects its
      // own MetricData, and those render with no Provider above them by design.
      // The live card reads AppState, so it belongs only on the real one.
      if (widget.metricKey == 'resting_hr' && widget.data == null) ...[
        const SizedBox(height: S.x2),
        const LiveHrCard(),
        const SizedBox(height: S.x5),
      ],
      if (metricSuppressed(widget.metricKey)) ...[
        const SizedBox(height: S.x2),
        StatusCard(
          l?.metricDetailNotShownTitle ?? 'Not shown as a trend',
          spec.suppress!,
          fix: spec.suppressFix ?? '',
          icon: spec.icon,
        ),
      ] else if (_failed) ...[
        StatusCard(
          'This metric could not load',
          'Your saved data is intact.',
          fix: 'Retry',
          onFix: _load,
        ),
      ] else if (win == 1 &&
          widget.data == null &&
          const [
            'sleep',
            'strain',
            'readiness',
          ].contains(widget.metricKey)) ...[
        _ranges(c, d, spec.color),
        const SizedBox(height: S.x5),
        if (widget.metricKey == 'sleep')
          const SleepDetail(embedded: true)
        else if (widget.metricKey == 'readiness')
          const ReadinessDetail(embedded: true)
        else
          const DayStrainDetail(embedded: true),
      ] else if (vals.isEmpty) ...[
        _ranges(c, d, spec.color),
        const SizedBox(height: S.x5),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          StatusCard(
            win == 1
                ? (l?.metricDetailNothingRecordedToday ??
                      'Nothing recorded today')
                : (l?.metricDetailNoHistoryYet(spec.title.toLowerCase()) ??
                      'No history for ${spec.title.toLowerCase()} yet'),
            win == 1
                ? (all.isEmpty
                      ? (l?.metricDetailNoValueYet ??
                            'Today has not produced a value yet.')
                      : (l?.metricDetailNoValueYetWiderRanges ??
                            'Today has not produced a value yet. The wider ranges '
                                'above hold the days that did.'))
                : (l?.metricDetailNoValueInWindow ??
                      'No day in this window produced a value.'),
            // Today opens first now, so this card is what someone with months
            // of history sees on a morning before the derive lands. Telling
            // them to wear the band is a promise that cannot change anything —
            // they already did, and the days are one tab away.
            fix: all.isEmpty
                ? (l?.metricDetailWearBandFix ??
                      'Wear the band overnight to start the series')
                : '',
            icon: spec.icon,
          ),
        // The goal is editable even before today has a steps value — the
        // gate below matches the measured branch's. `steps: null` keeps the
        // ring an empty track rather than fabricating a 0% reading. Gated on
        // `!_loading` too: before the real profile loads, `d` is the
        // placeholder `MetricData()` and `d.stepGoal` is just the fallback
        // default, not this user's goal — showing the editor pre-filled with
        // that would risk saving it over their real one.
        if (win == 1 &&
            widget.data == null &&
            const ['steps', 'step_kcal'].contains(widget.metricKey)) ...[
          const SizedBox(height: S.x3),
          DayStepsDetail(
            embedded: true,
            calories: widget.metricKey == 'step_kcal',
          ),
        ],
        if (!_loading && widget.metricKey == 'steps' && win == 1) ...[
          const SizedBox(height: S.x5),
          _StepGoalGauge(
            steps: null,
            goal: d.stepGoal,
            color: spec.color,
            onSaved: _load,
          ),
        ],
      ] else ...[
        _ranges(c, d, spec.color),
        const SizedBox(height: S.x5),
        _hero(c, spec, all, series, vals, win, d.wear, d.algoBreaks),
        if (win > 1) ..._periods(c, spec, series),
        // Today's count against the goal set on this screen's own edit
        // affordance — a trend average has no goal to be measured against, so
        // this stays win == 1 only, same gate as the Breakdown link below.
        if (widget.metricKey == 'steps' && win == 1) ...[
          const SizedBox(height: S.x5),
          _StepGoalGauge(
            steps: vals.last,
            goal: d.stepGoal,
            color: spec.color,
            onSaved: _load,
          ),
        ],
        if (const ['steps', 'step_kcal'].contains(widget.metricKey) &&
            win == 1 &&
            widget.data == null) ...[
          const SizedBox(height: S.x3),
          DayStepsDetail(
            embedded: true,
            calories: widget.metricKey == 'step_kcal',
          ),
        ],
        // On Today the window holds one value, and its lowest, typical and
        // highest would all be that same number. The normal range is a
        // property of your history, not of the window — so on Today it reads
        // the whole series.
        // A range needs a week of days; from one or two it printed the same
        // number as Lowest, Typical and Highest.
        if ((win == 1 ? valuesOf(all) : vals).length >= kNormalRangeMinDays)
          Section(
            l?.metricDetailNormalRangeSection ?? 'Your normal range',
            _range3(
              c,
              spec,
              win == 1 ? valuesOf(all) : vals,
              d.percentile,
              all.isEmpty ? null : all.last.t,
            ),
          ),
        if (const ['steps', 'step_kcal'].contains(widget.metricKey)) ...[
          const SizedBox(height: S.x3),
          detailLinkRow(
            c,
            LucideIcons.calendarDays,
            'Browse days',
            'Open today, yesterday or another saved day',
            () => go(
              c,
              DayStepsDetail(calories: widget.metricKey == 'step_kcal'),
            ),
          ),
        ],
        if (d.movers.isNotEmpty)
          Section(
            l?.metricDetailWhatMovesItSection ?? 'What moves it',
            _movers(c, d.movers),
          ),
        const SizedBox(height: S.x5),
      ],
      if (win == 1 &&
          widget.data == null &&
          const ['resting_hr', 'hrv', 'wear'].contains(widget.metricKey)) ...[
        const SizedBox(height: S.x3),
        TodaySignalDetail(widget.metricKey),
      ],
      if (widget.metricKey == 'step_kcal' && win == 1 && vals.isNotEmpty)
        Surface(
          child: Text(
            spec.method,
            style: F.cap.copyWith(color: P.of(c).ink2, height: 1.5),
          ),
        ),
    ]);
  }

  // ── value → context → trend ──
  //
  // THE HEADLINE IS THE WINDOW'S NUMBER, not the latest reading.
  //
  // It used to be `vals.last`, which is the same figure in every range — so
  // switching 7 days to 30 days changed the chart and left the big number
  // sitting there, and on an additive metric it was worse than confusing:
  // today's 43 steps under a "30 days" tab reads as a month's total.
  //
  // The day count beside it is not decoration. It is what explains the case
  // that looks broken: with one day of history, seven days and thirty days
  // really do average to the same number, and "1 of 30 days" says so where
  // a bare figure looked like a bug.
  Widget _hero(
    BuildContext c,
    MetricSpec spec,
    List<ChartPoint> all,
    List<double?> series,
    List<double> vals,
    int win,
    List<ChartPoint> wear,
    List<int> algoBreaks,
  ) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final mean = vals.reduce((a, b) => a + b) / vals.length;
    final latest = vals.last;
    final alternate = widget.metricKey == 'step_kcal'
        ? denseDays(_d?.acsmSeries ?? const [], win)
        : const <double?>[];
    // On a month or longer the day-to-day line is noisy; a 7-day average
    // drawn under it is the trend. Each point needs four measured days.
    final rolling = win < 30 || alternate.isNotEmpty
        ? const <double?>[]
        : rollingMean(series, 7, minCount: 4);
    // WHICH DAY the newest reading is from. `metric_series` gets a row only on
    // a day that derives, so after a sync gap the newest stored point is days
    // old — and this line is the answer to "is there a today?".
    final asOf = all.isEmpty ? '' : axisDay(all.last.t);

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.metricKey == 'step_kcal')
            CaloriePair(
              budget: mean,
              acsm: () {
                final values = denseDays(
                  _d?.acsmSeries ?? const [],
                  win,
                ).whereType<double>().toList();
                return values.length != vals.length
                    ? null
                    : values.reduce((a, b) => a + b) / values.length;
              }(),
              note: '',
            )
          else
            Wrap(
              spacing: S.x2,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(_fmt(spec, mean), style: F.n48.copyWith(color: p.ink)),
                // NOT `spec.unit`. `metricValue('min', 443)` is already "7h 23m",
                // so every min-unit metric — Time asleep, Deep, REM, Wear time —
                // rendered its headline as "7h 23m min".
                Text(
                  unitBeside(spec.unit),
                  style: F.body.copyWith(color: p.ink3),
                ),
              ],
            ),
          const SizedBox(height: S.x1),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              win == 1
                  ? (l?.metricDetailToday ?? 'Today')
                  : (l?.metricDetailDailyAverage(vals.length, win) ??
                        'Daily average · ${vals.length} of $win days'),
              style: F.cap.copyWith(color: p.ink3),
            ),
          ),
          // On a multi-day window the average is the headline, so the newest
          // reading needs its own line. On Today they are the same number, and
          // printing it twice would read as two different facts.
          if (win > 1 && asOf.isNotEmpty) ...[
            const SizedBox(height: S.x2),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                (l?.metricDetailLatestReading(
                          _fmt(spec, latest),
                          unitBeside(spec.unit),
                          asOf,
                        ) ??
                        'Latest ${_fmt(spec, latest)} ${unitBeside(spec.unit)} · $asOf')
                    .replaceAll('  ', ' '),
                style: F.cap.copyWith(color: p.ink3),
              ),
            ),
          ],
          // No chart on Today. These series carry one value per day, so a
          // one-day window is a single point — and a single point drawn on an
          // axis is a shape pretending to be a trend. "Your normal range" below
          // is the context that actually helps here.
          if (win > 1) const SizedBox(height: S.x5),
          if (win > 1)
            Builder(
              builder: (c) {
                // One axis, shared by the labels and the curve. `min` unit metrics
                // print `7h 30m` on the gridlines rather than `450`.
                final axis = AxisSpec.of(
                  [...vals, ...alternate.whereType<double>()],
                  ticks: 3,
                  format: spec.unit == 'min'
                      ? axisHm
                      : (spec.unit == 'steps' || spec.unit == 'kcal'
                            ? (v) => thousands(v)
                            : (vals.every((v) => v.abs() >= 10)
                                  ? axisInt
                                  : axisFixed)),
                  floor: spec.unit == '%' ? 0 : null,
                );
                // WHERE A RELEASE SITS ON THE LINE.
                //
                // A break's stamp is the first day computed the NEW way, so the
                // boundary is between two slots, not on one — half a slot left of it.
                // A break at slot 0 is dropped: there is nothing before it in this
                // window to be incomparable with.
                final marks = <double>[
                  if (series.length > 1 && !kPersonalSideload)
                    for (final t in algoBreaks)
                      if (daysBehind(t) case final b?
                          when b >= 0 &&
                              b < series.length &&
                              series.length - 1 - b > 0)
                        (series.length - 1 - b - .5) / (series.length - 1),
                ];
                return ChartFrame(
                  title: spec.title,
                  // Minutes already read "7h 05m"; a second "min" doubled it.
                  unit: spec.unit == 'min'
                      ? ''
                      : (spec.unit.isEmpty ? 'score' : spec.unit),
                  height: 150,
                  yAxis: axis,
                  xMarks: marks,
                  // The mark's only screen-reader form, and the only thing that can
                  // say what it is. Deliberately flat: a version change is
                  // provenance, not an event that happened to the user.
                  footnote: marks.isEmpty
                      ? null
                      : (l?.metricDetailAlgoBreakFootnote(marks.length) ??
                            (marks.length == 1
                                ? 'The dotted line is a change in how these days were '
                                      'computed. Readings either side of it came from '
                                      'different versions.'
                                : 'The dotted lines are changes in how these days were '
                                      'computed. Readings either side of one came from '
                                      'different versions.')),
                  // The window IS the span now: `series` has one slot per calendar
                  // day whether or not that day derived, so both edges are dates
                  // rather than array positions. It used to read the length of a
                  // compacted list, which meant a chart spanning two months labelled
                  // its left edge "30 days ago".
                  // Slot 0 is `length - 1` days behind today, not `length` — the
                  // last slot IS today. A 30-slot window spans 29 days of distance.
                  xLabels: [
                    l?.metricDetailDaysAgoLabel(series.length - 1) ??
                        '${series.length - 1} day${series.length == 2 ? '' : 's'} ago',
                    l?.metricDetailToday ?? 'Today',
                  ],
                  // The dots are already beside the big number two rows up; twice on
                  // one card reads as two different claims.
                  legend: alternate.isNotEmpty
                      ? [('Budget', p.on(spec.color)), ('ACSM', p.on(C.teal))]
                      : rolling.isEmpty
                      ? const []
                      : [
                          ('Daily', p.on(spec.color)),
                          ('7-day average', p.ink2),
                        ],
                  series: series,
                  readout: _pick == null
                      ? null
                      : _slotSays(
                          c,
                          spec,
                          series,
                          _pick!.clamp(0, series.length - 1),
                        ),
                  // TOUCHING A POINT OPENS THAT DAY.
                  //
                  // This chart will draw the night somebody's sleep collapsed and
                  // there was no way into it: every single-day screen resolved the
                  // newest day and stopped. A slot with a value came out of
                  // `metric_series`, which gets a row only on a day that DERIVED, so
                  // a non-null slot is by construction a day this install can open —
                  // no membership check, and a null slot offers no door.
                  child: Scrubber(
                    // Slot i sits at i/(len-1) — exactly where `minMaxRuns` plots it,
                    // so the readout names the day under the finger rather than the
                    // bucket the finger is in.
                    value: _pick == null
                        ? null
                        : _slotAt01(_pick!, series.length),
                    step: 1 / (series.length - 1),
                    label: spec.title,
                    describe: (v) =>
                        _slotSays(c, spec, series, _slotAt(v, series.length)),
                    onChanged: (v) =>
                        setState(() => _pick = _slotAt(v, series.length)),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: LineChart(
                              series,
                              p.on(spec.color),
                              fill: axis?.min == 0,
                              dots: series.length <= 40,
                              t: animate(c, 1),
                              dotInk: p.card,
                              axis: axis,
                              cursor: _pick,
                              cursorInk: p.ink,
                            ),
                          ),
                        ),
                        if (rolling.isNotEmpty)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: LineChart(
                                rolling,
                                p.ink2,
                                fill: false,
                                axis: axis,
                              ),
                            ),
                          ),
                        if (alternate.isNotEmpty)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: LineChart(
                                alternate,
                                p.on(C.teal),
                                fill: false,
                                dots: alternate.length <= 40,
                                axis: axis,
                                cursor: _pick,
                                cursorInk: p.ink,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          // Always shown: the newest day until another is picked, with arrows,
          // so no day needs the chart touched first.
          // (Today has its own day view and navigation below.)
          if (win > 1 && series.isNotEmpty) _picked(c, spec, series),
          // L4 — the coverage denominator, under the curve it belongs to.
          //
          // Deliberately unflattering, and gated to the ranges where it changes
          // the reading: a 7-day chart is one week you either wore or did not,
          // while a 6-month line drawn over four worn nights a month is an
          // attendance chart with a physiology label on it. It cannot make a
          // sparse month comparable — only refuse to pretend.
          //
          // A day with no `worn_min` row draws NOTHING, not a zero: wear older
          // than the 3-day substrate window is knowable only through this derived
          // key, and nothing here reconstructs it. Same card, not a new one; the
          // denominator is part of reading the chart, not a second claim.
          if (!kPersonalSideload &&
              win >= 30 &&
              spec.chartKey != 'wear' &&
              wear.isNotEmpty)
            Builder(
              builder: (c) {
                final hrs = [
                  for (final v in denseDays(wear, win))
                    v == null ? null : v / 60,
                ];
                final have = [for (final v in hrs) ?v];
                if (have.isEmpty) return const SizedBox.shrink();
                final axis = AxisSpec.of(
                  have,
                  ticks: 2,
                  floor: 0,
                  ceil: 24,
                  format: axisInt,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: S.x4),
                  child: ChartFrame(
                    title: l?.metricDetailWornChartTitle ?? 'Worn',
                    unit: l?.metricDetailHoursADayUnit ?? 'h a day',
                    height: 56,
                    yAxis: axis,
                    series: hrs,
                    footnote:
                        l?.metricDetailWearFootnote(have.length, win) ??
                        '${have.length} of these $win days have a wear '
                            'record. The rest are gaps in both charts — the line above '
                            'is not carried across one.',
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: Bars(hrs, p.ink3, axis: axis),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── a point on the chart is a day you can open ──────────────────────────

  /// A 0…1 position along the plot as a slot index into the dense window, and
  /// back. Point i is drawn at `i / (len - 1)` — see `minMaxRuns` — so that is
  /// what both directions use.
  int _slotAt(double v, int len) =>
      len < 2 ? 0 : (v * (len - 1)).round().clamp(0, len - 1);

  double _slotAt01(int i, int len) => len < 2 ? 0 : i / (len - 1);

  /// The calendar day a dense slot stands for. Slot `len - 1` is today and
  /// slot 0 is `len - 1` days behind it — the same arithmetic [denseDays] fills
  /// with, walked through [DateTime]'s own calendar so the two days a year that
  /// are 23 or 25 hours long land on the right date.
  String _dayOfSlot(int i, int len) {
    final n = DateTime.now();
    return dayLabelOf(DateTime(n.year, n.month, n.day - (len - 1 - i)));
  }

  /// What the slider reads out. The value, or the fact that the day is a hole.
  String _slotSays(
    BuildContext c,
    MetricSpec spec,
    List<double?> series,
    int i,
  ) {
    final l = AppLocalizations.of(c);
    final day = prettyDay(_dayOfSlot(i, series.length), l);
    final v = series[i];
    if (widget.metricKey == 'step_kcal') {
      final secondary = denseDays(_d?.acsmSeries ?? const [], series.length)[i];
      return '$day · Budget ${v == null ? 'unavailable' : '${thousands(v)} kcal'} · ACSM ${secondary == null ? 'unavailable' : '${thousands(secondary)} kcal'}';
    }
    return v == null
        ? (l?.metricDetailSlotNoRecord(day) ?? '$day, no record')
        : (l?.metricDetailSlotWithValue(
                    day,
                    _fmt(spec, v),
                    unitBeside(spec.unit),
                  ) ??
                  '$day, ${_fmt(spec, v)} ${unitBeside(spec.unit)}')
              .trimRight();
  }

  /// The touched day, and the door into it.
  ///
  /// A day with a value is a day that derived, so the door always leads
  /// somewhere. A day with no value says so and offers nothing — an action
  /// button is a promise, and there is no screen behind an empty day.
  Widget _picked(BuildContext c, MetricSpec spec, List<double?> series) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final newest = series.lastIndexWhere((v) => v != null);
    final asked = widget.day == null
        ? -1
        : series.length -
              1 -
              calendarDaysBetween(DateTime.parse(widget.day!), DateTime.now());
    final i =
        (_pick ??
                (asked >= 0
                    ? asked
                    : (newest < 0 ? series.length - 1 : newest)))
            .clamp(0, series.length - 1);
    final day = _dayOfSlot(i, series.length);
    final v = series[i];
    final door =
        v == null && !const ['steps', 'step_kcal'].contains(widget.metricKey)
        ? null
        : _dayScreen(widget.metricKey, day);
    Widget arrow(IconData icon, String label, int to) {
      final ok = to >= 0 && to < series.length;
      return Opacity(
        opacity: ok ? 1 : .35,
        child: Pressable(
          onTap: ok ? () => setState(() => _pick = to) : null,
          semanticLabel: label,
          child: Padding(
            padding: const EdgeInsets.all(S.x1),
            child: Icon(icon, size: 20, color: p.ink),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: Row(
        children: [
          arrow(LucideIcons.chevronLeft, 'Previous day', i - 1),
          const SizedBox(width: S.x1),
          Expanded(
            child: Surface(
              color: p.card2,
              elevation: 0,
              onTap: door == null ? null : () => go(c, door),
              semanticLabel: v == null
                  ? (l?.metricDetailSlotNoRecord(prettyDay(day, l)) ??
                        '${prettyDay(day, l)}, no record')
                  : door == null
                  ? '${prettyDay(day, l)}, ${_fmt(spec, v)} ${unitBeside(spec.unit)}'
                        .trimRight()
                  : (l?.metricDetailOpenDay(prettyDay(day, l)) ??
                        'Open ${prettyDay(day, l)}'),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      dayNavLabel(day),
                      style: F.body.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  if (widget.metricKey == 'step_kcal')
                    Flexible(
                      child: Text(
                        _slotSays(
                          c,
                          spec,
                          series,
                          i,
                        ).split(' · ').skip(1).join('\n'),
                        style: F.cap.copyWith(color: p.ink2),
                      ),
                    )
                  else
                    // Flexible: at large text on a small phone the value
                    // wraps rather than pushing the row off the card.
                    Flexible(
                      child: Text(
                        v == null
                            ? (l?.metricDetailNoRecordLabel ?? 'No record')
                            : '${_fmt(spec, v)} ${unitBeside(spec.unit)}'
                                  .trimRight(),
                        textAlign: TextAlign.right,
                        style: v == null
                            ? F.cap.copyWith(color: p.ink3)
                            : F.n17.copyWith(color: p.ink),
                      ),
                    ),
                  if (door != null) ...[
                    const SizedBox(width: S.x2),
                    Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: S.x1),
          arrow(LucideIcons.chevronRight, 'Next day', i + 1),
        ],
      ),
    );
  }

  /// What separates the ranges beyond the chart's width: each day for a week,
  /// weekly averages for a month and monthly averages for three months. A day
  /// row opens that day; a week or month row moves the selection to its
  /// newest measured day.
  List<Widget> _periods(BuildContext c, MetricSpec spec, List<double?> series) {
    if (widget.metricKey == 'step_kcal' || series.isEmpty) return const [];
    final p = P.of(c);
    final len = series.length;
    final rows = <({String label, double? value, int slot, bool day})>[];
    if (len <= 7) {
      for (var i = len - 1; i >= 0; i--) {
        rows.add((
          label: dayNavLabel(_dayOfSlot(i, len)),
          value: series[i],
          slot: i,
          day: true,
        ));
      }
    } else {
      final byMonth = len > 31;
      final groups = <String, List<int>>{};
      for (var i = 0; i < len; i++) {
        final d = DateTime.parse(_dayOfSlot(i, len));
        final key = byMonth
            ? '${d.year}-${d.month}'
            : dayLabelOf(DateTime(d.year, d.month, d.day - (d.weekday - 1)));
        (groups[key] ??= []).add(i);
      }
      for (final e in groups.entries.toList().reversed) {
        final have = [for (final i in e.value) ?series[i]];
        final newest = e.value.lastWhere(
          (i) => series[i] != null,
          orElse: () => e.value.last,
        );
        final first = DateTime.parse(_dayOfSlot(e.value.first, len));
        rows.add((
          label: byMonth
              ? _monthName(first)
              : 'Week of ${prettyDay(_dayOfSlot(e.value.first, len))}',
          value: have.isEmpty
              ? null
              : have.reduce((a, b) => a + b) / have.length,
          slot: newest,
          day: false,
        ));
      }
    }
    return [
      Section(
        len <= 7 ? 'By day' : (len > 31 ? 'By month' : 'By week'),
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(
            children: [
              for (var k = 0; k < rows.length; k++) ...[
                if (k > 0) Divider(color: p.line, height: 1),
                _periodRow(c, spec, rows[k], len),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  Widget _periodRow(
    BuildContext c,
    MetricSpec spec,
    ({String label, double? value, int slot, bool day}) row,
    int len,
  ) {
    final p = P.of(c);
    final v = row.value;
    final door = row.day && v != null
        ? _dayScreen(widget.metricKey, _dayOfSlot(row.slot, len))
        : null;
    final text = v == null
        ? 'No record'
        : '${row.day ? '' : 'avg '}${_fmt(spec, v)} ${unitBeside(spec.unit)}'
              .trimRight();
    return Pressable(
      onTap: row.day
          ? (door == null ? null : () => go(c, door))
          : () => setState(() => _pick = row.slot),
      semanticLabel: '${row.label}, $text',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Expanded(
              child: Text(row.label, style: F.body.copyWith(color: p.ink)),
            ),
            Text(
              text,
              style: v == null
                  ? F.cap.copyWith(color: p.ink3)
                  : F.body.copyWith(color: p.ink),
            ),
            if (door != null) ...[
              const SizedBox(width: S.x2),
              Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
            ],
          ],
        ),
      ),
    );
  }

  static String _monthName(DateTime d) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][d.month - 1];

  /// Where a day opens. Each metric lands on the screen that actually shows
  /// that day; a metric with no per-day screen has no door (null).
  Widget? _dayScreen(String key, String day) => switch (key) {
    'sleep' || 'deep' || 'rem' || 'efficiency' => SleepDetail(day: day),
    'steps' => DayStepsDetail(day: day),
    'step_kcal' => DayStepsDetail(day: day, calories: true),
    'strain' => DayStrainDetail(day: day),
    // Night-derived signals open the night they came from (Overnight signals).
    'hrv' ||
    'resting_hr' ||
    'resp_rate' ||
    'skin_temp' => SleepDetail(day: day),
    'readiness' || 'recovery' => ReadinessDetail(day: day),
    'wear' => DayTimelineScreen(day: day),
    _ => null,
  };

  /// [latestTs] is the stamp on the newest STORED point — the day the rank was
  /// computed for. `metric_series` gets a row only on a day that derives and
  /// the rollup is served for a week, so "Today sits at the 12th percentile"
  /// was printed unconditionally two rows under a hero saying "4 days ago".
  Widget _range3(
    BuildContext c,
    MetricSpec spec,
    List<double> win,
    Map<String, dynamic>? pct,
    int? latestTs,
  ) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final sorted = [...win]..sort();
    final lo = sorted.first, hi = sorted.last;
    final mid = sorted[sorted.length ~/ 2];
    final band = pct?['label']?.toString();
    final rank = (pct?['percentile_of_you'] as num?);
    final isToday = (daysBehind(latestTs) ?? 0) <= 0;
    final ordinal = rank == null ? '' : _ordinal(rank.round(), l);

    return Surface(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _stat(
                  p,
                  _fmt(spec, lo),
                  l?.metricDetailLowest ?? 'Lowest',
                ),
              ),
              Expanded(
                child: _stat(
                  p,
                  _fmt(spec, mid),
                  l?.metricDetailTypical ?? 'Typical',
                ),
              ),
              Expanded(
                child: _stat(
                  p,
                  _fmt(spec, hi),
                  l?.metricDetailHighest ?? 'Highest',
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x4),
          Text(
            rank == null
                ? (l?.metricDetailFromDaysCount(win.length) ??
                      'From ${win.length} of your own days.')
                : (isToday
                      ? (band == null
                            ? (l?.metricDetailPercentileTodayNoBand(ordinal) ??
                                  'Today sits at the $ordinal percentile of your own '
                                      'history.')
                            : (l?.metricDetailPercentileTodayBand(
                                    ordinal,
                                    band,
                                  ) ??
                                  'Today sits at the $ordinal percentile of your own '
                                      'history — $band.'))
                      : (band == null
                            ? (l?.metricDetailPercentileFromNoBand(
                                    axisDay(latestTs),
                                    ordinal,
                                  ) ??
                                  'Your reading from ${axisDay(latestTs)} sits at the '
                                      '$ordinal percentile of your own history.')
                            : (l?.metricDetailPercentileFromBand(
                                    axisDay(latestTs),
                                    ordinal,
                                    band,
                                  ) ??
                                  'Your reading from ${axisDay(latestTs)} sits at the '
                                      '$ordinal percentile of your own history — '
                                      '$band.'))),
            style: F.cap.copyWith(color: p.ink3, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// [n]th, localized. `{ordinal}` gets substituted whole into an ARB
  /// sentence, so this is the one place the suffix has to match the reader's
  /// language — an English "12th" inside a French sentence reads as broken,
  /// not translated.
  String _ordinal(int n, AppLocalizations? l) {
    switch (l?.localeName.split('_').first) {
      case 'fr':
        return n == 1 ? '1er' : '${n}e';
      case 'de':
        return '$n.';
      case 'es':
        return '$nº';
      case 'hi':
      case 'zh':
        // Neither language marks the ordinal with a suffix here — the
        // surrounding ARB sentence already carries the "the Nth" framing
        // (Hindi's postposition, Chinese's 第 prefix), so a bare number is
        // the correct rendering, not a fallback.
        return '$n';
      default:
        if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
        return '$n${const ['th', 'st', 'nd', 'rd'][n % 10 < 4 ? n % 10 : 0]}';
    }
  }

  Widget _stat(P p, String v, String l) => Column(
    children: [
      Text(v, style: F.n24.copyWith(color: p.ink)),
      const SizedBox(height: 3),
      Text(l, style: F.over.copyWith(color: p.ink3)),
    ],
  );

  /// Journal ↔ metric rank correlations. These are ASSOCIATIONS in your own
  /// history, which is why the copy says "on days you logged" and never
  /// "because".
  Widget _movers(BuildContext c, List<Map<String, dynamic>> movers) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final rows = movers.take(5).toList();
    return Column(
      children: [
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(color: p.line, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rows[i]['tag']?.toString() ?? '',
                              style: F.body.copyWith(color: p.ink),
                            ),
                            Text(
                              l?.metricDetailDaysWithWithout(
                                    (rows[i]['n_with'] as num? ?? 0).toInt(),
                                    (rows[i]['n_without'] as num? ?? 0).toInt(),
                                  ) ??
                                  '${rows[i]['n_with'] ?? 0} days with · '
                                      '${rows[i]['n_without'] ?? 0} without',
                              style: F.over.copyWith(color: p.ink3),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _signed(
                          rows[i]['delta'] as num?,
                          rows[i]['unit']?.toString(),
                        ),
                        style: F.body.copyWith(
                          color: p.on(
                            rows[i]['helped'] == true ? C.green : C.orange,
                          ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        Text(
          l?.metricDetailPatternsNotCauses ??
              'Patterns in your own logs, not causes.',
          style: F.over.copyWith(color: p.ink3, height: 1.5),
        ),
      ],
    );
  }

  String _signed(num? v, String? unit) {
    if (v == null) return '';
    final s = v.abs() >= 10
        ? v.abs().round().toString()
        : v.abs().toStringAsFixed(1);
    return '${v >= 0 ? '+' : '−'}$s${unit == null || unit.isEmpty ? '' : ' $unit'}';
  }

  String _fmt(MetricSpec spec, double v) => spec.unit == 'SD'
      ? '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)}'
      : metricValue(spec.unit, v);
}

/// Today's steps against the goal, as one small ring — the same [Ring]
/// painter Home's recovery/strain/sleep dials use, at a size that reads as a
/// detail beside the hero number rather than a fourth headline. The goal
/// itself is editable in place: tap it, type, hit the check — no dialog.
/// Same 500–100,000 bound as `LocalRepositoryImpl.setStepGoal` — this is the
/// UI writer of `step_goal`, through `AppState.updateProfile` directly rather
/// than through that method.
class _StepGoalGauge extends StatefulWidget {
  /// Null when today has not produced a steps value yet — the ring then
  /// shows only the empty track, never a fabricated 0%.
  final double? steps;
  final int goal;
  final Color color;
  final Future<void> Function() onSaved;

  const _StepGoalGauge({
    required this.steps,
    required this.goal,
    required this.color,
    required this.onSaved,
  });

  @override
  State<_StepGoalGauge> createState() => _StepGoalGaugeState();
}

class _StepGoalGaugeState extends State<_StepGoalGauge> {
  bool _editing = false;
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.goal}',
  );

  @override
  void didUpdateWidget(covariant _StepGoalGauge old) {
    super.didUpdateWidget(old);
    // The goal just saved (or changed under us some other way) — keep the
    // field in sync so reopening the editor shows the current value, not
    // the one it was first built with.
    if (!_editing && old.goal != widget.goal) {
      _ctrl.text = '${widget.goal}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = Typed.of(_ctrl.text);
    final typed = (t.bad || t.value == null) ? null : t.value!.round();
    if (typed == null) {
      setState(() => _editing = false);
      return;
    }
    if (typed < 500 || typed > 100000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A step goal of 500–100,000 is a real one. Nothing was saved.',
          ),
        ),
      );
      return;
    }
    setState(() => _editing = false);
    await context.read<AppState>().updateProfile({'step_goal': typed});
    // The parent's onSaved reloads and calls setState — never on a widget
    // that navigated away while the write was in flight.
    if (!mounted) return;
    await widget.onSaved();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final steps = widget.steps;
    final frac = steps == null || widget.goal <= 0 ? null : steps / widget.goal;
    return Surface(
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: Ring(
                    frac ?? 0,
                    widget.color,
                    p.track,
                    stroke: 7,
                    solid: true,
                  ),
                ),
                // No steps recorded yet is absent, not zero — the track alone
                // says that; a percentage here would fabricate a reading.
                if (frac != null)
                  Text(
                    '${(frac * 100).clamp(0, 999).round()}%',
                    style: F.over.copyWith(color: p.ink),
                  ),
              ],
            ),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: _editing
                ? Row(
                    children: [
                      Expanded(
                        child: OsTextField(
                          controller: _ctrl,
                          label: 'Goal',
                          keyboard: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: S.x2),
                      Pressable(
                        semanticLabel: 'Save step goal',
                        onTap: _save,
                        child: Icon(LucideIcons.check, size: 20, color: p.ink),
                      ),
                    ],
                  )
                : Pressable(
                    semanticLabel: 'Edit daily step goal',
                    onTap: () => setState(() => _editing = true),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Goal', style: F.over.copyWith(color: p.ink3)),
                            const SizedBox(width: S.x1),
                            Icon(LucideIcons.pencil, size: 12, color: p.ink3),
                          ],
                        ),
                        Text(
                          '${thousands(widget.goal)} steps',
                          style: F.body.copyWith(color: p.ink),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════ shared detail chrome ═══════════════════

/// Every detail screen is the same frame: a back bar, then a scroll. Keeping it
/// in one function is the reason the back affordance is in the same place on
/// all of them.
Widget detailScaffold(
  BuildContext c,
  String title,
  List<Widget> body, {
  String sub = '',
  Widget? trailing,
  bool embedded = false,
}) {
  if (embedded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: body,
    );
  }
  final p = P.of(c);
  return Scaffold(
    backgroundColor: p.bg,
    body: Stack(
      children: [
        // The same top light the tabs have (build 85), neutral here: a detail
        // screen belongs to whichever pillar opened it.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 240,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.glow(C.n400), p.bg.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x4),
                child: NavBar(
                  title,
                  sub: sub,
                  trailing: trailing,
                  onBack: () => Navigator.of(c).maybePop(),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x12),
                  children: body,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════ which day a detail screen is showing ═══════════════════
//
// Nothing prunes `day_result`, so an install holds every day it has ever
// derived — and until this existed every single-day screen resolved `days.first`
// and stopped there. The chart on this screen would happily draw the night
// somebody's sleep collapsed and offer no way into it.

/// The day a single-day screen should load: the one it was OPENED with when
/// that day exists, else the screen's own idea of now, else the newest day on
/// disk.
///
/// [want] is the day the caller asked for and [prefer] the screen's own
/// resolution (`today_day`, a held-over night). With no [want] this is exactly
/// what every loader did inline, which is why passing no day changes nothing.
String? pickDay(List<String> days, String? want, [String? prefer]) {
  final d = want ?? prefer;
  // No derived days at all: there is nothing to fall back TO, so the caller's
  // own answer stands or the screen renders its absence.
  if (days.isEmpty) return d;
  if (d != null && days.contains(d)) return d;
  return days.first;
}

/// 'Today' when it is, otherwise the day itself. Never "N days ago" — a
/// control you steer with needs the name of the place, not the distance to it.
String dayNavLabel(String? day) =>
    (_dayBehind(day) ?? 1) <= 0 ? 'Today' : prettyDay(day);

int? _dayBehind(String? dayId) {
  final d = dayId == null ? null : DateTime.tryParse(dayId);
  return d == null ? null : calendarDaysBetween(d, DateTime.now());
}

/// The calendar, restricted to the days that exist. A picker that offers an
/// empty day is a dead end, so [days] greys out everything it does not contain.
Future<String?> chooseDay(
  BuildContext c,
  List<String> days,
  String? current,
) async {
  if (days.isEmpty) return null;
  final have = days.toSet();
  final sorted = [...days]..sort(); // oldest → newest
  final first = DateTime.parse(sorted.first);
  final last = DateTime.parse(sorted.last);
  final want = DateTime.tryParse(current ?? '') ?? last;
  final picked = await showDatePicker(
    context: c,
    initialDate: want.isBefore(first)
        ? first
        : (want.isAfter(last) ? last : want),
    firstDate: first,
    lastDate: last,
    selectableDayPredicate: (d) => have.contains(dayLabelOf(d)),
    helpText:
        AppLocalizations.of(c)?.metricDetailChooseDayHelp ?? 'Choose a day',
  );
  return picked == null ? null : dayLabelOf(picked);
}

/// The day stepper every single-day screen wears under its nav bar.
///
/// [days] is `availableDays()` — NEWEST FIRST, and only days that derived. Both
/// arrows and the picker walk that list, so there is no way to steer onto a day
/// this install has no record of. With fewer than two days there is nowhere to
/// go and the control renders nothing rather than two dead arrows.
class DayNav extends StatelessWidget {
  final String? day;
  final List<String> days;
  final ValueChanged<String> onDay;

  const DayNav({
    super.key,
    required this.day,
    required this.days,
    required this.onDay,
  });

  @override
  Widget build(BuildContext c) {
    if (days.length < 2) return const SizedBox.shrink();
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final i = days.indexOf(day ?? '');
    // days is newest first: the OLDER day is further down the list.
    final older = i < 0
        ? days.first
        : (i + 1 < days.length ? days[i + 1] : null);
    final newer = i > 0 ? days[i - 1] : null;

    Widget arrow(IconData icon, String label, String? to) => Opacity(
      opacity: to == null ? .35 : 1,
      child: Pressable(
        onTap: to == null ? null : () => onDay(to),
        semanticLabel: label,
        child: Icon(icon, size: 20, color: p.ink),
      ),
    );

    return Container(
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
      child: Row(
        children: [
          arrow(
            LucideIcons.chevronLeft,
            l?.metricDetailPreviousDay ?? 'Previous day',
            older,
          ),
          Expanded(
            child: Pressable(
              onTap: () async {
                final picked = await chooseDay(c, days, day);
                if (picked != null && picked != day) onDay(picked);
              },
              semanticLabel:
                  l?.metricDetailChooseDayShowing(dayNavLabel(day)) ??
                  'Choose a day. Showing ${dayNavLabel(day)}',
              child: Text(
                dayNavLabel(day),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          arrow(
            LucideIcons.chevronRight,
            l?.metricDetailNextDay ?? 'Next day',
            newer,
          ),
          // Back to the newest day in one tap, however far back this is.
          if (newer != null) ...[
            Pressable(
              semanticLabel: 'Jump to today',
              onTap: () => onDay(days.first),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x2),
                child: Text(
                  'Today',
                  style: F.cap.copyWith(
                    color: p.on(C.blue),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Whether [key]'s trend is withheld. The personal build charts skin
/// temperature (its own band's nights only; see [MetricData.load]) rather than
/// opening a screen that says it will not.
bool metricSuppressed(String key) =>
    specOf(key).suppress != null && !(kPersonalSideload && key == 'skin_temp');

/// [DayNav] and the gap under it, spread into a `detailScaffold` body — or
/// nothing at all when there is only one day to look at.
List<Widget> dayNavRow(
  String? day,
  List<String> days,
  ValueChanged<String> onDay,
) => [DayNav(day: day, days: days, onDay: onDay), const SizedBox(height: S.x3)];

/// A plain door onto another screen. Deliberately quiet: a doorway is not a
/// card, and a metric screen that grows a second loud card stops having a
/// headline.
Widget detailLinkRow(
  BuildContext c,
  IconData icon,
  String title,
  String sub,
  VoidCallback onTap,
) {
  final p = P.of(c);
  return Pressable(
    onTap: onTap,
    semanticLabel: '$title: $sub',
    child: Container(
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(
        gradient: p.cardFace,
        borderRadius: R.rLg,
        border: Border.all(color: p.edge),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
            child: Icon(icon, size: 16, color: p.ink2),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: F.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(sub, style: F.over.copyWith(color: p.ink3)),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ],
      ),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: e.$2, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(e.$1, style: F.over.copyWith(color: p.ink2)),
            ],
          ),
      ],
    );
  }
}

/// The mean of the [window] slots ending at each slot, or null where fewer
/// than [minCount] of them were measured. Gaps are never filled.
List<double?> rollingMean(
  List<double?> series,
  int window, {
  int minCount = 1,
}) => [
  for (var i = 0; i < series.length; i++)
    () {
      final have = [
        for (var j = i - window + 1; j <= i; j++)
          if (j >= 0) ?series[j],
      ];
      return have.length < minCount
          ? null
          : have.reduce((a, b) => a + b) / have.length;
    }(),
];
