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

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../models/metric.dart';
import '../ui2.dart';
import 'sleep_breathing.dart';
import 'home_screen.dart';
import 'metric_detail.dart';
import 'naps.dart' show NapsScreen, napCalculationStatus;
import 'rough_night.dart';

/// Nights of history before a personal normal is claimed at all. Below this the
/// quartiles of three or four nights are noise wearing a band's clothing.
const _minNights = 7;

/// Nights before "your shortest night in N" is worth saying. A record inside a
/// week is a coincidence.
const _recordNights = 14;

/// How far back the comparison window reaches. Long enough to be stable, short
/// enough to still be "you lately" rather than "you last season".
const _window = 28;

/// A per-second label from the segmenter, or NULL for a second nobody watched.
///
/// `unobserved` is not a stage. The catch-all used to be `SleepStage.light`, so
/// every second the band never recorded was drawn — and read — as light sleep:
/// a three-hour hole came out as three hours of sleep. Null draws as a gap, and
/// an unrecognised label from an older bundle now goes the same way, which is
/// the honest direction to fail in.
SleepStage? _stageOf(Object? raw) => switch (raw?.toString()) {
  'wake' || 'awake' => SleepStage.awake,
  'rem' => SleepStage.rem,
  'deep' => SleepStage.deep,
  'light' || 'nrem' => SleepStage.light,
  _ => null,
};

/// 15-minute bands. The stager sees a wrist, so "you fell asleep in 7 minutes"
/// is a precision nobody measured.
String _solBand(BuildContext c, double m) {
  final l = AppLocalizations.of(c);
  if (m < 15) return l?.sleepDetailSolUnder15 ?? 'under 15 minutes';
  if (m >= 60) return l?.sleepDetailSolOverHour ?? 'over an hour';
  final lo = (m ~/ 15) * 15;
  return l?.sleepDetailSolRange(lo, lo + 15) ?? '$lo–${lo + 15} minutes';
}

/// Two call sites drew this byte-identical card; one function so they cannot
/// drift apart.
Widget _noOvernightLines(BuildContext c) {
  final l = AppLocalizations.of(c);
  return StatusCard(
    l?.sleepDetailNoOvernightTitle ?? 'No overnight signal lines',
    l?.sleepDetailNoOvernightBody ??
        'No overnight recordings reached this day.',
    icon: LucideIcons.activity,
  );
}

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

/// A stage's counted minutes and its share of total sleep, e.g. "1h 12m · 16%".
/// These are the same minutes the hypnogram draws, so Deep + REM + Light add
/// up to the total at the top of the screen.
String _stageText(num min, num? totalMin) {
  final share = (totalMin == null || totalMin <= 0)
      ? ''
      : ' · ${(min / totalMin * 100).round()}%';
  return '${hm(min)}$share';
}

class SleepData {
  final String? day;

  /// Every day this install has derived, newest first — what [DayNav] steers
  /// over. Empty in a fixture, which is why a golden shows no stepper.
  final List<String> days;

  final Map<String, dynamic> night;
  final Map<String, dynamic> timeline;
  final Metric need, debt, bedtime;

  /// The user's own recent nights, LAST NIGHT EXCLUDED, oldest→newest. Minutes
  /// for duration and deep, whole percent for efficiency, epoch seconds for
  /// onset. Empty until enough nights exist, which the screen renders as a
  /// [StatusCard] rather than as a comparison against nothing.
  final List<double> tstHistory, deepHistory, effHistory;
  final List<int> onsetHistory;

  /// The shape of last night, as the pipeline published it to `metric_series`.
  /// Not recomputed here: `_sleepRuns` in `onehz_pipeline.dart` owns where a run
  /// ends, and a second definition on this screen is how the hypnogram and the
  /// sentence under it start disagreeing.
  ///
  ///   * [unobservedMin] — minutes of the in-bed window nobody watched.
  ///   * [awakenings] — sustained wake runs, a FLOOR, never a total.
  ///   * [longestSleepMin] — the longest unbroken stretch; never bridges a hole.
  ///   * [solMin] — sleep-onset latency, and ONLY on a user-set window.
  final double? unobservedMin, awakenings, longestSleepMin, solMin;

  /// Minutes the Sleep Coach added to tonight's need for training load.
  /// Null when it added nothing measurable or has not learned a need yet.
  final double? strainBonusMin;

  /// The night's skin temperature as a distance from the user's usual
  /// (`skin_temp` series, a z-score), and the night's HRV (`hrv` series, ms).
  final double? skinTempZ, hrvNight;

  /// The day's naps (`getDayNaps`), each {start, end, duration_min, source}.
  final List<Map<String, dynamic>> naps;

  const SleepData({
    this.day,
    this.days = const [],
    this.night = const {},
    this.timeline = const {},
    this.need = Metric.empty,
    this.debt = Metric.empty,
    this.bedtime = Metric.empty,
    this.tstHistory = const [],
    this.deepHistory = const [],
    this.effHistory = const [],
    this.onsetHistory = const [],
    this.unobservedMin,
    this.awakenings,
    this.longestSleepMin,
    this.solMin,
    this.strainBonusMin,
    this.skinTempZ,
    this.hrvNight,
    this.naps = const [],
  });

  bool get hasNight => night['duration_min'] is num;

