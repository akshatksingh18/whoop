// SLEEP — one question, answered in three seconds, then revealed by scrolling.
//
// "How did my night go?" → what happened → how it compares to YOUR nights →
// what stood out → the signals underneath → the one thing to do tonight. Same
// screen, layered by scroll depth; there is no advanced mode to switch into.
//
// There is no sleep score. No composite exists in the pipeline, and inventing
// one here would mean choosing weights in a UI file. What replaces it is the
// comparison every "86" is a lossy summary of: last night against the middle
// half of the user's OWN recent nights, per measure, with the night count
// attached. A quartile band needs no thresholds, no population norms and no
// constants — it is the user's own distribution, so it cannot be wrong about
// somebody it was never fitted to.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/local_repository.dart';
import '../../state/app_state.dart';
import '../../models/metric.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'investigate.dart';
import 'metric_detail.dart';

/// Nights of history before a personal normal is claimed at all. Below this the
/// quartiles of three or four nights are noise wearing a band's clothing.
const _minNights = 7;

/// Nights before "your shortest night in N" is worth saying. A record inside a
/// week is a coincidence.
const _recordNights = 14;

/// How far back the comparison window reaches. Long enough to be stable, short
/// enough to still be "you lately" rather than "you last season".
const _window = 28;

SleepStage _stageOf(Object? raw) => switch (raw?.toString()) {
      'wake' || 'awake' => SleepStage.awake,
      'rem' => SleepStage.rem,
      'deep' => SleepStage.deep,
      _ => SleepStage.light,
    };

/// Two call sites drew this byte-identical card; one const so they cannot
/// drift apart.
const _noOvernightLines = StatusCard(
  'No overnight signal lines',
  'No overnight recordings reached this day.',
  icon: LucideIcons.activity,
);

/// Local noon of a 'YYYY-MM-DD' day, in epoch seconds — the stamp `getChart`
/// puts on that day's stored scalar. Used to cut the history at last night, so
/// a night is never compared against a window that contains itself.
int? _noonOf(String? day) => day == null
    ? null
    : (DateTime.tryParse('$day 12:00:00')?.millisecondsSinceEpoch ?? 0) ~/ 1000;

/// The middle half of the user's own nights, plus its median and its count.
///
/// Nearest-rank quartiles, no interpolation: with 20-odd samples the difference
/// is smaller than a minute and interpolation invents a value nobody slept.
/// Null below [_minNights] — the screen says so rather than drawing a band.
({double lo, double mid, double hi, int n})? _band(List<double> xs) {
  if (xs.length < _minNights) return null;
  final s = [...xs]..sort();
  double q(double f) => s[((s.length - 1) * f).round()];
  return (lo: q(.25), mid: q(.5), hi: q(.75), n: s.length);
}

String _pct(double v) => '${v.round()}%';
String _pts(double v) => '${v.round()} points';

class SleepData {
  final String? day;
  final Map<String, dynamic> night;
  final Map<String, dynamic> timeline;
  final Metric need, debt, bedtime;

  /// The user's own recent nights, LAST NIGHT EXCLUDED, oldest→newest. Minutes
  /// for duration and deep, whole percent for efficiency, epoch seconds for
  /// onset. Empty until enough nights exist, which the screen renders as a
  /// [StatusCard] rather than as a comparison against nothing.
  final List<double> tstHistory, deepHistory, effHistory;
  final List<int> onsetHistory;

  const SleepData({
    this.day,
    this.night = const {},
    this.timeline = const {},
    this.need = Metric.empty,
    this.debt = Metric.empty,
    this.bedtime = Metric.empty,
    this.tstHistory = const [],
    this.deepHistory = const [],
    this.effHistory = const [],
    this.onsetHistory = const [],
  });

  bool get hasNight => night['duration_min'] is num;

  /// Stage samples for the painter — the segment list resampled onto a fixed
  /// number of columns so a four-hour segment and a four-minute one stay in
  /// proportion.
  List<SleepStage> get stages {
    final pts = night['hypnogram'];
    if (pts is! List || pts.length < 2) return const [];
    final ts = <int>[], st = <SleepStage>[];
    for (final e in pts) {
      if (e is Map && e['t'] is num) {
        ts.add((e['t'] as num).round());
        st.add(_stageOf(e['stage']));
      }
    }
    if (ts.length < 2) return const [];
    final t0 = ts.first, t1 = ts.last;
    if (t1 <= t0) return const [];
    const cols = 240;
    return [
      for (var i = 0; i < cols; i++)
        st[_indexAt(ts, t0 + ((t1 - t0) * i / cols).round())],
    ];
  }

  static int _indexAt(List<int> ts, int t) {
    var lo = 0;
    for (var i = 0; i < ts.length; i++) {
      if (ts[i] <= t) lo = i;
    }
    return lo;
  }

  /// The trailing [_window] values of a stored scalar series, with any point
  /// dated on or after [cut] dropped.
  static List<double> _trailing(Object? chart, int? cut, {double scale = 1}) {
    final pts = [
      for (final p in pointsOf(chart))
        if (cut == null || p.t < cut) p.v * scale,
    ];
    return pts.length <= _window ? pts : pts.sublist(pts.length - _window);
  }

  static Future<SleepData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    // THE NIGHT `getToday` ACTUALLY SERVED. Home's Sleep card is that night, so
    // tapping it has to open that night. Resolving on `today_day` alone opened
    // a day that has a day_result but no night — wear the band all day with it
    // off overnight and the card said "7h 04m" while this screen answered "No
    // night to show" about the same tap.
    var day = heldOverNightOf(today) ??
        (today['status'] as Map?)?['today_day']?.toString();
    final days = await repo.availableDays();
    if (days.isNotEmpty && (day == null || !days.contains(day))) day = days.first;
    if (day == null) return const SleepData();