  /// Stage samples for the painter — the segment list resampled onto a fixed
  /// number of columns so a four-hour segment and a four-minute one stay in
  /// proportion.
  List<SleepStage?> get stages {
    final pts = night['hypnogram'];
    if (pts is! List || pts.length < 2) return const [];
    final ts = <int>[], st = <SleepStage?>[];
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

  /// One stored scalar for ONE day. `metric_series` stamps a day at local noon,
  /// which is exactly what [_noonOf] builds, so this is an equality match rather
  /// than a nearest-point search.
  static double? _on(Object? chart, int? noon) {
    if (noon == null) return null;
    for (final p in pointsOf(chart)) {
      if (p.t == noon) return p.v;
    }
    return null;
  }

  static Future<SleepData> load(LocalRepository repo, {String? want}) async {
    final today = await repo.getToday();
    // THE NIGHT `getToday` ACTUALLY SERVED. Home's Sleep card is that night, so
    // tapping it has to open that night. Resolving on `today_day` alone opened
    // a day that has a day_result but no night — wear the band all day with it
    // off overnight and the card said "7h 04m" while this screen answered "No
    // night to show" about the same tap.
    final days = await repo.availableDays();
    final day = pickDay(
      days,
      want,
      heldOverNightOf(today) ??
          (today['status'] as Map?)?['today_day']?.toString(),
    );
    if (day == null) return SleepData(days: days);

    final night = await repo.getDaySleepV2(day);
    var timeline = await repo.getDayTimeline(day);
    // The night's signals over its own onset-to-wake window, across midnight,
    // in place of the calendar-day lines (B86-03). A signal the night window
    // has nothing for keeps the day line, which shows an honest gap.
    final on = (night['onset_ts'] as num?)?.toInt();
    final off = (night['wake_ts'] as num?)?.toInt();
    if (on != null && off != null && off > on) {
      try {
        final sig = await repo.getNightSignals(on, off);
        if (sig.isNotEmpty) timeline = {...timeline, ...sig};
      } catch (_) {
        /* the day timeline still draws */
      }
    }
    final cd = await repo.getInsights();
    final coach = cd['sleep_coach'];
    final needEnv = coach is Map ? coach['need'] : null;
    final needSec = envValue(needEnv)?['need_sec'] as num?;
    final debtEnv = cd['sleep_debt'];
    final debtH = envValue(debtEnv)?['debt_hours'] as num?;
    final bedEnv = coach is Map ? coach['bedtime'] : null;
    final strainRaw = coach is Map ? coach['strain_bonus_min'] : null;
    final strainBonus = strainRaw is num && strainRaw.isFinite
        ? strainRaw.toDouble()
        : null;

    // Personal history for the comparisons. These are `metric_series` reads —
    // one small row per day per key — not day bundles, so the whole comparison
    // costs three scalar queries and one window query rather than 28 payload
    // decodes.
    final cut = _noonOf(day);
    final tst = _trailing(await repo.getChart('sleep'), cut);
    final deep = _trailing(await repo.getChart('deep'), cut);
    // Stored as whole percent; the night's own `efficiency` is 0…1.
    final eff = _trailing(await repo.getChart('efficiency'), cut);
    // The shape of THIS night. Four scalar series, read for one day each — the
    // day bundle's `accounting` carries the same figures but `_daySleep` does
    // not re-export them, and metric_series is one row per day per key.
    final unobserved = _on(await repo.getChart('unobserved_min'), cut);
    final wakeups = _on(await repo.getChart('awakenings'), cut);
    final longest = _on(await repo.getChart('longest_sleep_min'), cut);
    final sol = _on(await repo.getChart('sol_min'), cut);
    final tempZ = _on(await repo.getChart('skin_temp'), cut);
    final hrvN = _on(await repo.getChart('hrv'), cut);
    var naps = const <Map<String, dynamic>>[];
    try {
      final nd = await repo.getDayNaps(day);
      naps = [
        for (final x in (nd['naps'] as List?) ?? const [])
          if (x is Map) x.cast<String, dynamic>(),
      ];
    } catch (_) {
      naps = const [];
    }
    final wins = await repo.sleepWindows(days: _window + 1);
    final onsets = <int>[
      for (final w in wins.reversed)
        if (w['date'] != day && w['onset_ts'] is num)
          (w['onset_ts'] as num).round(),
    ];

    return SleepData(
      day: day,
      days: days,
      night: night,
      timeline: timeline,
      need: envMetric(
        needEnv,
        needSec == null ? null : needSec / 60,
        unit: 'min',
      ),
      debt: envMetric(debtEnv, debtH == null ? null : debtH * 60, unit: 'min'),
      bedtime: envMetric(
        bedEnv,
        envValue(bedEnv)?['bedtime_min_of_day'] as num?,
      ),
      tstHistory: tst,
      deepHistory: deep,
      effHistory: eff,
      onsetHistory: onsets,
      unobservedMin: unobserved,
      awakenings: wakeups,
      longestSleepMin: longest,
      solMin: sol,
      strainBonusMin: strainBonus,
      skinTempZ: tempZ,
      hrvNight: hrvN,
      naps: naps,
    );
  }
}

class SleepDetail extends StatefulWidget {
  final SleepData? data;

  /// The night to open. Null means last night — which is what every caller
  /// passed before this existed and what the stepper starts from.
  final String? day;
  final bool embedded;

  const SleepDetail({super.key, this.data, this.day, this.embedded = false});

  @override
  State<SleepDetail> createState() => _SleepDetailState();
}

class _SleepDetailState extends State<SleepDetail> with RevisionReload {
  SleepData? _d;
  bool _loading = true;
  bool _failed = false;
  String? _day;
  bool _saving = false; // an override write + its forced re-derive is in flight
  double? _scrub; // 0..1 across the night

  /// Whether the folded "Fix sleep times" card is open.
  bool _showFix = false;

  /// Why the last correction did not take. Null when it did.
  String? _overrideFailed;

  /// Last night's state against the user's own nights, when it was rough enough
  /// to say so and has not been dismissed. See `rough_night.dart` — it REPLACES
  /// the elevated-sleeping-HR card rather than joining it, so one night can
  /// never read as two observations.
  RoughNight? _rough;

  @override
  void initState() {
    super.initState();
    _day = widget.day;
    if (widget.data != null) {
      _d = widget.data;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // A locale change and `_goDay` can each kick off a `_load()` while a prior
  // one is still in flight; whichever resolves last would otherwise win and
  // could paint the wrong night. Stamp each call and only apply the result
  // still holding the latest stamp.
  int _loadGen = 0;

  @override
  bool get revisionReloads => widget.data == null;
  @override
  void reload() => _load();

  Future<void> _load() async {
    if (!mounted) return;
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted && gen == _loadGen) setState(() => _loading = false);
      return;
    }
    try {
      final d = await SleepData.load(repo, want: _day);
      // LAST NIGHT ONLY. The card names the luteal phase, and `getCycle` knows
      // today's phase and no other day's — so a card offered while stepping
      // back through the record would either drop that half or invent it.
      // Stepping back is also not the moment to ask about a night, which is the
      // stronger half of the reason.
      final rough =
          d.day == todayLabel() &&
              Prefs.getString(kRoughNightDismissed, '') != d.day
          ? await loadRoughNight(repo, d.day!, c: mounted ? context : null)
          : null;
      if (mounted && gen == _loadGen) {
        setState(() => (_d = d, _rough = rough, _loading = false));
      }
    } catch (_) {
      if (mounted && gen == _loadGen) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  /// Another night. The scrub cursor belongs to the night it was placed on, so
  /// it goes with it.
  void _goDay(String day) {
    setState(() {
      _day = day;
      _scrub = null;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext c) {
    final d = _d ?? const SleepData();
    final l = AppLocalizations.of(c);
    final title = l?.sleepDetailNavTitle ?? 'Sleep';

    if (_failed) {
      return detailScaffold(c, title, embedded: widget.embedded, [
        if (!widget.embedded) ...dayNavRow(_day ?? d.day, d.days, _goDay),
        StatusCard(
          'Sleep could not load',
          'Your saved nights are intact.',
          fix: 'Retry',
          onFix: _load,
        ),
      ]);
    }

    if (_loading && _d == null) {
      return detailScaffold(c, title, embedded: widget.embedded, const [
        SizedBox(height: S.x8),
        Center(child: CircularProgressIndicator()),
      ]);
    }

    if (!d.hasNight) {
      // "No night" also covers a night the user REJECTED outright (edge#248):
      // staging was skipped on purpose, so this day has no window at all — but
      // that must stay reversible the same way any other override is.
      final rejectedDay = d.day;
      final rejected =
          (d.night['sleep_source'] as String?) == 'rejected' &&
          rejectedDay != null;
      return detailScaffold(c, title, embedded: widget.embedded, [
        if (!widget.embedded) ...dayNavRow(_day ?? d.day, d.days, _goDay),
        const SizedBox(height: S.x2),
        // A day CAN be in `availableDays` and still hold no night — the band
        // was worn through the day and off overnight. Stepping onto one of
        // those says so and leaves the stepper above it, so it is a day you
        // walk off rather than a dead end.
        StatusCard(
          rejected
              ? (l?.sleepDetailRejectedTitle ?? 'Marked as not sleep')
              : (l?.sleepDetailNoNightTitle ?? 'No night to show'),
          rejected
              ? (l?.sleepDetailRejectedBody ??
                    'You told us this stretch was not sleep, so nothing is '
                        'scored for it.')
              : (l?.sleepDetailNoNightBody ??
                    'No stretch of band recordings long enough to score.'),
          fix: rejected
              ? ''
              : (l?.sleepDetailNoNightFix ??
                    'Wear the band overnight and sync in the morning'),
          icon: rejected ? LucideIcons.undo2 : LucideIcons.moon,
        ),
        if (napCalculationStatus(c) case final status?) status,
        detailLinkRow(
          c,
          LucideIcons.sun,
          'Naps',
          'Log, review or restore a nap',
          () => go(c, NapsScreen(day: d.day ?? _day ?? todayLabel())),
        ),
        if (rejected) ...[
          const SizedBox(height: S.x2),
          TextButton(
            onPressed: _saving ? null : () => _clearWindow(rejectedDay),
            child: Text(
              l?.sleepDetailUndoRejection ?? 'Undo — go back to automatic',
            ),
          ),
        ],
      ]);
    }

    final p = P.of(c);
    final n = d.night;
    final unusual = _unusual(c, p, d, n);

    // The stepper names the night, so the nav bar does not say it twice. With
    // one night on disk there is no stepper, and then the subtitle is the only
    // thing that dates the screen.
    return detailScaffold(
      c,
      title,
      embedded: widget.embedded,
      sub: d.days.length < 2 && d.day != null ? prettyDay(d.day, l) : '',
      [
        if (!widget.embedded) ...dayNavRow(_day ?? d.day, d.days, _goDay),
        if (widget.embedded && d.day != null && d.day != todayLabel())
          Text(prettyDay(d.day, l)),

        // ── 1 · THE ANSWER ──
        _answer(c, p, d, n),

        // ── 2 · THE NIGHT ITSELF ──
        const SizedBox(height: S.x3),
        _night(c, p, d, n),

        // ── 3 · WHAT IT WAS MADE OF ──
        Section(l?.sleepDetailStagesSection ?? 'Stages', _stages(c, p, n)),

        // ── 4 · AGAINST THE USER'S OWN NIGHTS ──
        if (_versusUsual(c, p, d, n) case final versus?)
          Section(
            l?.sleepDetailVersusUsualSection ?? 'Against your usual',
            versus,
          ),

        // ── 5 · WHAT STOOD OUT ──
        // Named after the night the nav bar is already showing. "Unusual last
        // night — Nothing stood out." is a present-tense all-clear, and it was
        // printed over a night that could be days old.
        if (unusual != null)
          Section(
            (daysBehind(_noonOf(d.day)) ?? 0) <= 0
                ? (l?.sleepDetailUnusualLastNight ?? 'Unusual last night')
                : (l?.sleepDetailUnusualOnDay(prettyDay(d.day, l)) ??
                      'Unusual on ${prettyDay(d.day, l)}'),
            unusual,
          ),

        // ── 6 · THE SIGNALS UNDERNEATH ──
        Section(
          l?.sleepDetailOvernightSection ?? 'Overnight signals',
          _overnight(c, p, d),
        ),

        // No "Tonight" section: sleep need, debt and a lights-out time are
        // noise to someone who sleeps on their own schedule. Still computed.
        if (napCalculationStatus(c) case final status?) status,
        // Naps stay reachable even after the last detection is removed.
        Section(
          'Naps',
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(
              children: [
                if (d.naps.isEmpty)
                  MetricRow(
                    LucideIcons.sun,
                    C.sleep,
                    'No naps logged',
                    '',
                    sub: 'Log a nap or restore a removed detection',
                    onTap: () => go(c, NapsScreen(day: d.day)),
                  ),
                for (final nap in d.naps)
                  MetricRow(
                    LucideIcons.sun,
                    C.sleep,
                    '${clockOfTs(nap['start'] as num?)} – '
                    '${clockOfTs(nap['end'] as num?)}',
                    hm(nap['duration_min'] as num?),
                    sub: nap['source'] == 'manual'
                        ? 'Added by you'
                        : 'Detected',
                    onTap: () => go(c, NapsScreen(day: d.day)),
                  ),
              ],
            ),
          ),
          action: 'Edit',
          onAction: () => go(c, NapsScreen(day: d.day)),
        ),

        // Correcting the sleep window is an occasional fix, not a reading, so it
        // sits last and folded rather than between the chart and the stages.
        if (_windowCard(c, p, d, n) case final fix?) ...[
          const SizedBox(height: S.x5),
          Pressable(
            onTap: () => setState(() => _showFix = !_showFix),
            semanticLabel: 'Fix sleep times',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Fix sleep times',
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                ),
                Icon(
                  _showFix ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 16,
                  color: p.ink3,
                ),
              ],
            ),
          ),
          if (_showFix) ...fix,
        ],

        // Across nights, never one: kept one tap down so it cannot read as a
        // headline about last night (see sleep_breathing.dart).
        const SizedBox(height: S.x5),
        detailLinkRow(
          c,
          LucideIcons.wind,
          'Breathing pattern in sleep',
          'Heart-rate cycling across your recent nights',
          () => go(c, const SleepBreathingScreen()),
        ),
      ],
    );
  }