    final night = await repo.getDaySleepV2(day);
    final timeline = await repo.getDayTimeline(day);
    final cd = await repo.getInsights();
    final coach = cd['sleep_coach'];
    final needEnv = coach is Map ? coach['need'] : null;
    final needSec = envValue(needEnv)?['need_sec'] as num?;
    final debtEnv = cd['sleep_debt'];
    final debtH = envValue(debtEnv)?['debt_hours'] as num?;
    final bedEnv = coach is Map ? coach['bedtime'] : null;

    // Personal history for the comparisons. These are `metric_series` reads —
    // one small row per day per key — not day bundles, so the whole comparison
    // costs three scalar queries and one window query rather than 28 payload
    // decodes.
    final cut = _noonOf(day);
    final tst = _trailing(await repo.getChart('sleep'), cut);
    final deep = _trailing(await repo.getChart('deep'), cut);
    // Stored as whole percent; the night's own `efficiency` is 0…1.
    final eff = _trailing(await repo.getChart('efficiency'), cut);
    final wins = await repo.sleepWindows(days: _window + 1);
    final onsets = <int>[
      for (final w in wins.reversed)
        if (w['date'] != day && w['onset_ts'] is num) (w['onset_ts'] as num).round(),
    ];

    return SleepData(
      day: day,
      night: night,
      timeline: timeline,
      need: envMetric(needEnv, needSec == null ? null : needSec / 60, unit: 'min'),
      debt: envMetric(debtEnv, debtH == null ? null : debtH * 60, unit: 'min'),
      bedtime:
          envMetric(bedEnv, envValue(bedEnv)?['bedtime_min_of_day'] as num?),
      tstHistory: tst,
      deepHistory: deep,
      effHistory: eff,
      onsetHistory: onsets,
    );
  }
}

class SleepDetail extends StatefulWidget {
  final SleepData? data;
  const SleepDetail({super.key, this.data});

  @override
  State<SleepDetail> createState() => _SleepDetailState();
}

class _SleepDetailState extends State<SleepDetail> {
  SleepData? _d;
  bool _loading = true;
  bool _saving = false; // an override write + its forced re-derive is in flight
  double? _scrub; // 0..1 across the night

  /// Why the last correction did not take. Null when it did.
  String? _overrideFailed;

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
      final d = await SleepData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final d = _d ?? const SleepData();

    if (_loading && _d == null) {
      return detailScaffold(c, 'Sleep', const [
        SizedBox(height: S.x8),
        Center(child: CircularProgressIndicator()),
      ]);
    }

    if (!d.hasNight) {
      return detailScaffold(c, 'Sleep', [
        const SizedBox(height: S.x2),
        const StatusCard(
          'No night to show',
          'No stretch of band recordings long enough to score.',
          fix: 'Wear the band overnight and sync in the morning',
          icon: LucideIcons.moon,
        ),
      ]);
    }

    final p = P.of(c);
    final n = d.night;
    final unusual = _unusual(c, p, d, n);