  /// Total sleep, when it ran, and the two ratios that qualify it. Everything
  /// here is measured; nothing is a judgement.
  Widget _answer(BuildContext c, P p, SleepData d, Map<String, dynamic> n) {
    final l = AppLocalizations.of(c);
    final tst = n['duration_min'] as num?;
    final eff = n['efficiency'] as num?;
    final inBed = n['in_bed_min'] as num?;
    final from = clockOfTs(n['onset_ts'] as num?);
    final to = clockOfTs(n['wake_ts'] as num?);
    // Wall clock minus the minutes nobody watched. `efficiency_pct` has always
    // divided by this, so on a night with a hole the honest denominator just
    // read as a worse night unless the screen says which window it is.
    final unobserved = d.unobservedMin;
    final watched = (inBed == null || unobserved == null || unobserved <= 0)
        ? null
        : math.max(0, inBed - unobserved);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hm(tst), style: F.n48.copyWith(color: p.ink)),
          const SizedBox(height: S.x1),
          Text(
            l?.sleepDetailTotalSleep ?? 'Total sleep',
            style: F.cap.copyWith(color: p.ink3),
          ),
          if (from.isNotEmpty && to.isNotEmpty) ...[
            const SizedBox(height: S.x4),
            Row(
              children: [
                Icon(LucideIcons.moon, size: 15, color: p.ink3),
                const SizedBox(width: S.x2),
                Flexible(
                  child: Text(
                    '$from → $to',
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (inBed != null || eff != null) ...[
            const SizedBox(height: S.x4),
            InlineMetrics([
              if (inBed != null)
                (l?.sleepDetailInBed ?? 'IN BED', hm(inBed), C.indigo),
              if (watched != null)
                (l?.sleepDetailWatched ?? 'WATCHED', hm(watched), C.sky),
              if (eff != null)
                (
                  watched == null
                      ? (l?.sleepDetailAsleepOfThat ?? 'ASLEEP OF THAT')
                      : (l?.sleepDetailAsleep ?? 'ASLEEP'),
                  _pct(eff * 100),
                  C.green,
                ),
            ]),
          ],
          if (watched != null) ...[
            const SizedBox(height: S.x3),
            Text(
              l?.sleepDetailWatchedExplain(hm(watched), hm(inBed!)) ??
                  'We watched ${hm(watched)} of your ${hm(inBed!)} in bed; the rest '
                      'is not a measurement. Asleep, and the stage shares below, are out '
                      'of the time we watched.',
              style: F.over.copyWith(color: p.ink3, height: 1.5),
            ),
          ],
        ],
      ),
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
  /// Main-sleep corrections restage the night. Nap corrections have their own
  /// immediate durable projection and background coaching update in Naps.
  List<Widget>? _windowCard(
    BuildContext c,
    P p,
    SleepData d,
    Map<String, dynamic> n,
  ) {
    final l = AppLocalizations.of(c);
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  mine ? LucideIcons.userCheck : LucideIcons.wandSparkles,
                  size: 16,
                  color: p.ink3,
                ),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(
                    mine
                        ? (l?.sleepDetailWindowMine ?? 'You set this window')
                        : fallback
                        ? (l?.sleepDetailWindowFallback ??
                              'This window was inferred from heart rate')
                        : (l?.sleepDetailWindowAuto ??
                              'This window was staged from the signals'),
                    style: F.body.copyWith(color: p.ink),
                  ),
                ),
              ],
            ),
            if (fallback) ...[
              const SizedBox(height: S.x2),
              Text(
                l?.sleepDetailWindowFallbackBody ??
                    'Staging could not find the edges, so the times are a best '
                        'guess.',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
            // SLP-02 — settling time, and ONLY here. On the auto path the window
            // is built from stillness gated on a sleep-ish heart rate, so it
            // cannot begin before you are already lying quiet: the 40 minutes of
            // tossing falls outside it and the latency would come out near zero.
            // On a window the user asserted, the number means what people think
            // it means. The pipeline abstains for both reasons; this only draws
            // what it published.
            if (mine && d.solMin != null) ...[
              const SizedBox(height: S.x2),
              Text(
                l?.sleepDetailWindowSol(_solBand(c, d.solMin!)) ??
                    'From the start of your window to asleep: '
                        '${_solBand(c, d.solMin!)}.',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
            const SizedBox(height: S.x2),
            Wrap(
              spacing: S.x2,
              children: [
                if (fallback)
                  TextButton(
                    onPressed: busy ? null : () => _confirmWindow(day),
                    child: Text(
                      l?.sleepDetailConfirmTimes ?? 'These times are right',
                    ),
                  ),
                TextButton(
                  onPressed: busy ? null : () => _editWindow(day, t0, t1),
                  child: Text(
                    mine
                        ? (l?.sleepDetailChangeTimes ?? 'Change the times')
                        : (l?.sleepDetailSetTimesMyself ??
                              'Set the times myself'),
                  ),
                ),
                if (mine)
                  TextButton(
                    onPressed: busy ? null : () => _clearWindow(day),
                    child: Text(
                      l?.sleepDetailBackToAutomatic ?? 'Back to automatic',
                    ),
                  ),
                // The missing third answer next to "Looks right"/"Edit": naps
                // already have a reject action (sleep_nap source='rejected');
                // a whole-night main-sleep session didn't (edge#248).
                TextButton(
                  onPressed: busy ? null : () => _rejectWindow(day),
                  child: Text(l?.sleepDetailNotSleep ?? 'Not sleep'),
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: S.x2),
              Text(
                l?.sleepDetailReanalysing ?? 'Re-analysing the night…',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
            if (!busy && _overrideFailed != null) ...[
              const SizedBox(height: S.x3),
              StatusCard(
                l?.sleepDetailCorrectionFailedTitle ??
                    'That correction has not been applied',
                _overrideFailed!,
                icon: LucideIcons.triangleAlert,
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Future<void> _confirmWindow(String day) =>
      _runOverride(() => context.read<AppState>().confirmSleep(day));

  Future<void> _clearWindow(String day) =>
      _runOverride(() => context.read<AppState>().clearSleepOverride(day));

  Future<void> _rejectWindow(String day) =>
      _runOverride(() => context.read<AppState>().rejectSleep(day));

  /// Two pickers, seeded from the window we already have — the user is
  /// correcting times, not entering a date, so the DATES stay as measured and
  /// only the clock moves. A wake that lands before the onset belongs to the
  /// next morning.
  Future<void> _editWindow(String day, int t0, int t1) async {
    final onset = DateTime.fromMillisecondsSinceEpoch(t0 * 1000);
    final wake = DateTime.fromMillisecondsSinceEpoch(t1 * 1000);
    final l = AppLocalizations.of(context);
    final bed = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(onset),
      helpText: l?.sleepDetailBedTimeHelp ?? 'WHEN YOU GOT INTO BED',
    );
    if (bed == null || !mounted) return;
    final up = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(wake),
      helpText: l?.sleepDetailWakeTimeHelp ?? 'WHEN YOU GOT UP',
    );
    if (up == null || !mounted) return;
    final newOnset = DateTime(
      onset.year,
      onset.month,
      onset.day,
      bed.hour,
      bed.minute,
    );
    // A wake at or before the onset is the next morning. `day + 1` rather than
    // adding a Duration: DateTime normalises the overflow, and it is calendar
    // arithmetic across a possible DST boundary, not a span of elapsed time.
    var newWake = DateTime(
      onset.year,
      onset.month,
      onset.day,
      up.hour,
      up.minute,
    );
    if (!newWake.isAfter(newOnset)) {
      newWake = DateTime(
        onset.year,
        onset.month,
        onset.day + 1,
        up.hour,
        up.minute,
      );
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
      final l = AppLocalizations.of(context);
      setState(
        () => _overrideFailed =
            failed ??
            l?.sleepDetailReanalyseFailed ??
            'The night was not re-analysed — another re-analysis was already '
                'running, or it failed. The times you set are saved; '
                'Re-analyze everything on Your data applies them.',
      );
    }
  }

  /// Where the drawn window came from: 'auto', 'auto_fallback', 'manual' or
  /// 'confirmed'.
  String? get _source => (_d?.night['sleep_source'] as String?) ?? 'auto';

  /// The hypnogram, as the centrepiece rather than as an illustration. The
  /// cycle count rides underneath it because it is a property of this shape,
  /// not a section of its own.
  Widget _night(BuildContext c, P p, SleepData d, Map<String, dynamic> n) {
    final l = AppLocalizations.of(c);
    final stages = d.stages;
    if (stages.isEmpty) {
      return StatusCard(
        l?.sleepDetailNoHypnogramTitle ?? 'No hypnogram for this night',
        l?.sleepDetailNoHypnogramBody ??
            'Staging needs movement and beat timing. One was missing.',
        icon: LucideIcons.chartNoAxesColumn,
      );
    }
    final t0 = (n['onset_ts'] as num?)?.round();
    final t1 = (n['wake_ts'] as num?)?.round();
    final cycles = (n['cycle_count'] as num?)?.toInt() ?? 0;
    final mean = n['cycles_mean_min'] as num?;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChartFrame(
            title: l?.sleepDetailThroughTheNight ?? 'Through the night',
            unit: '',
            height: 132,
            // Five evenly spaced clock marks: the labels sit at quarters of the
            // plot, so each one is the time at that point of the night.
            xLabels: [
              clockOfTs(t0),
              if (t0 != null && t1 != null && t1 > t0)
                for (var q = 1; q < 4; q++) clockOfTs(t0 + (t1 - t0) * q ~/ 4),
              clockOfTs(t1),
            ],
            readout: _scrub == null ? null : _scrubLine(c, d, _scrub!),
            // Driven by the night, not by the enum: a night with no REM in
            // it used to still print REM in its key.
            legend: [
              for (final e in Hypnogram.legend(p))
                if (stages.any((s) => s?.label == e.$1)) e,
            ],
            child: _hypnogram(c, p, stages, n),
          ),
          const SizedBox(height: S.x2),
          Text(
            cycles > 0
                ? (mean == null
                      ? (l?.sleepDetailTapDragCycles(cycles) ??
                            'Tap or drag the chart for any moment. $cycles '
                                '${cycles == 1 ? 'cycle' : 'cycles'}.')
                      : (l?.sleepDetailTapDragCyclesAvg(cycles, hm(mean)) ??
                            'Tap or drag the chart for any moment. $cycles '
                                '${cycles == 1 ? 'cycle' : 'cycles'}, ${hm(mean)} '
                                'on average.'))
                : (l?.sleepDetailTapDragNone ??
                      'Tap or drag the chart for any moment of the night.'),
            style: F.over.copyWith(color: p.ink3, height: 1.5),
          ),
          if (_shape(c, d) case final shape?) ...[
            const SizedBox(height: S.x2),
            Text(
              [
                if (d.awakenings != null)
                  '${d.awakenings!.round()}+ wake-ups ≥5 min',
                if (d.longestSleepMin != null)
                  'Longest ${hm(d.longestSleepMin)}',
              ].join(' · '),
              style: F.over.copyWith(color: p.ink2),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                'Night details',
                style: F.over.copyWith(color: p.ink3),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: S.x2),
                  child: Text(
                    shape,
                    style: F.over.copyWith(color: p.ink3, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The shape of the night in one line — how broken it was, and the longest
  /// piece of it. Null when the pipeline published neither.
  ///
  /// The count is a FLOOR and says so: our stager sees sustained wake, and the
  /// 3-15 s cortical arousals a PSG counts are invisible to a 1 Hz wrist, so the
  /// true number is higher than this one. Five minutes is a choice, not
  /// physiology, so it is stated rather than assumed. No arousal index, no
  /// explanation, only the shape.
  String? _shape(BuildContext c, SleepData d) {
    final l = AppLocalizations.of(c);
    final w = d.awakenings?.round();
    final longest = d.longestSleepMin;
    final parts = [
      if (w != null)
        w == 0
            ? (l?.sleepDetailNoWakeups ??
                  'No wake-ups of 5 minutes or more; shorter ones are invisible to '
                      'a wrist.')
            : (l?.sleepDetailAtLeastWakeups(w) ??
                  'At least $w wake-up${w == 1 ? '' : 's'} of 5 minutes or more; '
                      'shorter ones are invisible to a wrist.'),
      if (longest != null)
        l?.sleepDetailLongestStretch(hm(longest)) ??
            'Longest unbroken stretch ${hm(longest)}.',
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// The night split into stretches we watched and holes we did not:
  /// `(stages, columns)`, where a null stage list is time the band was not
  /// recording and is drawn as NOTHING.
  ///
  /// A gap is the only honest mark for "not a measurement". There is no fifth
  /// lane and there should not be one — a lane is a stage, and this is the
  /// absence of one.
  static List<(List<SleepStage>?, int)> _runs(List<SleepStage?> st) {
    final out = <(List<SleepStage>?, int)>[];
    var i = 0;
    while (i < st.length) {
      var j = i;
      while (j + 1 < st.length && (st[j + 1] == null) == (st[i] == null)) {
        j++;
      }
      out.add(
        st[i] == null
            ? (null, j - i + 1)
            : (st.sublist(i, j + 1).cast<SleepStage>(), j - i + 1),
      );
      i = j + 1;
    }
    return out;
  }

  /// A [Scrubber], not a drag gesture: what matters is where the pointer IS,
  /// and the 44 pt tap rule does not apply to a continuous readout. What DOES
  /// apply is that the readout has to exist without a pointer — [Scrubber]
  /// carries the slider role and speaks [describe] at each step.
  Widget _hypnogram(
    BuildContext c,
    P p,
    List<SleepStage?> stages,
    Map<String, dynamic> n,
  ) => Scrubber(
    value: _scrub,
    onChanged: (v) => setState(() => _scrub = v),
    label: AppLocalizations.of(c)?.sleepDetailHypnogramLabel ?? 'Hypnogram',
    describe: (v) => _scrubSays(c, stages, n, v),
    child: SizedBox(
      height: 132,
      child: Stack(
        children: [
          // One painter per watched stretch, laid out by its width in
          // columns, with nothing at all where the band was not recording.
          // Every painter gets the same height, so the four lanes stay on the
          // same four lines across the whole night.
          Row(
            children: [
              for (final (st, cols) in _runs(stages))
                Expanded(
                  flex: cols,
                  child: st == null
                      ? const SizedBox.expand()
                      : CustomPaint(
                          size: Size.infinite,
                          painter: Hypnogram(st, p, t: animate(c, 1)),
                        ),
                ),
            ],
          ),
          if (_scrub != null)
            // Aligned by fraction rather than by a measured offset, so the
            // cursor needs no width from the layout.
            Align(
              alignment: Alignment(_scrub! * 2 - 1, 0),
              child: SizedBox(
                width: 2,
                height: double.infinity,
                child: ColoredBox(color: p.ink),
              ),
            ),
        ],
      ),
    ),
  );

  /// What the night read at [v] (0…1 of it): the clock time and the stage.
  String _scrubSays(
    BuildContext c,
    List<SleepStage?> stages,
    Map<String, dynamic> n,
    double v,
  ) {
    final l = AppLocalizations.of(c);
    final t0 = (n['onset_ts'] as num?)?.toInt();
    final t1 = (n['wake_ts'] as num?)?.toInt();
    final st = stages.isEmpty
        ? null
        : stages[(v * (stages.length - 1)).round().clamp(0, stages.length - 1)];
    final at = (t0 == null || t1 == null || t1 <= t0)
        ? (l?.sleepDetailPercentThroughNight((v * 100).round()) ??
              '${(v * 100).round()}% through the night')
        : clockOfTs(t0 + ((t1 - t0) * v).round());
    final stageName = st == null
        ? (l?.sleepDetailNotMeasured ?? 'not measured')
        : _stageName(c, st);
    return l?.sleepDetailScrubAt(at, stageName) ?? '$at, $stageName';
  }

  /// What every signal read at the scrubbed instant. Each line abstains on its
  /// own — a night with no respiration series still shows heart rate.
  /// The chart header while a finger is on the night: time · stage · heart
  /// rate · HRV · skin temperature against the night's own average. Each
  /// part abstains on its own when nothing was recorded near that moment.
  String _scrubLine(BuildContext c, SleepData d, double v) {
    final n = d.night;
    final t0 = (n['onset_ts'] as num?)?.toInt();
    final t1 = (n['wake_ts'] as num?)?.toInt();
    final head = _scrubSays(c, d.stages, n, v).replaceFirst(', ', ' · ');
    if (t0 == null || t1 == null || t1 <= t0) return head;
    final t = t0 + ((t1 - t0) * v).round();
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

    double? nightMean(String key) {
      final list = d.timeline[key];
      if (list is! List) return null;
      final vs = [
        for (final e in list)
          if (e is Map &&
              e['t'] is num &&
              e['v'] is num &&
              (e['t'] as num) >= t0 &&
              (e['t'] as num) <= t1)
            (e['v'] as num).toDouble(),
      ];
      return vs.isEmpty ? null : vs.reduce((a, b) => a + b) / vs.length;
    }

    final hr = at('hr'), hrv = at('hrv'), temp = at('skin_temp');
    final mean = nightMean('skin_temp');
    final signals = [
      if (hr != null) '${hr.round()} bpm',
      if (hrv != null) 'HRV ${hrv.round()} ms',
      if (temp != null && mean != null)
        'Temp Δ ${temp - mean >= 0 ? '+' : '−'}${(temp - mean).abs().toStringAsFixed(1)} °C',
    ].join(' · ');
    return signals.isEmpty ? head : '$head\n$signals';
  }

  String _stageName(BuildContext c, SleepStage s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      SleepStage.awake => l?.sleepDetailStageAwake ?? 'Awake',
      SleepStage.rem => l?.sleepDetailStageRem ?? 'REM',
      SleepStage.light => l?.sleepDetailStageLight ?? 'Light sleep',
      SleepStage.deep => l?.sleepDetailStageDeep ?? 'Deep sleep',
    };
  }

  /// One stage of the night: a name and what it came to. The value is one
  /// string — the range for a staged figure, a plain duration for Awake — so
  /// the column has ONE right edge down the whole table. It is `Flexible`
  /// rather than fixed because "1h 15m–2h 30m" is twice the width the old
  /// minutes column was sized for; above the big-text threshold the row
  /// restacks rather than squeeze, exactly like [MetricRow].
  Widget _stageRow(BuildContext c, P p, (String, String, Color) s) {
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle),
    );
    final name = Text(s.$1, style: F.body.copyWith(color: p.ink));
    final value = Text(
      s.$2,
      textAlign: TextAlign.right,
      style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600),
    );
    if (!bigText(c)) {
      return Row(
        children: [
          dot,
          const SizedBox(width: S.x3),
          Expanded(child: name),
          const SizedBox(width: S.x3),
          Flexible(child: value),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        dot,
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              name,
              const SizedBox(height: S.x1),
              Text(
                s.$2,
                style: F.cap.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// SLP-13 — the stage block, as ranges.
  ///
  /// The share column is GONE and that is the point. A percentage is computed
  /// from the exact minute count, so printing "19%" beside "45m–1h 15m" would
  /// have restored, on the same row, the precision the range exists to retire.
  /// Nothing is lost that the range does not carry better.
  ///
  /// Awake keeps a single figure. It is not one of the three the overlay splits
  /// — asleep-versus-awake is a different decision with a different weakness,
  /// already stated where the awakening count is, and `stageIntervals` publishes
  /// no interval for it. Inventing one here would be exactly the fabricated
  /// precision this item removes.
  Widget _stages(BuildContext c, P p, Map<String, dynamic> n) {
    final l = AppLocalizations.of(c);
    final total = n['duration_min'] as num?;
    final deep = n['deep_min'] as num?,
        rem = n['rem_min'] as num?,
        light = n['light_min'] as num?;
    final staged = deep != null && rem != null && light != null;
    final awake = n['awake_min'] as num?;
    final rows = <(String, String, Color)>[
      if (staged)
        (l?.sleepDetailDeep ?? 'Deep', _stageText(deep, total), C.sleep),
      if (staged)
        (l?.sleepDetailStageRem ?? 'REM', _stageText(rem, total), C.teal),
      if (staged)
        (l?.sleepDetailLight ?? 'Light', _stageText(light, total), C.sky),
      if (awake != null)
        (l?.sleepDetailStageAwake ?? 'Awake', hm(awake), C.orange),
    ];
    if (rows.isEmpty) {
      return StatusCard(
        l?.sleepDetailNoStageSplitTitle ?? 'No stage split for this night',
        l?.sleepDetailNoStageSplitBody ??
            'No beat timing across the whole window.',
        icon: LucideIcons.chartNoAxesColumn,
      );
    }
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
                  child: _stageRow(c, p, rows[i]),
                ),
              ],
            ],
          ),
        ),
        if (staged) ...[
          const SizedBox(height: S.x2),
          // One plain caveat instead of printing every stage as a wide range:
          // a wrist estimates stages, it does not count them.
          Text(
            'Estimated from heart rate and movement at the wrist.',
            style: F.over.copyWith(color: p.ink3, height: 1.5),
          ),
        ],
      ],
    );
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
    BuildContext c,
    P p,
    SleepData d,
    Map<String, dynamic> n,
  ) {
    final l = AppLocalizations.of(c);
    final rows = <Widget>[];

    final tst = (n['duration_min'] as num?)?.toDouble();
    if (tst != null) {
      rows.add(
        _Compare(
          label: l?.sleepDetailTimeAsleep ?? 'Time asleep',
          value: hm(tst),
          tonight: tst,
          history: d.tstHistory,
          color: C.indigo,
          low: l?.sleepDetailShorterThanUsual ?? 'shorter than usual',
          high: l?.sleepDetailLongerThanUsual ?? 'longer than usual',
          fmt: (v) => hm(v),
          dfmt: (v) => hm(v),
        ),
      );
    }

    final deep = (n['deep_min'] as num?)?.toDouble();
    if (deep != null) {
      rows.add(
        _Compare(
          label: l?.sleepDetailStageDeep ?? 'Deep sleep',
          value: hm(deep),
          tonight: deep,
          history: d.deepHistory,
          color: C.sleep,
          low: l?.sleepDetailLessThanUsual ?? 'less than usual',
          high: l?.sleepDetailMoreThanUsual ?? 'more than usual',
          fmt: (v) => hm(v),
          dfmt: (v) => hm(v),
        ),
      );
    }

    final eff = (n['efficiency'] as num?)?.toDouble();
    if (eff != null) {
      rows.add(
        _Compare(
          label: l?.sleepDetailAsleepWhileInBed ?? 'Asleep while in bed',
          value: _pct(eff * 100),
          tonight: eff * 100,
          history: d.effHistory,
          color: C.green,
          low: l?.sleepDetailLowerThanUsual ?? 'lower than usual',
          high: l?.sleepDetailHigherThanUsual ?? 'higher than usual',
          fmt: _pct,
          dfmt: _pts,
        ),
      );
    }

    // Timing is measured on an axis anchored at last night's onset: every past
    // night becomes signed minutes relative to it, wrapped across midnight, so
    // 11:50 PM and 12:10 AM are twenty minutes apart rather than 23 hours. The
    // band edges are formatted back into clock times, which is the only form
    // anyone reads a bedtime in.
    final onset = (n['onset_ts'] as num?)?.round();
    if (onset != null && d.onsetHistory.isNotEmpty) {
      final rel = [for (final o in d.onsetHistory) _relMinutes(o, onset)];
      rows.add(
        _Compare(
          label: l?.sleepDetailFellAsleep ?? 'Fell asleep',
          value: clockOfTs(onset),
          tonight: 0,
          history: rel,
          color: C.purple,
          low: l?.sleepDetailEarlierThanUsual ?? 'earlier than usual',
          high: l?.sleepDetailLaterThanUsual ?? 'later than usual',
          fmt: (v) => clockOfTs(onset + (v * 60).round()),
          dfmt: (v) => hm(v),
        ),
      );
      // Bedtime consistency (build 81): how far your bedtimes spread across
      // the last fortnight, tonight included. A spread, not a verdict on a
      // single night, so it needs a week of nights before it says anything.
      final recent = [
        0.0,
        ...rel.skip(math.max(0, rel.length - (kBedtimeNights - 1))),
      ];
      final spread = bedtimeSpreadMin(recent);
      if (spread != null) {
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bedtime consistency',
                      style: F.body.copyWith(color: p.ink),
                    ),
                    Text(
                      '${bedtimeWord(spread)} · last ${recent.length} nights',
                      style: F.over.copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
              Text(
                '±${hm(spread)}',
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }
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
        l?.sleepDetailNotEnoughNightsTitle ?? 'Not enough nights to compare',
        '',
        fix:
            l?.sleepDetailNightsSoFar(have, _minNights) ??
            '$have of $_minNights nights so far',
        icon: LucideIcons.chartNoAxesColumn,
      );
    }

    return Column(
      children: [
        Surface(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: S.x5),
                rows[i],
              ],
            ],
          ),
        ),
        const SizedBox(height: S.x2),
        Text(
          l?.sleepDetailBarExplain ??
              'The bar is the middle half of your own nights.',
          style: F.over.copyWith(color: p.ink3, height: 1.5),
        ),
      ],
    );
  }

  /// Signed minutes from [ref] to [t], as times of day, wrapped to ±12 h.
  /// (Used by the timing rows and the bedtime spread above.)
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
    final l = AppLocalizations.of(c);
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
        items.add(
          InsightCard(
            lowLabel,
            l?.sleepDetailLessThanAny(noun, fmt(v), hist.length, fmt(lo)) ??
                '$noun ${fmt(v)} — less than any of your last ${hist.length} '
                    'nights, the lowest of which was ${fmt(lo)}.',
            icon: LucideIcons.trendingDown,
            color: C.orange,
          ),
        );
      } else if (v > hi) {
        items.add(
          InsightCard(
            highLabel,
            l?.sleepDetailMoreThanAny(noun, fmt(v), hist.length, fmt(hi)) ??
                '$noun ${fmt(v)} — more than any of your last ${hist.length} '
                    'nights, the highest of which was ${fmt(hi)}.',
            icon: LucideIcons.trendingUp,
            color: C.green,
          ),
        );
      }
    }

    extreme(
      (n['duration_min'] as num?)?.toDouble(),
      d.tstHistory,
      l?.sleepDetailYouSlept ?? 'You slept',
      l?.sleepDetailShortestNightLately ?? 'Your shortest night lately',
      l?.sleepDetailLongestNightLately ?? 'Your longest night lately',
      hm,
    );
    // SLP-13a — NO deep-sleep extreme. `segment.dart` emits
    // `deep_low_confidence` and calls the Light/Deep split unvalidated; ranking
    // last night's deep minutes against 28 other nights of the same unvalidated
    // split is the most confident wrong claim the screen could make. The row in
    // "Against your usual" stays, because a band is a distribution, not a
    // record claim.

    // Detection against the user's own resting baseline, never a diagnosis: a
    // sleeping heart rate this far above baseline is the signal the illness
    // watch is built on, and it is worth saying on the night it happens.
    // ONE CARD ABOUT THE NIGHT'S AUTONOMIC STATE, EVER.
    //
    // When the rough-night card is up it says everything this one says and
    // more, off a strictly harder gate: `elevated` is a flat baseline + 4 bpm
    // on one channel, the rough card needs two of four channels past their own
    // minimal detectable change on this person's scale. Showing both puts two
    // cards on one observation and the reader cannot tell they are one.
    final rough = _rough;
    if (rough != null) {
      items.add(
        RoughNightCard(
          night: rough,
          // Stats only: the personal build logs nothing by hand, so the card
          // states which measurements moved and never asks what caused it.
          ask: 'never',
          onDismiss: () => setState(() => _rough = null),
        ),
      );
    }

    final noc = n['nocturnal'];
    final vsBase = noc is Map ? noc['vs_baseline_bpm'] as num? : null;
    if (rough == null &&
        noc is Map &&
        noc['elevated'] == true &&
        vsBase != null) {
      items.add(
        InsightCard(
          l?.sleepDetailSleepingHrHighTitle ?? 'Sleeping heart rate ran high',
          l?.sleepDetailSleepingHrHighBody(vsBase.toStringAsFixed(1)) ??
              '${vsBase.toStringAsFixed(1)} bpm above your own baseline. Common '
                  'after alcohol, a late meal, a hard session or an infection '
                  'starting — this is a measurement, not a diagnosis.',
          icon: LucideIcons.heartPulse,
          color: C.red,
        ),
      );
    }

    if (items.isEmpty) {
      // Only claim "nothing unusual" once there is enough history to have
      // looked. Before that the section is absent rather than reassuring from
      // no evidence — and the section above has already said why.
      if (d.tstHistory.length < _recordNights) return null;
      return Surface(
        color: p.card2,
        elevation: 0,
        child: Row(
          children: [
            Icon(LucideIcons.check, size: 16, color: p.on(C.green)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Text(
                l?.sleepDetailNothingStoodOut ?? 'Nothing stood out.',
                style: F.cap.copyWith(color: p.ink2, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: S.x3),
          items[i],
        ],
      ],
    );
  }

  // ── OVERNIGHT SIGNALS ─────────────────────────────────────────────────────

  /// Overnight signals as one clean row each: the number that matters and a
  /// small line through the night. Breathing gets a row only on a night it was
  /// measured; a lane that was mostly empty read as a broken chart.
  Widget _overnight(BuildContext c, P p, SleepData d) {
    final loc = AppLocalizations.of(c);
    final n = d.night;
    final t0 = (n['onset_ts'] as num?)?.round();
    final t1 = (n['wake_ts'] as num?)?.round();

    /// One signal across the night in [cols] buckets (mean per bucket, null
    /// where nothing was recorded), and its night mean.
    (List<double?>, double?) lane(String key, {int cols = 40}) {
      final list = d.timeline[key];
      if (list is! List || t0 == null || t1 == null || t1 <= t0) {
        return (const [], null);
      }
      final sum = List<double>.filled(cols, 0), cnt = List<int>.filled(cols, 0);
      var all = 0.0;
      var k = 0;
      for (final e in list) {
        if (e is! Map || e['t'] is! num || e['v'] is! num) continue;
        final t = (e['t'] as num).round();
        if (t < t0 || t > t1) continue;
        final v = (e['v'] as num).toDouble();
        final i = ((t - t0) / (t1 - t0) * (cols - 1)).round().clamp(
          0,
          cols - 1,
        );
        sum[i] += v;
        cnt[i]++;
        all += v;
        k++;
      }
      return (
        [for (var i = 0; i < cols; i++) cnt[i] == 0 ? null : sum[i] / cnt[i]],
        k == 0 ? null : all / k,
      );
    }

    final noc = n['nocturnal'];
    final avgHr = noc is Map ? noc['sleeping_hr_avg'] as num? : null;
    final minHr = noc is Map ? noc['sleeping_hr_min'] as num? : null;
    final respV = n['resp'] is Map ? (n['resp'] as Map)['value'] as num? : null;
    final (hrLine, hrMean) = lane('hr');
    final (hrvLine, hrvMean) = lane('hrv');
    final (tempLine, _) = lane('skin_temp');
    final (respLine, _) = lane('resp');
    final hrv = d.hrvNight ?? hrvMean;
    final z = d.skinTempZ;

    final rows = <(String, String, String, Color, List<double?>, String)>[
      if (avgHr != null || hrMean != null)
        (
          loc?.sleepDetailHeartRate ?? 'Heart rate',
          '${(avgHr ?? hrMean)!.round()} bpm',
          minHr == null ? 'average' : 'average · lowest ${minHr.round()}',
          C.heart,
          hrLine,
          'resting_hr',
        ),
      if (hrv != null)
        (
          'HRV',
          '${hrv.round()} ms',
          'through the night',
          C.green,
          hrvLine,
          'hrv',
        ),
      if (z != null || tempLine.any((v) => v != null))
        (
          loc?.sleepDetailSkinTemp ?? 'Skin temperature',
          z == null
              ? 'measured'
              : '${z >= 0 ? '+' : '−'}${z.abs().toStringAsFixed(1)}',
          z == null
              ? 'relative reading'
              : z.abs() < 1
              ? 'about usual'
              : (z > 0 ? 'warmer than usual' : 'cooler than usual'),
          C.orange,
          tempLine,
          'skin_temp',
        ),
      if (respV != null)
        (
          loc?.sleepDetailBreathing ?? 'Breathing',
          '${respV.toStringAsFixed(1)} br/min',
          'average',
          C.teal,
          respLine,
          'resp_rate',
        ),
    ];
    if (rows.isEmpty) return _noOvernightLines(c);
    return Surface(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: p.line, height: S.x6),
            Pressable(
              onTap: () => go(c, MetricDetail.at(rows[i].$6, d.day)),
              semanticLabel: '${rows[i].$1} ${rows[i].$2}, open its trend',
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rows[i].$1, style: F.cap.copyWith(color: p.ink3)),
                        const SizedBox(height: 2),
                        Text(
                          rows[i].$2,
                          style: F.n17.copyWith(color: p.on(rows[i].$4)),
                        ),
                        Text(rows[i].$3, style: F.over.copyWith(color: p.ink3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    flex: 6,
                    child: SizedBox(
                      height: 40,
                      child: rows[i].$5.where((v) => v != null).length < 2
                          ? const SizedBox.shrink()
                          : CustomPaint(
                              size: Size.infinite,
                              painter: LineChart(
                                rows[i].$5,
                                p.on(rows[i].$4),
                                fill: false,
                                t: animate(c, 1),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: S.x2),
                  Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
                ],
              ),
            ),
          ],
        ],
      ),
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
    final l = AppLocalizations.of(c);
    final band = _band(history);

    final head = Row(
      children: [
        Expanded(
          child: Text(label, style: F.body.copyWith(color: p.ink)),
        ),
        const SizedBox(width: S.x2),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: F.n17.copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );

    if (band == null) {
      // The value is real, the comparison is not available yet. Say which is
      // which rather than dropping the row or drawing an empty band.
      return Column(
        children: [
          head,
          const SizedBox(height: S.x1),
          Text(
            l?.sleepDetailNoPersonalRangeYet(history.length, _minNights) ??
                'No personal range yet — ${history.length} of $_minNights nights.',
            style: F.over.copyWith(color: p.ink3),
          ),
        ],
      );
    }

    final verdict = tonight < band.lo
        ? '${dfmt((band.mid - tonight).abs())} $low'
        : tonight > band.hi
        ? '${dfmt((tonight - band.mid).abs())} $high'
        : (l?.sleepDetailTypicalForYou ?? 'Typical for you');

    final lo = math.min(tonight, history.reduce(math.min));
    final hi = math.max(tonight, history.reduce(math.max));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head,
        const SizedBox(height: S.x3),
        _Strip(
          lo: lo,
          hi: hi,
          bandLo: band.lo,
          bandHi: band.hi,
          mark: tonight,
          color: color,
        ),
        const SizedBox(height: S.x2),
        Text(
          l?.sleepDetailVerdictSummary(
                verdict,
                fmt(band.lo),
                fmt(band.hi),
                band.n,
              ) ??
              '$verdict · usual ${fmt(band.lo)}–${fmt(band.hi)} over ${band.n} '
                  'nights',
          style: F.over.copyWith(color: p.ink3, height: 1.5),
        ),
      ],
    );
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
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 5,
                  width: w,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.track,
                      borderRadius: R.rPill,
                    ),
                  ),
                ),
                Positioned(
                  left: math.min(left, w - width),
                  top: 5,
                  width: width,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.on(color),
                      borderRadius: R.rPill,
                    ),
                  ),
                ),
                Positioned(
                  left: (f(mark) * w - 1.5).clamp(0.0, w - 3),
                  top: 0,
                  width: 3,
                  height: 18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.ink,
                      borderRadius: R.rPill,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Nights the bedtime-consistency row looks back over.
const int kBedtimeNights = 14;

/// Standard deviation of bedtimes, in minutes, from signed minutes relative to
/// one night (wrapped across midnight). Null under seven nights.
double? bedtimeSpreadMin(List<double> relMinutes) {
  if (relMinutes.length < 7) return null;
  final mean = relMinutes.reduce((a, b) => a + b) / relMinutes.length;
  final v =
      relMinutes.fold<double>(0, (a, x) => a + (x - mean) * (x - mean)) /
      relMinutes.length;
  return math.sqrt(v);
}

/// Plain words for a bedtime spread: within half an hour is steady.
String bedtimeWord(double spreadMin) => spreadMin <= 30
    ? 'Steady'
    : spreadMin <= 60
    ? 'Varies'
    : 'Irregular';