    return detailScaffold(c, 'Sleep', sub: (d.day ?? '').toUpperCase(), [
      // ── 1 · THE ANSWER ──
      _answer(c, p, n),

      // ── 2 · THE NIGHT ITSELF ──
      const SizedBox(height: S.x3),
      _night(c, p, d, n),
      if (_scrub != null) _scrubCard(c, p, d),

      // ── 2b · WHOSE WINDOW IS THIS ──
      ...?_windowCard(c, p, d, n),

      // ── 3 · WHAT IT WAS MADE OF ──
      Section('Stages', _stages(c, p, n, n['duration_min'] as num?)),

      // ── 4 · AGAINST THE USER'S OWN NIGHTS ──
      if (_versusUsual(c, p, d, n) case final versus?)
        Section('Against your usual', versus),

      // ── 5 · WHAT STOOD OUT ──
      // Named after the night the nav bar is already showing. "Unusual last
      // night — Nothing stood out." is a present-tense all-clear, and it was
      // printed over a night that could be days old.
      if (unusual != null)
        Section(
            (daysBehind(_noonOf(d.day)) ?? 0) <= 0
                ? 'Unusual last night'
                : 'Unusual on ${prettyDay(d.day)}',
            unusual),

      // ── 6 · THE SIGNALS UNDERNEATH ──
      Section('Overnight signals', _overnight(c, p, d)),

      // ── 7 · ONE TAKEAWAY ──
      Section('Tonight', _tonight(c, p, d)),

      const SizedBox(height: S.x5),
      investigateRow(c, () => go(c, const Investigate('sleep'))),
    ]);
  }

  /// Total sleep, when it ran, and the two ratios that qualify it. Everything
  /// here is measured; nothing is a judgement.
  Widget _answer(BuildContext c, P p, Map<String, dynamic> n) {
    final tst = n['duration_min'] as num?;
    final eff = n['efficiency'] as num?;
    final inBed = n['in_bed_min'] as num?;
    final from = clockOfTs(n['onset_ts'] as num?);
    final to = clockOfTs(n['wake_ts'] as num?);
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(hm(tst), style: F.n48.copyWith(color: p.ink)),
        const SizedBox(height: S.x1),
        Text('Total sleep', style: F.cap.copyWith(color: p.ink3)),
        if (from.isNotEmpty && to.isNotEmpty) ...[
          const SizedBox(height: S.x4),
          Row(children: [
            Icon(LucideIcons.moon, size: 15, color: p.ink3),
            const SizedBox(width: S.x2),
            Flexible(
              child: Text('$from → $to',
                  style: F.body
                      .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            ),
          ]),
        ],
        if (inBed != null || eff != null) ...[
          const SizedBox(height: S.x4),
          InlineMetrics([
            if (inBed != null) ('IN BED', hm(inBed), C.indigo),
            if (eff != null)
              ('ASLEEP OF THAT', _pct(eff * 100), C.green),
          ]),
        ],
      ]),
    );
  }

  /// Where this night's window came from, and the user's say over it.
  ///
  /// `sleep_source` has been on the day bundle all along — 'auto' (staged from
  /// the signals), 'auto_fallback' (the HR-led guess staging falls back to when
  /// it cannot find the edges), 'manual' / 'confirmed' (the user's own). The
  /// repository comment already said it "drives the Sleep screen's confirm
  /// prompt + edit affordance"; nothing did, and `sleep_override` had no writer
  /// anywhere in the app, so the derive engine's user-window restage path could
  /// never run and a mis-staged night was uncorrectable.
  ///
  /// NAP EDITS ARE DELIBERATELY NOT HERE. `applyNapEdits` reads a `nap_edits`
  /// table that nothing in the app writes either; a control that appeared to
  /// edit naps while the edits went nowhere would be worse than the absence.
  /// It needs a writer first.
  List<Widget>? _windowCard(
      BuildContext c, P p, SleepData d, Map<String, dynamic> n) {
    final day = d.day;
    final t0 = (n['onset_ts'] as num?)?.round();
    final t1 = (n['wake_ts'] as num?)?.round();
    if (day == null || t0 == null || t1 == null) return null;
    final source = (n['sleep_source'] as String?) ?? 'auto';
    final mine = source == 'manual' || source == 'confirmed';
    final fallback = source == 'auto_fallback';

    final busy = _saving;
    return [
      const SizedBox(height: S.x3),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(mine ? LucideIcons.userCheck : LucideIcons.wandSparkles,
                size: 16, color: p.ink3),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text(
                mine
                    ? 'You set this window'
                    : fallback
                        ? 'This window was inferred from heart rate'
                        : 'This window was staged from the signals',
                style: F.body.copyWith(color: p.ink),
              ),
            ),
          ]),
          if (fallback) ...[
            const SizedBox(height: S.x2),
            Text(
              'Staging could not find the edges, so the times are a best '
              'guess.',
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
          const SizedBox(height: S.x2),
          Wrap(spacing: S.x2, children: [
            if (fallback)
              TextButton(
                onPressed: busy ? null : () => _confirmWindow(day),
                child: const Text('These times are right'),
              ),
            TextButton(
              onPressed: busy ? null : () => _editWindow(day, t0, t1),
              child: Text(mine ? 'Change the times' : 'Set the times myself'),
            ),
            if (mine)
              TextButton(
                onPressed: busy ? null : () => _clearWindow(day),
                child: const Text('Back to automatic'),
              ),
          ]),
          if (busy) ...[
            const SizedBox(height: S.x2),
            Text('Re-analysing the night…',
                style: F.cap.copyWith(color: p.ink3)),
          ],
          if (!busy && _overrideFailed != null) ...[
            const SizedBox(height: S.x3),
            StatusCard(
              'That correction has not been applied',
              _overrideFailed!,
              icon: LucideIcons.triangleAlert,
            ),
          ],
        ]),
      ),
    ];
  }

  Future<void> _confirmWindow(String day) =>
      _runOverride(() => context.read<AppState>().confirmSleep(day));

  Future<void> _clearWindow(String day) =>
      _runOverride(() => context.read<AppState>().clearSleepOverride(day));

  /// Two pickers, seeded from the window we already have — the user is
  /// correcting times, not entering a date, so the DATES stay as measured and
  /// only the clock moves. A wake that lands before the onset belongs to the
  /// next morning.
  Future<void> _editWindow(String day, int t0, int t1) async {
    final onset = DateTime.fromMillisecondsSinceEpoch(t0 * 1000);
    final wake = DateTime.fromMillisecondsSinceEpoch(t1 * 1000);
    final bed = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(onset),
      helpText: 'WHEN YOU GOT INTO BED',
    );
    if (bed == null || !mounted) return;
    final up = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(wake),
      helpText: 'WHEN YOU GOT UP',
    );
    if (up == null || !mounted) return;
    final newOnset =
        DateTime(onset.year, onset.month, onset.day, bed.hour, bed.minute);
    // A wake at or before the onset is the next morning. `day + 1` rather than
    // adding a Duration: DateTime normalises the overflow, and it is calendar
    // arithmetic across a possible DST boundary, not a span of elapsed time.
    var newWake =
        DateTime(onset.year, onset.month, onset.day, up.hour, up.minute);
    if (!newWake.isAfter(newOnset)) {
      newWake = DateTime(
          onset.year, onset.month, onset.day + 1, up.hour, up.minute);
    }
    await _runOverride(
      () => context.read<AppState>().setSleepOverride(day, newOnset, newWake),
    );
  }

  /// Every override path is the same shape: write it, wait for the forced
  /// re-derive, then reload the screen from what the engine produced. The
  /// screen must not keep drawing the old night's numbers under a new window.
  Future<void> _runOverride(Future<void> Function() write) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _overrideFailed = null;
    });
    String? failed;
    try {
      await write();
    } catch (e) {
      failed = '$e';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    final before = _source;
    if (mounted) await _load();
    if (!mounted) return;
    // EVERY failure below this screen is silent: the forced re-derive catches
    // and logs its own throw, and it returns at its first line when another
    // re-analysis is already running. Both leave the write in the database and
    // the night on screen unchanged — indistinguishable from a correction that
    // worked, which is how a rejected one got dropped without a word. The
    // window's source changes on all three actions, so an unchanged source
    // means nothing was restaged.
    if (failed != null || _source == before) {
      setState(() => _overrideFailed = failed ??
          'The night was not re-analysed — another re-analysis was already '
              'running, or it failed. The times you set are saved; '
              'Re-analyze everything on Your data applies them.');
    }
  }

  /// Where the drawn window came from: 'auto', 'auto_fallback', 'manual' or
  /// 'confirmed'.
  String? get _source => (_d?.night['sleep_source'] as String?) ?? 'auto';

  /// The hypnogram, as the centrepiece rather than as an illustration. The
  /// cycle count rides underneath it because it is a property of this shape,
  /// not a section of its own.
  Widget _night(BuildContext c, P p, SleepData d, Map<String, dynamic> n) {
    final stages = d.stages;
    if (stages.isEmpty) {
      return const StatusCard(
        'No hypnogram for this night',
        'Staging needs movement and beat timing. One was missing.',
        icon: LucideIcons.chartNoAxesColumn,
      );
    }
    final t0 = (n['onset_ts'] as num?)?.round();
    final t1 = (n['wake_ts'] as num?)?.round();
    final cycles = (n['cycle_count'] as num?)?.toInt() ?? 0;
    final mean = n['cycles_mean_min'] as num?;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ChartFrame(
          title: 'Through the night',
          unit: 'stage',
          height: 132,
          xLabels: [
            clockOfTs(t0),
            if (t0 != null && t1 != null && t1 > t0)
              clockOfTs(t0 + (t1 - t0) ~/ 2),
            clockOfTs(t1),
          ],
          // Driven by the night, not by the enum: a night with no REM in
          // it used to still print REM in its key.
          legend: [
            for (final e in Hypnogram.legend(p))
              if (stages.any((s) => s.label == e.$1)) e,
          ],
          child: _hypnogram(c, p, stages, n),
        ),
        const SizedBox(height: S.x2),
        Text(
          cycles > 0
              ? 'Tap or drag the chart for any moment. $cycles cycles'
                  '${mean == null ? '' : ', ${hm(mean)} on average'}.'
              : 'Tap or drag the chart for any moment of the night.',
          style: F.over.copyWith(color: p.ink3, height: 1.5),
        ),
      ]),
    );
  }

  /// A [Scrubber], not a drag gesture: what matters is where the pointer IS,
  /// and the 44 pt tap rule does not apply to a continuous readout. What DOES
  /// apply is that the readout has to exist without a pointer — [Scrubber]
  /// carries the slider role and speaks [describe] at each step.
  Widget _hypnogram(
          BuildContext c, P p, List<SleepStage> stages, Map<String, dynamic> n) =>
      Scrubber(
        value: _scrub,
        onChanged: (v) => setState(() => _scrub = v),
        label: 'Hypnogram',
        describe: (v) {
          final t0 = (n['onset_ts'] as num?)?.toInt();
          final t1 = (n['wake_ts'] as num?)?.toInt();
          final st = stages.isEmpty
              ? null
              : stages[(v * (stages.length - 1)).round().clamp(0, stages.length - 1)];
          final at = (t0 == null || t1 == null || t1 <= t0)
              ? '${(v * 100).round()}% through the night'
              : clockOfTs(t0 + ((t1 - t0) * v).round());
          return st == null ? at : '$at, ${_stageName(st)}';
        },
        child: SizedBox(
          height: 132,
          child: Stack(children: [
            CustomPaint(
                size: Size.infinite,
                painter: Hypnogram(stages, p, t: animate(c, 1))),
            if (_scrub != null)
              // Aligned by fraction rather than by a measured offset, so the
              // cursor needs no width from the layout.
              Align(
                alignment: Alignment(_scrub! * 2 - 1, 0),
                child: SizedBox(width: 2, height: double.infinity,
                    child: ColoredBox(color: p.ink)),
              ),
          ]),
        ),
      );

  /// What every signal read at the scrubbed instant. Each line abstains on its
  /// own — a night with no respiration series still shows heart rate.
  Widget _scrubCard(BuildContext c, P p, SleepData d) {
    final n = d.night;
    final t0 = (n['onset_ts'] as num?)?.toInt();
    final t1 = (n['wake_ts'] as num?)?.toInt();
    if (t0 == null || t1 == null || t1 <= t0) return const SizedBox.shrink();
    final t = t0 + ((t1 - t0) * _scrub!).round();

    num? at(String key) {
      final list = d.timeline[key];
      if (list is! List) return null;
      num? best;
      var bestGap = 1 << 30;
      for (final e in list) {
        if (e is Map && e['t'] is num && e['v'] is num) {
          final gap = ((e['t'] as num).round() - t).abs();
          if (gap < bestGap) {
            bestGap = gap;
            best = e['v'] as num;
          }
        }
      }
      return bestGap > 900 ? null : best;
    }

    final stages = d.stages;
    final stage = stages.isEmpty
        ? null
        : stages[(_scrub! * (stages.length - 1)).round()];
    final items = <(String, String, Color)>[
      if (at('hr') != null) ('Heart rate', '${at('hr')!.round()} bpm', C.red),
      if (at('hrv') != null) ('HRV', '${at('hrv')!.round()} ms', C.green),
      if (at('resp') != null)
        ('Breathing', '${at('resp')!.toStringAsFixed(1)} br/min', C.teal),
      if (at('skin_temp') != null)
        ('Temp', at('skin_temp')!.toStringAsFixed(2), C.orange),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: Surface(
        color: p.card2,
        elevation: 0,
        child: Column(children: [
          Row(children: [
            Text(clockOfTs(t),
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (stage != null)
              Pill(_stageName(stage), Hypnogram.pigment[stage] ?? C.blue),
          ]),
          if (items.isEmpty) ...[
            const SizedBox(height: S.x3),
            Text('No signal recorded at this moment.',
                style: F.cap.copyWith(color: p.ink3)),
          ] else ...[
            const SizedBox(height: S.x4),
            InlineMetrics(items),
          ],
        ]),
      ),
    );
  }

  String _stageName(SleepStage s) => switch (s) {
        SleepStage.awake => 'Awake',
        SleepStage.rem => 'REM',
        SleepStage.light => 'Light sleep',
        SleepStage.deep => 'Deep sleep',
      };

  /// One stage of the night: a name, its minutes and its share. The two
  /// numbers are non-flex, so the minutes column and the percent column each
  /// have ONE right edge down the whole table — `Flexible` shrink-wrapped
  /// every row to its own width and parked the leftover after the percentage,
  /// so neither column lined up and neither reached the card edge the old
  /// comment here claimed they did. The percent slot is fixed but SCALED, so
  /// it never wraps "19%" onto two lines; above the big-text threshold the
  /// row restacks rather than squeeze, exactly like [MetricRow].
  Widget _stageRow(BuildContext c, P p, (String, num?, Color) s, num total) {
    final dot = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle));
    final name = Text(s.$1, style: F.body.copyWith(color: p.ink));
    final minutes = Text(hm(s.$2),
        style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600));
    final share = SizedBox(
      width: MediaQuery.textScalerOf(c).scale(34),
      child: Text(
        total == 0 ? '' : '${((s.$2! / total) * 100).round()}%',
        textAlign: TextAlign.right,
        style: F.cap.copyWith(color: p.ink3),
      ),
    );
    if (!bigText(c)) {
      return Row(children: [
        dot,
        const SizedBox(width: S.x3),
        Expanded(child: name),
        minutes,
        const SizedBox(width: S.x3),
        share,
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      dot,
      const SizedBox(width: S.x3),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          name,
          const SizedBox(height: S.x1),
          // Wrap, not Row: at 3.1× "1h 25m" alone is most of the card, so the
          // share has to be allowed onto a second line.
          Wrap(spacing: S.x3, runSpacing: S.x1, children: [minutes, share]),
        ]),
      ),
    ]);
  }

  Widget _stages(BuildContext c, P p, Map<String, dynamic> n, num? tst) {
    final rows = <(String, num?, Color)>[
      ('Deep', n['deep_min'] as num?, C.blue),
      ('REM', n['rem_min'] as num?, C.teal),
      ('Light', n['light_min'] as num?, C.sky),
      ('Awake', n['awake_min'] as num?, C.orange),
    ];
    final present = [for (final r in rows) if (r.$2 != null) r];
    if (present.isEmpty) {
      return const StatusCard(
        'No stage split for this night',
        'No beat timing across the whole window.',
        icon: LucideIcons.chartNoAxesColumn,
      );
    }
    // ONE denominator, and it is the whole in-bed span. Awake sits OUTSIDE
    // total sleep time (`tst_sec` and `waso_sec` are mutually exclusive), so
    // dividing all four by TST inflated the Awake share and made the four rows
    // sum past 100% in a list a user can add up.
    final awake = (n['awake_min'] as num?) ?? 0;
    final asleep = tst ??
        present
            .where((r) => r.$1 != 'Awake')
            .fold<num>(0, (a, r) => a + r.$2!);
    final total = asleep + awake;
    return Column(children: [
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(children: [
          for (var i = 0; i < present.length; i++) ...[
            if (i > 0) Divider(color: p.line, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x3),
              child: _stageRow(c, p, present[i], total),
            ),
          ],
        ]),
      ),
      const SizedBox(height: S.x2),
      // The stager is a wrist ESTIMATE and Deep is the weakest of the four —
      // an HR-depth overlay, not an EEG read. Said once, here, rather than
      // decorating every number with a caveat.
      Text('Shares of your time in bed. Deep is the least certain of the four.',
          style: F.over.copyWith(color: p.ink3, height: 1.5)),
    ]);
  }

  // ── AGAINST YOUR USUAL ────────────────────────────────────────────────────

  /// The four comparisons that used to be five progress bars against invented
  /// denominators (`1 - waso/120`, `1 - sol/3600`) — numbers with no owner,
  /// which moved when nothing physiological had. Each row is now the user's own
  /// distribution: the middle half of their recent nights, and where last night
  /// landed in it.
  ///
  /// This section absorbs the separate "what was different" block a delta table
  /// would have been. Deltas and verdicts are the same comparison rendered
  /// twice; the strip IS the delta, the sentence beside it IS the verdict.
  Widget? _versusUsual(
      BuildContext c, P p, SleepData d, Map<String, dynamic> n) {
    final rows = <Widget>[];

    final tst = (n['duration_min'] as num?)?.toDouble();
    if (tst != null) {
      rows.add(_Compare(
        label: 'Time asleep',
        value: hm(tst),
        tonight: tst,
        history: d.tstHistory,
        color: C.indigo,
        low: 'shorter than usual',
        high: 'longer than usual',
        fmt: (v) => hm(v),
        dfmt: (v) => hm(v),
      ));
    }

    final deep = (n['deep_min'] as num?)?.toDouble();
    if (deep != null) {
      rows.add(_Compare(
        label: 'Deep sleep',
        value: hm(deep),
        tonight: deep,
        history: d.deepHistory,
        color: C.blue,
        low: 'less than usual',
        high: 'more than usual',
        fmt: (v) => hm(v),
        dfmt: (v) => hm(v),
      ));
    }

    final eff = (n['efficiency'] as num?)?.toDouble();
    if (eff != null) {
      rows.add(_Compare(
        label: 'Asleep while in bed',
        value: _pct(eff * 100),
        tonight: eff * 100,
        history: d.effHistory,
        color: C.green,
        low: 'lower than usual',
        high: 'higher than usual',
        fmt: _pct,
        dfmt: _pts,
      ));
    }

    // Timing is measured on an axis anchored at last night's onset: every past
    // night becomes signed minutes relative to it, wrapped across midnight, so
    // 11:50 PM and 12:10 AM are twenty minutes apart rather than 23 hours. The
    // band edges are formatted back into clock times, which is the only form
    // anyone reads a bedtime in.
    final onset = (n['onset_ts'] as num?)?.round();
    if (onset != null && d.onsetHistory.isNotEmpty) {
      final rel = [for (final o in d.onsetHistory) _relMinutes(o, onset)];
      rows.add(_Compare(
        label: 'Fell asleep',
        value: clockOfTs(onset),
        tonight: 0,
        history: rel,
        color: C.purple,
        low: 'earlier than usual',
        high: 'later than usual',
        fmt: (v) => clockOfTs(onset + (v * 60).round()),
        dfmt: (v) => hm(v),
      ));
    }

    final have = [
      d.tstHistory.length,
      d.deepHistory.length,
      d.effHistory.length,
      d.onsetHistory.length,
    ].reduce(math.max);

    // Title and the COUNT, no prose. The sentence about population averages
    // was slop; "3 of 7 nights so far" is the one thing on this card a user can
    // act on — it says the comparison is coming and when. Dropping the whole
    // card took the count with it.
    if (rows.isEmpty || have < _minNights) {
      return StatusCard(
        'Not enough nights to compare',
        '',
        fix: '$have of $_minNights nights so far',
        icon: LucideIcons.chartNoAxesColumn,
      );
    }

    return Column(children: [
      Surface(
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x5),
            rows[i],
          ],
        ]),
      ),
      const SizedBox(height: S.x2),
      Text('The bar is the middle half of your own nights.',
          style: F.over.copyWith(color: p.ink3, height: 1.5)),
    ]);
  }

  /// Signed minutes from [ref] to [t], as times of day, wrapped to ±12 h.
  static double _relMinutes(int t, int ref) {
    final a = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    final b = DateTime.fromMillisecondsSinceEpoch(ref * 1000);
    var diff = (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute);
    if (diff > 720) diff -= 1440;
    if (diff < -720) diff += 1440;
    return diff.toDouble();
  }

  // ── UNUSUAL ───────────────────────────────────────────────────────────────

  /// Only what genuinely stands out, and only against this user's own record.
  ///
  /// An extreme is a FACT — "the shortest night in your last 28" needs no
  /// threshold, no population norm and no model. Everything softer than an
  /// extreme is already visible one section up, where it belongs. When nothing
  /// qualifies, that is the answer and it is shown.
  Widget? _unusual(BuildContext c, P p, SleepData d, Map<String, dynamic> n) {
    final items = <Widget>[];

    void extreme(
      double? v,
      List<double> hist,
      String noun,
      String lowLabel,
      String highLabel,
      String Function(double) fmt,
    ) {
      if (v == null || hist.length < _recordNights) return;
      final lo = hist.reduce(math.min), hi = hist.reduce(math.max);
      // Strictly beyond, not equal to. Stage minutes are whole minutes so ties
      // are ordinary, and a tie printed "less than any of your last 20 nights,
      // the lowest of which was 41m" — the claim and its evidence disagreeing
      // in one sentence.
      if (v < lo) {
        items.add(InsightCard(
            lowLabel,
            '$noun ${fmt(v)} — less than any of your last ${hist.length} '
                'nights, the lowest of which was ${fmt(lo)}.',
            icon: LucideIcons.trendingDown,
            color: C.orange));
      } else if (v > hi) {
        items.add(InsightCard(
            highLabel,
            '$noun ${fmt(v)} — more than any of your last ${hist.length} '
                'nights, the highest of which was ${fmt(hi)}.',
            icon: LucideIcons.trendingUp,
            color: C.green));
      }
    }

    extreme((n['duration_min'] as num?)?.toDouble(), d.tstHistory, 'You slept',
        'Your shortest night lately', 'Your longest night lately', hm);
    extreme((n['deep_min'] as num?)?.toDouble(), d.deepHistory, 'Deep sleep came to',
        'Least deep sleep lately', 'Most deep sleep lately', hm);

    // Detection against the user's own resting baseline, never a diagnosis: a
    // sleeping heart rate this far above baseline is the signal the illness
    // watch is built on, and it is worth saying on the night it happens.
    final noc = n['nocturnal'];
    final vsBase = noc is Map ? noc['vs_baseline_bpm'] as num? : null;
    if (noc is Map && noc['elevated'] == true && vsBase != null) {
      items.add(InsightCard(
        'Sleeping heart rate ran high',
        '${vsBase.toStringAsFixed(1)} bpm above your own baseline. Common '
            'after alcohol, a late meal, a hard session or an infection '
            'starting — this is a measurement, not a diagnosis.',
        icon: LucideIcons.heartPulse,
        color: C.red,
      ));
    }

    if (items.isEmpty) {
      // Only claim "nothing unusual" once there is enough history to have
      // looked. Before that the section is absent rather than reassuring from
      // no evidence — and the section above has already said why.
      if (d.tstHistory.length < _recordNights) return null;
      return Surface(
        color: p.card2,
        elevation: 0,
        child: Row(children: [
          Icon(LucideIcons.check, size: 16, color: p.on(C.green)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text('Nothing stood out.',
                style: F.cap.copyWith(color: p.ink2, height: 1.5)),
          ),
        ]),
      );
    }

    return Column(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: S.x3),
        items[i],
      ],
    ]);
  }

  // ── OVERNIGHT SIGNALS ─────────────────────────────────────────────────────

  Widget _overnight(BuildContext c, P p, SleepData d) {
    /// One lane as `(timestamp, value)`. The timestamp is the point — the
    /// signals arrive on different cadences.
    List<(int, double)> stamped(String key) {
      final l = d.timeline[key];
      if (l is! List) return const [];
      return [
        for (final e in l)
          if (e is Map && e['v'] is num && e['t'] is num)
            ((e['t'] as num).round(), (e['v'] as num).toDouble()),
      ];
    }

    final n = d.night;
    final hr = stamped('hr'),
        hrv = stamped('hrv'),
        resp = stamped('resp'),
        temp = stamped('skin_temp');
    final all = [...hr, ...hrv, ...resp, ...temp];

    // The night's own nocturnal summary — measured, and until now shown
    // nowhere on the screen that owns it.
    final noc = d.night['nocturnal'];
    final respV = (d.night['resp'] is Map)
        ? (d.night['resp'] as Map)['value'] as num?
        : null;
    // Three, not four: `InlineMetrics` divides the card evenly, and a fourth
    // column truncates "14.2 br/min" to "14.2 br/…" at 390 pt. The nocturnal
    // dip was the fourth and is the one number here that is a ratio of two
    // others rather than a reading of its own.
    final summary = <(String, String, Color)>[
      if (noc is Map && noc['sleeping_hr_avg'] != null)
        ('SLEEPING HR', '${noc['sleeping_hr_avg']} bpm', C.red),
      if (noc is Map && noc['sleeping_hr_min'] != null)
        ('LOWEST', '${noc['sleeping_hr_min']} bpm', C.blue),
      if (respV != null)
        ('BREATHING', '${respV.toStringAsFixed(1)} br/min', C.teal),
    ];

    if (all.isEmpty) {
      return summary.isEmpty
          ? _noOvernightLines
          : Surface(child: InlineMetrics(summary));
    }

    // ONE grid for all lanes. `NightStack` reads index as instant, so lanes of
    // different lengths spread across the same width put different times under
    // one vertical slice — which is the entire premise of a stacked night view.
    // The window is the night the axis labels name, and the column count is the
    // densest lane, capped: past ~a column per pixel the extra buckets only add
    // holes.
    var t0 = (n['onset_ts'] as num?)?.round() ??
        all.map((e) => e.$1).reduce((a, b) => a < b ? a : b);
    var t1 = (n['wake_ts'] as num?)?.round() ??
        all.map((e) => e.$1).reduce((a, b) => a > b ? a : b);
    if (t1 <= t0) {
      t0 = all.map((e) => e.$1).reduce((a, b) => a < b ? a : b);
      t1 = all.map((e) => e.$1).reduce((a, b) => a > b ? a : b);
    }
    // The bucket width is set by the SPARSEST lane, not the densest.
    //
    // Heart rate is stored per minute and breathing and skin temperature per
    // five, so a grid sized to heart rate leaves four empty buckets between
    // every breathing sample — and an empty bucket is a HOLE, which the painter
    // correctly draws as a break. The breathing lane was therefore drawn as a
    // dotted line on every night the app has ever rendered, describing a sensor
    // dropout that never happened. Sizing the grid to the slowest lane makes
    // every lane continuous and costs the fast lane nothing a 330 pt chart
    // could have shown anyway. Lanes with almost nothing in them are excluded
    // from the vote (they really are sparse) and the floor keeps a stray short
    // lane from coarsening the whole night.
    //
    // The vote counts points INSIDE the window, not stored points. These lanes
    // are ALL-DAY curves — `hr_curve` at one a minute, `resp_day`/
    // `skin_temp_day` at one per five — so voting on their total length picked
    // ~385 columns from the 24 h heart-rate lane and left the 5-min lanes with
    // a hole in three buckets out of four, on every normal night.
    int inWindow(List<(int, double)> l) {
      var n = 0;
      for (final (t, _) in l) {
        if (t >= t0 && t <= t1) n++;
      }
      return n;
    }

    final lens = [
      for (final l in [hr, hrv, resp, temp])
        if (inWindow(l) >= 8) inWindow(l),
    ];
    // The floor is the admission threshold, not 60: a lane admitted with 48
    // in-window samples was still stretched over 60 buckets and drawn broken.
    final cols = t1 <= t0
        ? 0
        : lens.isEmpty
            ? 2
            : lens.reduce(math.min).clamp(8, 480);

    /// Bucket mean per column; null where the lane has nothing in that
    /// bucket. A null is a HOLE — the painter breaks the line rather than
    /// drawing across a gap the data never covered.
    List<double?> grid(List<(int, double)> v) {
      final sum = List<double>.filled(cols, 0), cnt = List<int>.filled(cols, 0);
      for (final (t, x) in v) {
        if (t < t0 || t > t1) continue;
        final i = (((t - t0) / (t1 - t0)) * (cols - 1)).round().clamp(0, cols - 1);
        sum[i] += x;
        cnt[i]++;
      }
      return [
        for (var i = 0; i < cols; i++)
          cnt[i] == 0 ? null : sum[i] / cnt[i],
      ];
    }

    final series = <List<double?>>[], colors = <Color>[];
    final legend = <(String, Color)>[];
    final axes = <AxisSpec?>[];
    final units = <String>[];

    // Each lane keeps its own scale — they are different quantities — but the
    // scale is PINNED to the night's own range and its unit is named. Three
    // unlabelled lines on three invisible axes was the least readable chart
    // in the app.
    void lane(List<(int, double)> raw, String label, String unit, Color col,
        {String Function(double) format = axisInt}) {
      if (raw.isEmpty || cols == 0) return;
      final g = grid(raw);
      final present = <double>[for (final v in g) ?v];
      if (present.length < 2) return;
      series.add(g);
      colors.add(col);
      legend.add(('$label ($unit)', col));
      axes.add(AxisSpec.of(present, ticks: 2, format: format));
      units.add(unit);
    }

    // Solved against the card, like every other mark: raw pigment measures
    // 1.7-2.5:1 on white and a lane's colour is what tells you which signal
    // you are looking at.
    lane(hr, 'Heart rate', 'bpm', p.on(C.red));
    lane(hrv, 'HRV', 'ms', p.on(C.green));
    lane(resp, 'Breathing', 'br/min', p.on(C.teal));
    // Skin temperature is ADC-relative — a deviation, never a °C. The unit
    // says so rather than implying a thermometer.
    lane(temp, 'Skin temp', 'rel', p.on(C.orange), format: axisFixed);

    if (series.isEmpty) {
      return summary.isEmpty
          ? _noOvernightLines
          : Surface(child: InlineMetrics(summary));
    }
    return Surface(
      child: Column(children: [
        if (summary.isNotEmpty) ...[
          InlineMetrics(summary),
          const SizedBox(height: S.x5),
        ],
        ChartFrame(
          title: 'Through the night',
          unit: units.join(' · '),
          height: 44.0 * series.length + 20,
          xLabels: [
            clockOfTs(n['onset_ts'] as num?),
            clockOfTs(n['wake_ts'] as num?),
          ],
          legend: legend,
          // No footnote. The legend already names each lane and its unit, and
          // the lanes are visibly separate — a paragraph explaining that they
          // are separate was describing the picture instead of letting it work.
          child: CustomPaint(
              size: Size.infinite,
              painter: NightStack(series, colors, axes: axes)),
        ),
      ]),
    );
  }

  // ── TONIGHT ───────────────────────────────────────────────────────────────

  /// One takeaway. The old block listed need, debt, strain bonus, nap credit,
  /// target bed and target wake — six numbers, no instruction. A target bedtime
  /// is the only one of them anybody can act on before midnight.
  Widget _tonight(BuildContext c, P p, SleepData d) {
    final need = d.need.value;
    final bed = d.bedtime.value;
    final debt = d.debt.value;

    if (need == null && bed == null) {
      return StatusCard.forMetric('Sleep need not established', d.need) ??
          const SizedBox.shrink();
    }

    final reason = [
      if (need != null) 'Your need is ${hm(need)}',
      if (debt != null && debt >= 1) 'you are ${hm(debt)} down',
    ].join(', ');

    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(bed != null ? clock(bed) : hm(need),
                    style: F.n34.copyWith(color: p.ink)),
              ),
              const SizedBox(width: S.x2),
              Flexible(
                child: Text(bed != null ? 'lights out' : 'to aim for',
                    style: F.cap.copyWith(color: p.ink3)),
              ),
            ]),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          Text('$reason.', style: F.body.copyWith(color: p.ink2, height: 1.5)),
        ],
      ]),
    );
  }
}

// ── the comparison row ──────────────────────────────────────────────────────

/// One measure of last night against the middle half of the user's own nights.
///
/// Deliberately not a chart: a full plot per measure is four charts in a
/// section nobody would read, and the only two facts here are "where is the
/// band" and "where did last night land". A strip carries both, and the
/// sentence under it carries the same thing in words for anyone who cannot see
/// the strip.
class _Compare extends StatelessWidget {
  final String label, value, low, high;
  final double tonight;
  final List<double> history;
  final Color color;

  /// [fmt] renders a value on this row's axis (minutes → `7h 23m`, relative
  /// minutes → a clock time). [dfmt] renders the SIZE of a difference on it.
  final String Function(double) fmt, dfmt;

  const _Compare({
    required this.label,
    required this.value,
    required this.tonight,
    required this.history,
    required this.color,
    required this.low,
    required this.high,
    required this.fmt,
    required this.dfmt,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final band = _band(history);

    final head = Row(children: [
      Expanded(child: Text(label, style: F.body.copyWith(color: p.ink))),
      const SizedBox(width: S.x2),
      Flexible(
        child: Text(value,
            textAlign: TextAlign.right,
            style: F.n17.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
      ),
    ]);

    if (band == null) {
      // The value is real, the comparison is not available yet. Say which is
      // which rather than dropping the row or drawing an empty band.
      return Column(children: [
        head,
        const SizedBox(height: S.x1),
        Text(
            'No personal range yet — ${history.length} of $_minNights nights.',
            style: F.over.copyWith(color: p.ink3)),
      ]);
    }

    final verdict = tonight < band.lo
        ? '${dfmt((band.mid - tonight).abs())} $low'
        : tonight > band.hi
            ? '${dfmt((tonight - band.mid).abs())} $high'
            : 'Typical for you';

    final lo = math.min(tonight, history.reduce(math.min));
    final hi = math.max(tonight, history.reduce(math.max));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      head,
      const SizedBox(height: S.x3),
      _Strip(
          lo: lo,
          hi: hi,
          bandLo: band.lo,
          bandHi: band.hi,
          mark: tonight,
          color: color),
      const SizedBox(height: S.x2),
      Text('$verdict · usual ${fmt(band.lo)}–${fmt(band.hi)} over ${band.n} '
          'nights',
          style: F.over.copyWith(color: p.ink3, height: 1.5)),
    ]);
  }
}

/// The strip: a neutral track across the observed range, the middle half of the
/// user's nights filled in, and last night as a mark that overhangs both so it
/// is legible whether it lands on the band or off it.
class _Strip extends StatelessWidget {
  final double lo, hi, bandLo, bandHi, mark;
  final Color color;

  const _Strip({
    required this.lo,
    required this.hi,
    required this.bandLo,
    required this.bandHi,
    required this.mark,
    required this.color,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final span = hi - lo;
    double f(double v) => span <= 0 ? .5 : ((v - lo) / span).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (c, box) {
          final w = box.maxWidth;
          final left = f(bandLo) * w;
          // A degenerate band (every night identical) still has to be visible,
          // so it keeps a minimum width rather than collapsing to nothing.
          final width = math.max(4.0, (f(bandHi) - f(bandLo)) * w);
          return SizedBox(
            height: 18,
            width: w,
            child: Stack(children: [
              Positioned(
                left: 0,
                top: 5,
                width: w,
                height: 8,
                child: DecoratedBox(
                    decoration:
                        BoxDecoration(color: p.track, borderRadius: R.rPill)),
              ),
              Positioned(
                left: math.min(left, w - width),
                top: 5,
                width: width,
                height: 8,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: p.on(color), borderRadius: R.rPill)),
              ),
              Positioned(
                left: (f(mark) * w - 1.5).clamp(0.0, w - 3),
                top: 0,
                width: 3,
                height: 18,
                child: DecoratedBox(
                    decoration:
                        BoxDecoration(color: p.ink, borderRadius: R.rPill)),
              ),
            ]),
          );
        },
      ),
    );
  }
}
