// TRAIN — one page: start a session, see the week's strain, and open any
// recent session. No sub-tabs.

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../build_profile.dart';
import '../../data/db.dart';
import '../../gps/gps_source.dart';
import '../../gps/route_models.dart';
import '../../compute/streak.dart';
import '../../data/day_label.dart' show dayLabelOf, todayLabel;
import '../../gps/motion_window.dart';
import '../../gps/workout_measurements.dart';
import '../../gps/workout_clock.dart';
import '../../gps/route_math.dart'
    show
        totalDistanceMeters,
        movingSeconds,
        computeSplits,
        kMetersPerKm,
        kMetersPerMile;
import '../../compute/day_upkeep.dart' show sessionProfile;
import '../../compute/profile.dart';
import '../../data/profile_history.dart';
import '../../gps/run_analysis.dart'
    show elevationGain, kBestEffortDistances, motionMix, riegel, runMix;
import '../../gps/run_history.dart';
import '../../health/health_import_state.dart';
import '../../health/auto_workout_import.dart';
import '../../health/health_workout_import.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart';
import '../activity/day_strain.dart';
import '../activity/live.dart';
import '../activity/picker.dart';
import '../activity/poster.dart' show PosterStatRow;
import '../activity/setup.dart';
import '../activity/summary.dart';
import '../charts.dart';
import '../grammar.dart';
import '../revision.dart';
import '../theme.dart';
import 'home_screen.dart' show calendarDaysBetween, pad, pullToRefresh;
import 'food_picker.dart' show SwipeDelete;
import 'metric_detail.dart' show dayNavLabel, detailLinkRow, detailScaffold;
import '../../data/local_repository.dart' show LocalRepository;
import 'log_workout.dart';
import 'training_review.dart';

/// Shared destination for a notification, lock-screen tap or saved session.
class SessionDestination extends StatefulWidget {
  const SessionDestination(this.id, {super.key});
  final String? id;
  @override
  State<SessionDestination> createState() => _SessionDestinationState();
}

class _SessionDestinationState extends State<SessionDestination> {
  Widget? _screen;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _failed = false);
    final app = context.read<AppState>();
    try {
      final id = widget.id ?? app.activeWorkout?.workoutId;
      if (id == null) {
        if (mounted) setState(() => _screen = const WorkoutScreen());
        return;
      }
      if (app.activeWorkout?.workoutId == id) {
        final activity = activityByName(app.activeWorkout!.type);
        if (activity != null) {
          final history = await loadSetHistory();
          if (mounted)
            setState(
              () => _screen = liveFor(
                activity,
                private: LiveDraft.current?.private ?? false,
                weightKg: LiveDraft.current?.weightKg,
                host: activityHost(app, history: history),
              ),
            );
          return;
        }
      }
      final row = await LocalDb.session(id);
      final start = row?['start_ts'] as num?;
      final end = row?['end_ts'] as num?;
      final activity = activityByName(row?['type']?.toString());
      if (start == null || end == null || activity == null) {
        if (mounted)
          setState(
            () => _screen = detailScaffold(context, 'Session', [
              const StatusCard(
                'Session unavailable',
                'It may have been removed.',
              ),
            ]),
          );
        return;
      }
      final at = DateTime.fromMillisecondsSinceEpoch(start.toInt() * 1000);
      final stop = DateTime.fromMillisecondsSinceEpoch(end.toInt() * 1000);
      final clock = WorkoutClock.read(id, at, end: stop);
      final priced = await sessionProfile(
        id,
        at,
        Profile.fromMap(app.user),
        end: stop,
      );
      final result = await _detailOf(
        app,
        _PastWorkout(
          id,
          activity,
          at,
          clock.activeDuration(stop),
          private: row?['private'] == 1,
          calories: isRunType(activity.typeKey) || isWalkType(activity.typeKey)
              ? (row?['calories'] as num?)?.round()
              : sessionActiveKcal(
                  p: priced,
                  type: activity.typeKey,
                  minutes: clock.activeDuration(stop).inSeconds / 60,
                  meanHr: (row?['avg_hr'] as num?)?.toDouble(),
                  catalogueMet: activity.met,
                )?.round(),
          steps: (row?['steps'] as num?)?.round(),
        ),
      );
      if (mounted) setState(() => _screen = ActivitySummary(result));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext c) =>
      _screen ??
      detailScaffold(c, 'Session', [
        if (_failed)
          StatusCard(
            'Session could not load',
            'Your saved data is intact.',
            fix: 'Retry',
            onFix: _load,
          )
        else
          const Center(child: CircularProgressIndicator()),
      ]);
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> with RevisionReload {
  Future<_WorkoutData>? _load;

  /// The one Recent row open in place, if any.
  String? _openId;

  /// The day under the finger on the 7-day strain bars, and the week under it
  /// on distance per week. Null until a finger lands.
  int? _strainPick, _weekPick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `_load ??=` alone meant the screen read the database exactly once, for
    // the life of the widget — so a session you had just finished was absent
    // from History, "This week", "Tracked" and the weekly load until the app
    // was restarted. `RevisionReload` re-reads when the data moves: the manual
    // finish, the gesture path, the Live Activity and an import alike.
    _load ??= _loadWorkoutData(context.read<AppState>());
  }

  @override
  void reload() {
    setState(() {
      _load = _loadWorkoutData(context.read<AppState>());
    });
  }

  @override
  Widget build(BuildContext c) {
    return FutureBuilder<_WorkoutData>(
      future: _load,
      builder: (c, snap) {
        final d = snap.data ?? const _WorkoutData.empty();
        return RefreshIndicator(
          onRefresh: () => pullToRefresh(c, () async {
            runsChanged();
            reload();
            await _load;
          }),
          child: ListView(
            padding: pad,
            children: [
              const ScreenTitle('Train'),
              if (snap.hasError)
                StatusCard(
                  'Training history could not load',
                  'Your saved sessions are intact.',
                  fix: 'Retry',
                  onFix: reload,
                )
              else if (!snap.hasData)
                const Center(child: CircularProgressIndicator())
              else
                ..._page(c, d),
            ],
          ),
        );
      },
    );
  }

  void _openPicker(BuildContext c, _WorkoutData d) => Navigator.of(c).push(
    MaterialPageRoute(
      builder: (_) => ActivityPicker(
        weightKg: d.weightKg,
        host: _host(d),
        recent: d.recent,
      ),
    ),
  );

  ActivityHost _host(_WorkoutData d) =>
      activityHost(context.read<AppState>(), history: d.setHistory);

  // ─────────────── HISTORY ───────────────

  /// Open a screen that can write a session, then re-read. Every write path on
  /// this tab goes through here: `RevisionReload` covers the writers that bump
  /// `AppState.insightsRevision`, and this covers the ones that do not.
  Future<void> _push(BuildContext c, Widget w) async {
    await Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));
    if (mounted) reload();
  }

  /// The detector's unreviewed bouts, at the top of History where the sessions
  /// they might become are listed.
  ///
  /// This is the surface that was missing, not a second copy of one: for the
  /// whole time the notification was emitted on the `recovery` channel it was
  /// dropped by `classOf` and never fired, so these rows accumulated unseen.
  /// It fires now (reminders channel, NotifClass.prompt) and lands on the one
  /// bout it is about — but only for a bout detected in the last ~2 h, so
  /// everything drained later still has to be reviewable here.
  List<Widget> _suggestionCards(BuildContext c, _WorkoutData d) {
    if (d.suggestions.isEmpty) return const [];
    final loc = AppLocalizations.of(c);
    final n = d.suggestions.length;
    return [
      StatusCard(
        loc?.workoutSuggestionsTitle(n) ??
            (n == 1
                ? '$n effort we spotted but did not log'
                : '$n efforts we spotted but did not log'),
        loc?.workoutSuggestionsBody ??
            'The band saw sustained work and nothing was started for it. Nothing '
                'is logged until you say so.',
        fix: loc?.workoutReviewFix(n) ?? 'Review ${n == 1 ? 'it' : 'them'}',
        icon: LucideIcons.radar,
        onFix: () =>
            _push(c, WorkoutSuggestionScreen(preloaded: d.suggestions)),
      ),
      const SizedBox(height: S.x5),
    ];
  }

  List<Widget> _page(BuildContext c, _WorkoutData d) {
    final p = P.of(c);
    final loc = AppLocalizations.of(c);
    Activity act(String name) =>
        allActivities.firstWhere((a) => a.name == name);
    void start(Activity a) =>
        _push(c, ActivitySetup(a, weightKg: d.weightKg, host: _host(d)));
    return [
      // The fortnight review is hidden in the personal build (Akshat, build
      // 78): his runs are occasional, so it was mostly an empty screen. Its
      // computation and the sessions it reads are unchanged.
      if (!kPersonalSideload) ...[
        detailLinkRow(
          c,
          LucideIcons.chartNoAxesCombined,
          'Training review',
          'Compare the last two fortnights using measured sessions',
          () => _push(c, const TrainingReviewScreen()),
        ),
        const SizedBox(height: S.x3),
      ],
      Row(
        children: [
          Expanded(
            child: _QuickTile(
              LucideIcons.footprints,
              C.run,
              'Run',
              () => start(act('Running')),
            ),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: _QuickTile(
              LucideIcons.personStanding,
              C.steps,
              'Walk',
              () => start(act('Walking')),
            ),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: _QuickTile(
              LucideIcons.dumbbell,
              C.purple,
              'Lift',
              () => start(act('Weight training')),
            ),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: _QuickTile(
              LucideIcons.ellipsis,
              C.n500,
              'Other',
              () => _openPicker(c, d),
            ),
          ),
        ],
      ),
      const SizedBox(height: S.x3),
      if (d.streak != null) ...[
        _streakCard(c, p, d.streak!),
        const SizedBox(height: S.x3),
      ],
      ..._suggestionCards(c, d),
      if (d.strain7.any((v) => v != null)) _strainWeek(c, p, d),
      if (d.runs.isNotEmpty) _running(c, p, d.runs),
      ..._importCard(c, d),
      Section(
        'Recent',
        d.workouts.isEmpty
            ? StatusCard(
                loc?.workoutNoSessionsTitle ?? 'No sessions recorded yet',
                'Start one above.',
                icon: LucideIcons.dumbbell,
              )
            : Column(
                children: [
                  // The last five as one-line rows; a tap opens one in place.
                  // Everything older lives on the history page, so this
                  // section never grows with the month.
                  for (final w in d.workouts.take(5)) ...[
                    _sessionRow(c, d, w),
                    const SizedBox(height: S.x2),
                  ],
                  const SizedBox(height: S.x1),
                  detailLinkRow(
                    c,
                    LucideIcons.history,
                    'All workouts',
                    'Every session, by month',
                    () => _push(c, WorkoutHistoryScreen(weightKg: d.weightKg)),
                  ),
                ],
              ),
        action: 'Add a past one',
        onAction: () => _push(c, const LogWorkout()),
      ),
    ];
  }

  /// One collapsible session row: swipe either way to delete, tap to open.
  Widget _sessionRow(BuildContext c, _WorkoutData d, _PastWorkout w) =>
      historyRow(
        c,
        w,
        weightKg: d.weightKg,
        expanded: _openId == _rowKey(w),
        onToggle: () => setState(
          () => _openId = _openId == _rowKey(w) ? null : _rowKey(w),
        ),
        onChanged: reload,
      );

  /// Running, across every recorded run: weekly distance for eight weeks,
  /// predicted 5K and 10K times, and the best time at each distance. Updates
  /// with each new run.
  Widget _running(BuildContext c, P p, List<RunSummary> runs) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final weeks = List<double?>.filled(8, null);
    for (final r in runs) {
      final w =
          (monday
                      .difference(
                        DateTime(r.start.year, r.start.month, r.start.day),
                      )
                      .inDays /
                  7)
              .ceil();
      final slot = r.start.isBefore(monday) ? 7 - w : 7;
      if (slot >= 0 && slot < 8) {
        weeks[slot] = (weeks[slot] ?? 0) + r.meters / 1000;
      }
    }
    final p5 = predicted5k(runs);
    String t(double sec) => clock(sec.round());
    final prs = <(String, double, DateTime)>[];
    for (final (label, _) in kBestEffortDistances) {
      (double, DateTime)? best;
      for (final r in runs) {
        final s = r.efforts[label];
        if (s != null && (best == null || s < best.$1)) best = (s, r.start);
      }
      if (best != null) prs.add((label, best.$1, best.$2));
    }
    final axis = AxisSpec.of([for (final v in weeks) ?v], floor: 0);
    String weekSays(int i) {
      final from = DateTime(
        monday.year,
        monday.month,
        monday.day - 7 * (7 - i),
      );
      final km = weeks[i];
      return '${i == 7 ? 'This week' : 'Week of ${from.day}/${from.month}'} · '
          '${km == null ? 'no runs' : '${km.toStringAsFixed(1)} km'}';
    }

    final wk = _weekPick;
    return Section(
      'Running',
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (axis != null)
              ChartFrame(
                title: 'Distance per week',
                unit: 'km',
                height: 88,
                yAxis: axis,
                xLabels: const ['8 weeks ago', 'This week'],
                series: weeks,
                readout: wk == null ? null : weekSays(wk),
                child: Scrubber(
                  value: wk == null ? null : (wk + .5) / 8,
                  step: 1 / 8,
                  label: 'Distance per week',
                  describe: (v) => weekSays((v * 8).floor().clamp(0, 7)),
                  onChanged: (v) =>
                      setState(() => _weekPick = (v * 8).floor().clamp(0, 7)),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: Bars(
                      weeks,
                      p.on(C.run),
                      highlight: weeks.last == null ? -1 : 7,
                      cursor: wk,
                      axis: axis,
                      t: animate(context, 1),
                    ),
                  ),
                ),
              ),
            if (p5 != null) ...[
              const SizedBox(height: S.x4),
              InlineMetrics([
                ('PREDICTED 5K', t(p5), C.run),
                ('PREDICTED 10K', t(riegel(p5, 5000, 10000)), C.run),
              ]),
            ],
            if (prs.isNotEmpty) ...[
              const SizedBox(height: S.x4),
              Text('Best times', style: F.over.copyWith(color: p.ink3)),
              for (final (label, sec, at) in prs)
                Padding(
                  padding: const EdgeInsets.only(top: S.x2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: F.body.copyWith(color: p.ink),
                        ),
                      ),
                      Text(
                        '${t(sec)} · ${at.day}/${at.month}',
                        style: F.cap.copyWith(color: p.ink2),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// The day's strain for each of the last seven days. Drag across to read
  /// each day; a tap opens the day under the finger (today until one is
  /// picked), with arrows to step through the others.
  Widget _strainWeek(BuildContext c, P p, _WorkoutData d) {
    final end = d.weekEnd ?? DateTime.now();
    DateTime dayAt(int i) => DateTime(end.year, end.month, end.day - (6 - i));
    final axis = AxisSpec.of([for (final v in d.strain7) ?v], floor: 0);
    String says(int i) {
      final v = d.strain7[i];
      return '${dayNavLabel(dayLabelOf(dayAt(i)))} · '
          '${v == null ? 'no strain' : v.toStringAsFixed(1)}';
    }

    final pick = _strainPick;
    return Surface(
      onTap: () => _push(
        c,
        DayStrainDetail(day: pick == null ? null : dayLabelOf(dayAt(pick))),
      ),
      semanticLabel: 'Strain, last 7 days. Opens the day.',
      child: ChartFrame(
        title: 'Strain, last 7 days',
        unit: '0–21',
        height: 88,
        yAxis: axis,
        readout: pick == null ? null : says(pick),
        xLabels: [for (var i = 0; i < 7; i++) _weekdayLetter(c, dayAt(i))],
        series: d.strain7,
        child: Scrubber(
          // A line like every other day-by-day chart: point i sits at i/6.
          value: pick == null ? null : pick / 6,
          step: 1 / 6,
          label: 'Strain, last 7 days',
          describe: (v) => says((v * 6).round().clamp(0, 6)),
          onChanged: (v) =>
              setState(() => _strainPick = (v * 6).round().clamp(0, 6)),
          child: CustomPaint(
            size: Size.infinite,
            // Today is the last slot, always — not "the newest value".
            painter: LineChart(
              d.strain7,
              p.on(C.strain),
              dots: true,
              dotInk: p.card,
              cursor: pick,
              cursorInk: p.ink,
              axis: axis,
              t: animate(context, 1),
            ),
          ),
        ),
      ),
    );
  }

  /// Days in a row with at least ten minutes of running or walking.
  Widget _streakCard(BuildContext c, P p, MoveStreak s) {
    final now = DateTime.now();
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${s.current}', style: F.n34.copyWith(color: p.ink)),
              const SizedBox(width: S.x2),
              Padding(
                padding: const EdgeInsets.only(bottom: S.x1),
                child: Text('day streak', style: F.cap.copyWith(color: p.ink2)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: S.x1),
                child: Text(
                  'Longest ${s.longest}',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: switch (s.last7[i]) {
                            MoveDay.run => p.on(C.run),
                            MoveDay.walk => p.on(C.steps),
                            MoveDay.goal => p.on(C.green),
                            MoveDay.lift => p.on(C.purple),
                            MoveDay.other => p.on(C.teal),
                            // Kept, not earned: drawn as an outline.
                            MoveDay.rest || MoveDay.life => p.bg,
                            MoveDay.none => p.track,
                          },
                          border:
                              s.last7[i] == MoveDay.rest ||
                                  s.last7[i] == MoveDay.life
                              ? Border.all(color: p.ink3, width: 1.5)
                              : null,
                        ),
                      ),
                      const SizedBox(height: S.x1),
                      Text(
                        _weekdayLetter(
                          c,
                          DateTime(now.year, now.month, now.day - (6 - i)),
                        ),
                        style: F.over.copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.x3),
          Text(
            [
              s.todayDone
                  ? 'Today counts.'
                  : s.last7.last == MoveDay.rest
                  ? 'Rest day planned. It keeps the streak; it is not counted.'
                  : s.current > 0
                  ? 'Your step goal or 10 minutes of exercise keeps it going.'
                  : 'Complete your step goal or record 10 minutes of exercise.',
              if (s.protectedInStreak > 0)
                '${s.protectedInStreak} protected '
                    '${s.protectedInStreak == 1 ? 'day' : 'days'} in this streak.',
            ].join(' '),
            style: F.cap.copyWith(color: p.ink3),
          ),
          ..._protectActions(c, p, s),
        ],
      ),
    );
  }

  /// Plan rest for today, or mark a missed yesterday as "Life happens",
  /// within the allowance in `streak.dart` (B86-10). Neither records any
  /// activity; both can be undone.
  List<Widget> _protectActions(BuildContext c, P p, MoveStreak s) {
    final now = DateTime.now();
    final today = todayLabel();
    final yesterday = dayLabelOf(DateTime(now.year, now.month, now.day - 1));
    Future<void> act(Future<String?> Function() f) async {
      final why = await f();
      if (!c.mounted) return;
      if (why != null) {
        ScaffoldMessenger.maybeOf(c)?.showSnackBar(SnackBar(content: Text(why)));
      }
      reload();
    }

    Widget link(String label, VoidCallback onTap) => Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: S.x2, right: S.x4),
        child: Text(label, style: F.cap.copyWith(color: p.ink2)),
      ),
    );
    final todayKept =
        s.last7.last == MoveDay.rest || s.last7.last == MoveDay.life;
    final yesterdayMissed = s.last7[5] == MoveDay.none;
    final links = [
      if (!s.todayDone && !todayKept)
        link(
          'Rest today',
          () => act(() => StreakProtection.protect(today, Protection.rest)),
        ),
      if (todayKept)
        link('Undo rest', () => act(() async {
          await StreakProtection.clear(today);
          return null;
        })),
      // Only worth offering when it would join two real activity runs.
      if (yesterdayMissed && s.last7[4] != MoveDay.none)
        link(
          'Yesterday: life happens',
          () => act(() => StreakProtection.protect(yesterday, Protection.life)),
        ),
    ];
    return links.isEmpty ? const [] : [Wrap(children: links)];
  }

  /// Delete one session — recorded or imported. For an IMPORTED session the
  /// health-store uuid goes onto a tombstone list first, or the next import
  /// (manual, or the hourly auto path) would bring the very row the user just
  /// removed straight back. A copy in Apple Health / Health Connect itself is
  /// out of our reach by design and the confirm says so.
  /// Bring in what another app recorded. On History because that is the list
  /// it joins — it used to live three taps deep under More settings, next to a
  /// database export, which is not where anybody looks for their Sunday run.
  List<Widget> _importCard(BuildContext c, _WorkoutData d) {
    if (kPersonalSideload) return const [];
    final p = P.of(c);
    final loc = AppLocalizations.of(c);
    return [
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ONE ROW in the parent card — no nested box: tick = hourly sweep,
            // ↻ = fetch NOW (only meaningful while the tick is on). The
            // refresh tap is the only thing that ever prompts for access.
            Row(
              children: [
                Pressable(
                  semanticLabel: _autoImport
                      ? (loc?.workoutAutoImportOnLabel ??
                            'Auto-import on. Tap to turn off.')
                      : (loc?.workoutAutoImportOffLabel ??
                            'Auto-import off. Tap to turn on.'),
                  onTap: () => _setAutoImport(!_autoImport),
                  child: Icon(
                    _autoImport
                        ? LucideIcons.circleCheckBig
                        : LucideIcons.circle,
                    size: 22,
                    color: _autoImport ? p.on(C.domMove) : p.ink3,
                  ),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(
                    loc?.workoutImportFromStore(storeName) ??
                        'Import from $storeName',
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Pressable(
                  semanticLabel:
                      loc?.workoutFetchNowLabel ?? 'Fetch workouts now',
                  onTap: (!_autoImport || _importing)
                      ? null
                      : () => unawaited(_importWorkouts()),
                  child: Padding(
                    padding: const EdgeInsets.all(S.x2),
                    child: _importing || !_autoImport
                        ? Icon(LucideIcons.refreshCw, size: 18, color: p.ink3)
                        : Icon(
                            LucideIcons.refreshCw,
                            size: 18,
                            color: p.on(C.domMove),
                          ),
                  ),
                ),
              ],
            ),
            if (_importNote != null) ...[
              const SizedBox(height: S.x3),
              Text(
                _importNote!,
                style: F.cap.copyWith(
                  color: _importFailed ? p.on(C.red) : p.ink2,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  bool _importing = false;
  bool _autoImport = false;
  String? _importNote;
  bool _importFailed = false;

  @override
  void initState() {
    super.initState();
    if (kPersonalSideload) return;
    () async {
      final on = await AutoWorkoutImport.isEnabled();
      if (!mounted) return;
      setState(() => _autoImport = on);
      if (on) unawaited(AutoWorkoutImport.maybeRun());
    }();
  }

  Future<void> _setAutoImport(bool v) async {
    if (kPersonalSideload) return;
    setState(() => _autoImport = v);
    await AutoWorkoutImport.setEnabled(v);
    // Silent by design: the tick only arms the hourly sweep. The refresh
    // icon beside it is what asks for access.
    if (v) unawaited(AutoWorkoutImport.maybeRun());
  }

  /// Read the store, then reload the tab so the new rows are in the list the
  /// user is looking at.
  ///
  /// Re-reading the WHOLE window every time rather than only what is new: the
  /// table is keyed on the health store's own uuid and the write replaces, so
  /// a second pass over the same run updates that one row instead of stacking
  /// a copy. It also picks up a workout the source app edited or back-dated
  /// after the fact, which a "since last time" cursor would miss forever.
  Future<void> _importWorkouts({bool silent = false}) async {
    if (kPersonalSideload) return;
    if (_importing) return;
    setState(() {
      _importing = true;
      // The auto path shares this body but must not speak over it: no note
      // clearing, and its outcomes are silent by design.
      if (!silent) _importNote = null;
    });
    final importer = HealthWorkoutImporter();
    try {
      // Asked HERE, on the tap, and for WORKOUT alone. Nothing at launch and
      // nothing in onboarding — a sheet asking for data the user has not asked
      // us to read is how the whole set gets denied in one go.
      if (!await importer.requestPermission()) {
        if (!mounted) return;
        final loc = AppLocalizations.of(context);
        setState(() {
          _importNote =
              loc?.workoutImportDenied(storeName) ??
              '$storeName did not grant workouts. Nothing was read.';
          _importFailed = true;
        });
        return;
      }
      final res = await importer.sync();
      if (res.workouts == 0) {
        if (!mounted) return;
        final loc = AppLocalizations.of(context);
        setState(() {
          _importNote =
              loc?.workoutImportEmpty(storeName) ??
              'Nothing came back. $storeName holds no workouts '
                  'inside the window it will share.';
          _importFailed = false;
        });
        return;
      }
      // Only now. A denied read on iOS comes back as an empty list rather than
      // as an error, so marking a zero-row read as done would put "Refresh" on
      // the button for someone who said no.
      await markImported(HealthImport.workouts);
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      final route = !res.routesSupported
          // Said with the result rather than near it: this is the moment the
          // user is looking for their map.
          ? (loc?.workoutImportNoRoutes(storeName) ??
                ' $storeName will not share routes, so none have coordinates.')
          : res.withRoutes == 0
          ? (loc?.workoutImportNoneWithRoute ??
                ' None of them had a route recorded.')
          : (loc?.workoutImportSomeWithRoute(res.withRoutes) ??
                ' ${res.withRoutes} came with a route.');
      if (!mounted) return;
      setState(() {
        _importNote =
            (loc?.workoutImportBroughtIn(res.workouts) ??
                '${res.workouts} workout'
                    '${res.workouts == 1 ? '' : 's'} brought in.') +
            route;
        _importFailed = false;
      });
    } catch (e) {
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      setState(() {
        _importNote = loc?.workoutImportFailed(e.toString()) ?? 'Failed: $e';
        _importFailed = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _load = _loadWorkoutData(context.read<AppState>());
        });
      }
    }
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _QuickTile(this.icon, this.color, this.label, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      pad: const EdgeInsets.symmetric(vertical: S.x5, horizontal: S.x2),
      onTap: onTap,
      semanticLabel: 'Start $label',
      child: Column(
        children: [
          // A coloured disc per activity (build 85): the start buttons read
          // as four doors, not four icons on a card.
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.wash(color),
              shape: BoxShape.circle,
              border: Border.all(color: p.on(color).withValues(alpha: .35)),
            ),
            child: Icon(icon, size: 22, color: p.on(color)),
          ),
          const SizedBox(height: S.x2),
          Text(
            label,
            style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// One past session. Taps through to the same summary a live session lands
/// on, built from the stores rather than from the six columns in this row —
/// the heart-rate curve, the sets and the route are all read on open.
class _HistoryRow extends StatelessWidget {
  final _PastWorkout w;
  final double? weightKg;

  /// Widen or correct this session's window. Null for an imported row, and for
  /// a session with no id to retime.
  final VoidCallback? onRetime;

  /// Remove this session locally. Null hides the control (no id to delete).
  final VoidCallback? onDelete;

  /// Collapsed rows show one line (name, date, duration, strain); a tap opens
  /// the full card in place. Null [onToggle] keeps the card always open.
  final bool expanded;
  final VoidCallback? onToggle;

  const _HistoryRow(
    this.w, {
    this.weightKg,
    this.onRetime,
    this.onDelete,
    this.expanded = true,
    this.onToggle,
  });

  Future<void> _open(BuildContext c) async {
    final nav = Navigator.of(c);
    final r = await _detailOf(c.read<AppState>(), w);
    await nav.push(
      MaterialPageRoute(builder: (_) => ActivitySummary(r, weightKg: weightKg)),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final loc = AppLocalizations.of(c);
    final a = w.activity;
    final pairedCalories =
        w.importedFrom == null &&
        (isRunType(a.typeKey) || isWalkType(a.typeKey));
    final stats = _stats(c)
        .where(
          (s) =>
              !pairedCalories ||
              (!s.$1.startsWith('Budget') && !s.$1.startsWith('ACSM')),
        )
        .toList();
    return Surface(
      // An imported row does not open. The summary screen behind this tap is
      // built to show a session THIS band measured — its rating control, its
      // heart-rate trace, its zone split — and it has nowhere to say whose
      // workout it is. A screen that presents an Apple Watch run exactly like
      // one of ours is the fabrication this whole table exists to avoid, so
      // the row stays a row until that screen can name its source.
      onTap: onToggle ?? (w.importedFrom == null ? () => _open(c) : null),
      semanticLabel: onToggle == null
          ? null
          : '${w.importedTitle ?? a.name}, ${w.when(loc)}, '
                '${expanded ? 'tap to close' : 'tap for details'}',
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.wash(a.color),
                  borderRadius: R.rMd,
                ),
                child: Icon(a.icon, size: 19, color: p.on(a.color)),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          // The store's own word for it when it is not ours: the
                          // catalogue knows the ~40 types this app can start, and
                          // "Workout" over a surf loses the one thing we were told.
                          child: Text(
                            w.importedTitle ?? a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: F.body.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // The flag the setup screen promised, visible on the one
                        // list this session shows up in.
                        if (w.private) ...[
                          const SizedBox(width: S.x2),
                          Icon(LucideIcons.lock, size: 13, color: p.ink3),
                        ],
                      ],
                    ),
                    // "Apple Watch · Today, 07:12". The source is not decoration
                    // and it is not the word "imported": a band-measured session
                    // and an Apple Watch session are different measurements, and
                    // the name of the thing that took it is the difference.
                    Text(
                      [
                        if (w.importedFrom != null) w.importedFrom!,
                        w.when(loc),
                        if (w.duration.inMinutes > 0)
                          '${w.duration.inMinutes} min',
                      ].join(' · '),
                      style: F.over.copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
              if (w.strain != null) ...[
                Text(
                  w.strain!.toStringAsFixed(1),
                  style: F.n17.copyWith(color: p.ink),
                ),
                const SizedBox(width: S.x1),
                Padding(
                  padding: const EdgeInsets.only(top: S.x1),
                  // "strain", not "load". Training load is CTL/ATL over weeks;
                  // this is one session's 0–21 strain, and the two were being
                  // shown under the same word on the same screen.
                  child: Text(
                    loc?.workoutStrainLabel ?? 'strain',
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ),
              ],
              // Delete sits BEFORE the chevron and is drawn whether or not the
              // row is open, so opening a row never slides the chevron and
              // puts the trash under the next tap (B86-06). It still asks.
              if (onDelete != null) ...[
                const SizedBox(width: S.x2),
                Pressable(
                  semanticLabel:
                      loc?.workoutDeleteSessionLabel ?? 'Delete this session',
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(S.x1),
                    child: Icon(LucideIcons.trash2, size: 17, color: p.ink3),
                  ),
                ),
              ],
              if (onToggle != null) ...[
                const SizedBox(width: S.x2),
                Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18,
                  color: p.ink3,
                ),
              ],
            ],
          ),
          if (expanded && w.zoneMinutes.length == 5) ...[
            const SizedBox(height: S.x4),
            ChartFrame(
              title: loc?.workoutTimeInZonesTitle ?? 'TIME IN ZONES',
              unit: loc?.workoutMinutesUnit ?? 'minutes',
              height: 8,
              legend: [
                for (var i = 0; i < 5; i++)
                  (
                    'Z${i + 1} · ${w.zoneMinutes[i].round()}m',
                    ZoneBar.cols(p)[i],
                  ),
              ],
              child: CustomPaint(
                size: Size.infinite,
                painter: ZoneBar(w.zoneFractions, p),
              ),
            ),
          ],
          if (expanded) const SizedBox(height: S.x4),
          if (expanded && pairedCalories) ...[
            CaloriePair(
              budget: w.calories?.toDouble(),
              acsm: w.acsmCalories,
              compact: true,
              note:
                  'Active calories above resting; counted once in maintenance.',
            ),
            const SizedBox(height: S.x3),
          ],
          for (var i = 0; expanded && i < stats.length; i++) ...[
            if (i > 0) Divider(color: p.line, height: S.x5),
            PosterStatRow(
              icon: statIcon(stats[i].$1),
              label: stats[i].$1,
              value: stats[i].$2,
              unit: stats[i].$3,
              accent: p.on(a.color),
            ),
          ],
          // The way to correct a window the detector clipped, or one a session
          // started late. Nested inside the card's own tap: the inner Pressable
          // wins, so the row still opens the summary everywhere else.
          if (expanded && onToggle != null && w.importedFrom == null) ...[
            Divider(color: p.line, height: S.x5),
            Pressable(
              onTap: () => _open(c),
              semanticLabel: 'Open this session',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Open session',
                    style: F.cap.copyWith(
                      color: p.on(C.blue),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: S.x1),
                  Icon(LucideIcons.chevronRight, size: 14, color: p.on(C.blue)),
                ],
              ),
            ),
          ],
          if (expanded && onRetime != null) ...[
            Divider(color: p.line, height: S.x5),
            Pressable(
              onTap: onRetime,
              semanticLabel:
                  loc?.workoutFixTimesOnSessionLabel ??
                  'Fix the times on this session',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.clock, size: 14, color: p.on(C.blue)),
                  const SizedBox(width: S.x2),
                  Text(
                    loc?.workoutFixTimes ?? 'Fix the times',
                    style: F.cap.copyWith(
                      color: p.on(C.blue),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// `(name, value, unit)`. Absence is a WORD here rather than a dropped row,
  /// which is the one place this differs from the summary's own stat block:
  /// this is a LIST of sessions read against each other, and a card that
  /// quietly loses its calorie line reads as a lighter session rather than an
  /// uncosted one. The unit is null in that case — 'Not costed kcal' is not a
  /// sentence.
  List<(String, String, String?)> _stats(BuildContext c) {
    final loc = AppLocalizations.of(c);
    final timeLabel = loc?.workoutTimeStatLabel ?? 'Time';
    // Band sessions all show the conservative active estimate now; only an
    // imported row prints the other app's own figure.
    final caloriesLabel = w.importedFrom == null
        ? 'Budget · active'
        : loc?.workoutCaloriesStatLabel ?? 'Calories';
    return w.importedFrom != null
        ? [
            // An imported row prints only what the recording app actually
            // recorded, and drops the rest rather than saying "No reading": this
            // band was not on the wrist, so there is no reading it could have
            // taken and nothing was lost. The calories are the SOURCE's figure,
            // shown under the source's name a line above — never added to ours,
            // because two devices' calorie models summed is a number neither of
            // them would stand behind.
            (timeLabel, hms(w.duration), null),
            if (w.distanceM != null && w.distanceM! > 0)
              (
                loc?.workoutDistanceStatLabel ?? 'Distance',
                (w.distanceM! / 1000).toStringAsFixed(2),
                'km',
              ),
            if (w.calories != null)
              (caloriesLabel, grouped(w.calories!), 'kcal'),
          ]
        : [
            (timeLabel, hms(w.duration), null),
            if (w.calories == null)
              (caloriesLabel, loc?.workoutNotCostedValue ?? 'Not costed', null)
            else
              (caloriesLabel, grouped(w.calories!), 'kcal'),
            if (isRunType(w.activity.typeKey) || isWalkType(w.activity.typeKey))
              (
                'ACSM · active',
                w.acsmCalories == null ? '—' : grouped(w.acsmCalories!),
                'kcal',
              ),
            if (w.maxHr == null)
              (
                loc?.workoutMaxHrStatLabel ?? 'Max HR',
                loc?.workoutNoReadingValue ?? 'No reading',
                null,
              )
            else
              (loc?.workoutMaxHrStatLabel ?? 'Max HR', '${w.maxHr}', 'bpm'),
          ];
  }
}

/// One day's initial. Taken from the date the point carries — deriving it from
/// the point's position in the list is how a chart comes to name days its data
/// did not come from.
String _weekdayLetter(BuildContext c, DateTime d) {
  final loc = AppLocalizations.of(c);
  final letters = [
    loc?.workoutWeekdayLetterMon ?? 'M',
    loc?.workoutWeekdayLetterTue ?? 'T',
    loc?.workoutWeekdayLetterWed ?? 'W',
    loc?.workoutWeekdayLetterThu ?? 'T',
    loc?.workoutWeekdayLetterFri ?? 'F',
    loc?.workoutWeekdayLetterSat ?? 'S',
    loc?.workoutWeekdayLetterSun ?? 'S',
  ];
  return letters[d.weekday - 1];
}

/// `getChart` points → one slot per calendar day for the seven ending [end],
/// index 6 being [end] itself. A day with no point is null, which the painter
/// draws as a hole.
///
/// The alternative — "the last seven stored points" — is what made the axis
/// lie: `metric_series` only gains a row on a day that derives, so a sync gap
/// slid the whole week left and stamped today's letter on a week-old bar.
List<double?> lastSevenDays(Object? points, DateTime end) {
  final out = List<double?>.filled(7, null);
  if (points is! List) return out;
  for (final e in points) {
    if (e is! Map || e['v'] is! num || e['t'] is! num) continue;
    // `t` is noon local on the day the value belongs to.
    final at = DateTime.fromMillisecondsSinceEpoch(
      (e['t'] as num).toInt() * 1000,
    );
    // CALENDAR days, not elapsed hours: the day after a spring-forward is 23 h
    // long, `inDays` floored that to 0, and Sunday landed in Monday's slot
    // where Monday overwrote it. UTC midnights have no DST to floor.
    final slot =
        6 -
        DateTime.utc(
          end.year,
          end.month,
          end.day,
        ).difference(DateTime.utc(at.year, at.month, at.day)).inDays;
    if (slot < 0 || slot > 6) continue;
    out[slot] = (e['v'] as num).toDouble();
  }
  return out;
}

// ── the app seam ───────────────────────────────────────────────────────────
// Top-level, not methods: the live-session bar in `app.dart` reopens a
// minimised workout from outside this screen, and it needs the same session
// lifecycle rather than a second copy of it.

/// Everything the activity screens need from the app.
///
/// [history] is the user's own previous/best per lift. Absent is honest — the
/// live screen says "First time on this lift" — so the resume path passes what
/// it has rather than blocking on a query.
ActivityHost activityHost(
  AppState app, {
  Map<String, SetHistory> history = const {},
}) {
  // The id of the session this host opened, remembered across calls.
  //
  // `stopWorkout` clears `activeWorkout`, so a RETRY after a failed write —
  // the strength log throwing, say, which leaves the sessions row saved and
  // the sets lost — used to read a null id, return the draft untouched, throw
  // nothing, and be reported to the user as saved.
  String? sessionId;
  return ActivityHost(
    feed: () => _feedOf(app),
    onStart: (a) => _startSession(app, a),
    onFinish: (draft) {
      sessionId ??= app.activeWorkout?.workoutId;
      return _finishSession(app, draft, sessionId);
    },
    onSets: (sets) => _bankSets(app, sets),
    history: history,
    bandConnected: app.isConnected,
  );
}

/// The band, as the live screens see it. Read on every tick rather than
/// subscribed to: there is no stream on `AppState` — `AppState.liveHr` is a
/// getter over the field the engine writes and the UI pulls.
///
/// Six of these ten fields used to be left unset, which is why the zone
/// pill, the zone bar, the live distance and the session average heart rate
/// were all inert. They all have producers; none of them needed new science.
LiveFeed _feedOf(AppState app) {
  final w = app.activeWorkout;
  return LiveFeed(
    // The freshness-checked getter, not `device.liveHr`: the raw field keeps
    // its last value forever after an unintentional drop, which suppressed
    // LiveHeart's "The band is not connected" card exactly when it was true.
    hr: app.liveHr,
    maxHr: (w?.maxHrSeen ?? 0) > 0 ? w!.maxHrSeen : null,
    zone: app.liveZone,
    calories: app.workoutActiveKcal,
    hrActiveCalories: app.workoutHrActiveKcal,
    acsmCalories: app.workoutAcsmKcal,
    strain: w?.strain,
    steps: app.workoutStepCount,
    cadence: app.workoutCadence?.spm,
    cadenceSource: app.workoutCadence?.source,
    zoneMinutes: w?.zoneMinutes() ?? const [],
    // The SET those minutes were binned with, not a second resolution of the
    // anchors: `zoneSet` is pinned at session start precisely so a mid-session
    // anchor change cannot rebrand a split already on screen.
    zoneSource: w?.zoneSet?.source,
    zoneMaxHr: w?.zoneSet?.maxHr,
    // DENSE, not the hole-free variant: this feeds the summary's chart, whose
    // x axis is the session clock. `perMinuteHr()` is for statistics.
    hrCurve: _curveOverSession(w),
    distanceKm: app.liveDistanceKm,
    currentSpeedMps: app.routeTracker?.freshSpeedMps(
      DateTime.now().millisecondsSinceEpoch,
    ),
    gpsActive: app.routeTracking,
    gpsWaiting: app.routeWaitingForFix,
    bandConnected: app.isConnected,
    // Both were implemented at the state layer and read by nothing, so a
    // location denial showed as an absent map and no sentence at all.
    routeIssue: app.routeLocationIssue,
    onFixRoute: () {
      final issue = app.routeLocationIssue;
      if (issue == null) return;
      // A plain denial can be asked again; the rest can only be fixed in
      // Settings, and re-asking there would do nothing.
      if (issue == GpsPermissionStatus.denied) {
        app.retryRouteTracking();
      } else {
        GpsSource.openSettingsFor(issue);
      }
    },
  );
}

/// The per-minute curve, padded out to the session's OWN length.
///
/// `perMinuteHrDense` can only pad up to a minute that has a sample in it, and
/// the 1 Hz tick skips `accrueHr` entirely while the band is silent — so a
/// band that dropped at minute 30 of a 45-minute run hands back 30 slots. The
/// summary labels that chart's x axis `Start … 45:00` and spreads whatever it
/// is given across the whole width, so the reading taken at minute 15 was
/// painted under 22:30 and the fifteen-minute dropout was invisible. The tail
/// has to be there as nulls, which is what the painter breaks its line on.
List<double?> _curveOverSession(LiveWorkoutState? w) {
  if (w == null) return const [];
  final out = w.perMinuteHrDense();
  if (out.isEmpty) return out;
  final minutes = w.elapsed.inMinutes + 1;
  // Same sanity bound `_denseMinutes` uses: a clock that is not what we think
  // it is must not allocate a nonsense array.
  if (minutes <= out.length || minutes > 24 * 60) return out;
  return [...out, ...List<double?>.filled(minutes - out.length, null)];
}

/// Open a real session. Until this existed the live screens ran their own
/// clock over an app that had recorded nothing: no `sessions` row, no zone
/// tally, no calorie scoring, no GPS.
Future<bool> _startSession(AppState app, Activity a) async {
  if (app.activeWorkout != null) return false;
  final profile = await ProfileHistory.on(
    dayLabelOf(DateTime.now()),
    Profile.fromMap(app.user),
  );
  app.startWorkout(
    type: a.typeKey,
    calculationProfile: profile,
    met: a.met,
  );
  return app.activeWorkout != null;
}

/// `strength_set` rows for one log. `set_index` counts per exercise; `seq` is
/// the position in the whole session and is [LocalDb.saveStrengthSets]'s own
/// key, which is why re-sending the same log is idempotent.
List<Map<String, Object?>> _setRows(List<LoggedSet> sets) {
  final perExercise = <String, int>{};
  return [
    for (final s in sets)
      {
        'exercise_key': s.exerciseKey,
        'set_index': perExercise[s.exerciseKey] =
            (perExercise[s.exerciseKey] ?? 0) + 1,
        'reps': s.reps,
        'load_kg': s.loadKg,
        'rpe': s.rpe,
        'rest_sec': s.restSec,
        'at_ts': s.at.millisecondsSinceEpoch ~/ 1000,
      },
  ];
}

/// Bank the sets logged so far against the OPEN session. Called on every set,
/// because a typed set is the one thing in a session no sensor can reproduce
/// and it used to live in widget state until the user pressed stop.
Future<void> _bankSets(AppState app, List<LoggedSet> sets) async {
  final id = app.activeWorkout?.workoutId;
  if (id == null || sets.isEmpty) return;
  try {
    await LocalDb.saveStrengthSets(id, _setRows(sets));
  } catch (_) {
    // The draft still holds them, and finish writes the whole log again.
  }
}

/// Close it: finalize the session, persist the sets the user typed and the
/// privacy flag against its id, then hand back the result with the recorded
/// route folded in.
///
/// [id] is passed rather than read here so a retry still has one — see
/// [activityHost].
Future<ActivityResult> _finishSession(
  AppState app,
  ActivityResult draft,
  String? id,
) async {
  // Idempotent: on a retry the session is already stopped and this is a no-op.
  await app.stopWorkout();
  if (id == null) return draft;
  // The row exists from here on, so the summary can carry its id — which is
  // what TS-09's rating is written against. A draft that never reached the
  // database keeps a null id and is never offered the prompt.
  draft = draft.copyWith(sessionId: id);

  // The privacy toggle, finally landing somewhere. `putSession` is
  // INSERT-OR-REPLACE over the whole row and does not carry the flag, so this
  // is its own narrow UPDATE and it has to run AFTER stopWorkout, not before.
  if (draft.private) {
    await app.repo?.setWorkoutPrivate(id, true);
  }

  // Written on every set already; written again here because the last one
  // may have landed while the app was being torn down.
  if (draft.strength.sets.isNotEmpty) {
    await LocalDb.saveStrengthSets(id, _setRows(draft.strength.sets));
  }

  // The GPS tail is flushed by stopWorkout before it returns, so the route
  // read here is the whole route.
  runsChanged();
  try {
    final route = await app.repo?.getWorkoutRoute(id);
    if (route != null && route.hasPath) {
      return _withCalculation(await _withPhone(_withRoute(draft, route)), app);
    }
  } catch (_) {
    // A missing map is a missing map; the session itself is already banked.
  }
  return _withCalculation(await _withMotion(draft), app);
}

/// Previous and best per lift, from this user's own log. One indexed query
/// per exercise, fired in parallel.
Future<Map<String, SetHistory>> loadSetHistory() async {
  final history = <String, SetHistory>{};
  try {
    await Future.wait([
      for (final e in exerciseLibrary)
        LocalDb.recentSetsFor(e.key, limit: 40).then((rows) {
          if (rows.isEmpty) return;
          final sets = _logFrom(rows).sets;
          history[e.key] = SetHistory(
            previous: sets.first, // recentSetsFor orders newest first
            best: StrengthLog(sets).topSet,
          );
        }),
    ]);
  } catch (_) {
    // No history is the normal state on day one.
  }
  return history;
}

// ── the route seam ─────────────────────────────────────────────────────────

/// Fold a recorded route into a session: the line, the distance, the climb
/// and the per-kilometre splits. All of this already sat in `workout_route`
/// and `getWorkoutRoute`; none of it had ever reached the summary screen.
ActivityResult _withRoute(ActivityResult r, WorkoutRoute route) {
  final pts = route.points;
  final alt = [for (final p in pts) p.alt];
  final haveAlt = alt.every((a) => a != null) && alt.length > 1;
  double? gain, loss;
  if (haveAlt) {
    var up = 0.0, down = 0.0;
    for (var i = 1; i < alt.length; i++) {
      final d = alt[i]! - alt[i - 1]!;
      // A one-metre deadband: GPS altitude jitters by about that standing
      // still, and summing the jitter over an hour invents a mountain.
      if (d > 1) {
        up += d;
      } else if (d < -1) {
        down -= d;
      }
    }
    gain = up;
    loss = down;
  }
  final speeds = [for (final p in pts) p.speed];
  final haveSpeed = speeds.every((s) => s != null && s >= 0);
  return r.copyWith(
    route: _normalise(pts),
    geo: [for (final p in pts) (p.lat, p.lng)],
    routePace: haveSpeed ? _spread([for (final s in speeds) s!]) : null,
    distanceKm: route.distanceMeters / 1000,
    elevationM: haveAlt ? [for (final a in alt) a!] : const [],
    // Smoothed and deadbanded: raw GPS altitude wanders metres standing still.
    gainM: elevationGain(pts) ?? gain,
    lossM: loss,
    track: pts,
    movingSec: route.movingSec,
    mix: runMix(pts),
    splits: [
      for (final s in route.splitsKm)
        KmSplit(s.meters / 1000, s.durationSec, avgHr: s.avgHr?.round()),
    ],
  );
}

/// Latitude/longitude → the 0…1 box `RouteMap` draws in, origin top-left.
/// One shared span for both axes so the shape is the shape you ran, and a
/// cosine on longitude because a degree of it is not a degree of latitude.
List<Offset> _normalise(List<RoutePoint> pts) {
  if (pts.length < 2) return const [];
  var loLat = pts.first.lat, hiLat = loLat;
  var loLng = pts.first.lng, hiLng = loLng;
  for (final p in pts) {
    loLat = math.min(loLat, p.lat);
    hiLat = math.max(hiLat, p.lat);
    loLng = math.min(loLng, p.lng);
    hiLng = math.max(hiLng, p.lng);
  }
  final k = math.cos((loLat + hiLat) / 2 * math.pi / 180).abs().clamp(.01, 1.0);
  final w = (hiLng - loLng) * k, h = hiLat - loLat;
  final span = math.max(w, h);
  if (span <= 0) return const [];
  final dx = (1 - w / span) / 2, dy = (1 - h / span) / 2;
  return [
    for (final p in pts)
      Offset(dx + (p.lng - loLng) * k / span, dy + (hiLat - p.lat) / span),
  ];
}

/// Spread a series across 0…1 for a colour ramp. A flat series lands in the
/// middle rather than at an extreme it never reached.
List<double> _spread(List<double> v) {
  final lo = v.reduce(math.min), hi = v.reduce(math.max);
  if (hi - lo < 1e-9) return [for (var i = 0; i < v.length; i++) .5];
  return [for (final x in v) (x - lo) / (hi - lo)];
}

/// The stored `[{t, v}]` heart-rate curve as one slot per MINUTE of the
/// session, `null` where nothing was recorded.
///
/// The store emits a point only for minutes that had samples, so dropping `t`
/// and keeping the values closed every dropout up: a band that lost the link
/// for ten minutes drew a trace that ran straight across them, under an axis
/// labelled `Start … 47:20`. The x position of a sample is its index, so the
/// index has to be the minute.
/// [session] pads the TAIL out to the session's own length, for the same
/// reason [_curveOverSession] does on the live path: the store's last point is
/// the last minute that had samples, so a band that dropped at minute 30 of a
/// 45-minute session ends the line there and the chart stretches it across an
/// axis that says 45:00.
List<double?> _denseMinutes(Object? hr, [Duration? session]) {
  final pts = <(int, double)>[
    for (final e in (hr as List? ?? const []))
      if (e is Map && e['t'] is num && e['v'] is num)
        ((e['t'] as num).toInt(), (e['v'] as num).toDouble()),
  ];
  if (pts.isEmpty) return const [];
  final t0 = pts.first.$1;
  final n = (pts.last.$1 - t0) ~/ 60 + 1;
  // A session longer than a day, or timestamps that are not what we think they
  // are: fall back to the values rather than allocating a nonsense array.
  if (n < 1 || n > 24 * 60) return [for (final p in pts) p.$2];
  final want = session == null ? n : session.inMinutes + 1;
  final out = List<double?>.filled(
    want > n && want <= 24 * 60 ? want : n,
    null,
  );
  for (final p in pts) {
    final i = (p.$1 - t0) ~/ 60;
    if (i >= 0 && i < n) out[i] = p.$2;
  }
  return out;
}

/// Zone 5 of a persisted `zone_bands` list — the row carrying the set's own
/// `source` stamp and, as its `hi`, the ceiling the whole set is a percentage
/// of. Null for a session that banked no split, and then the footnote says the
/// estimate: the one claim that stands with no ceiling to name.
Map<String, dynamic>? _topBand(Object? bands) {
  if (bands is! List || bands.length != 5) return null;
  final top = bands.last;
  return top is Map ? top.cast<String, dynamic>() : null;
}

/// `zone_min` comes back from the repo as raw decoded JSON — guard the type
/// once here so a non-`List` value (or a non-numeric entry) never throws in
/// either read path.
List<double> _decodeZoneMinutes(Object? raw) => [
  for (final z in (raw is List ? raw : const []))
    if (z is num) z.toDouble(),
];

/// One past session, opened from history — built from what the stores hold
/// rather than from the six columns the list row carries.
Future<ActivityResult> _detailOf(AppState app, _PastWorkout w) async {
  var out = w.toResult();
  final repo = app.repo;
  if (repo == null) return out;
  try {
    final b = await repo.getWorkout(w.id);
    final band = _topBand(b['zone_bands']);
    // The bundle's own split — and whether it is the one that ends up on
    // screen. A short or absent `zone_min` falls back to the list row's split
    // rather than blanking the bars, but that is a different read from a
    // different moment, so it is one more case where the bands beside it
    // describe a different set.
    final decoded = _decodeZoneMinutes(b['zone_min']);
    final usedBundleSplit = decoded.length == 5;
    // …and whether that split was binned by the pass that produced the bands.
    final rebinned = usedBundleSplit && b['zone_min_rebinned'] != false;
    out = out.copyWith(
      hr: _denseMinutes(b['hr'], w.duration),
      // The session's own mean, computed over its heart-rate stream.
      avgHr: (b['avg_hr'] as num?)?.round(),
      maxHr: (b['max_hr'] as num?)?.round(),
      // How much of the window the trace behind those numbers actually covers.
      // Sessions past `rawRetentionDays` are served from the frozen trace, and
      // one frozen mid-dropout has to read as partial rather than draw a
      // confident line across the gap.
      traceCoveragePct: (b['trace_coverage_pct'] as num?)?.toInt(),
      // TS-04 — the anchors the bands on this card were binned against, read
      // off the bands themselves. `_zoneBands` stamps every row with the set's
      // `source`, and zone 5's `hi` IS the ceiling (both `zonesFromMaxHr` and
      // `reserveZones` put 100 % of the anchor there), so the footnote needs no
      // second read and cannot describe a different set from the bars.
      //
      // …EXCEPT WHEN IT WOULD. The bands are recomputed from the current
      // anchors on every open, while the minutes below can be a KEPT LIVE
      // split: a session the band only partly handed over keeps whichever side
      // saw more minutes, and that side was binned against whatever ceiling was
      // current when it was written. `zone_min_rebinned` is false exactly
      // there, and then this card has no ceiling it can name for these bars —
      // so it names none, and the footnote falls back to the estimate, the one
      // claim that stands without one. Understating the bars to match the
      // bands instead would put them at odds with the strain, calories and
      // duration beside them, which are the kept values too.
      // `band?['source'] as String?` / `as num?` would THROW on a
      // wrong-typed (not just missing) field, and the catch below is
      // best-effort for the WHOLE enrichment — one bad band field must not
      // also blank the hr/avgHr/zoneMinutes reads beside it. `is`-checks
      // degrade to null instead of throwing.
      zoneSource: rebinned && band?['source'] is String
          ? band!['source'] as String
          : null,
      zoneMaxHr: rebinned && band?['hi'] is num ? band!['hi'] as num : null,
      // …and the MINUTES from the same read, not from the list row. Opening a
      // session rescores it (`_rescoreSessionFromSubstrate`), so the row loaded
      // with the month list can be a split binned before that correction — and
      // pairing those bars with the provenance of the bands just recomputed
      // beside them is the exact mismatch this card is being fixed for.
      //
      // The list row is still the fallback for a split this read could not
      // produce: five zones or nothing, because a partial vector would draw
      // bars for the zones it has and silently drop the rest. When it fires,
      // `rebinned` is false above and no ceiling is named — which is what the
      // objection to falling back here was actually about.
      zoneMinutes: usedBundleSplit ? decoded : out.zoneMinutes,
    );
  } catch (_) {
    // Enrichment is best-effort; the scalars on the row still render.
  }
  // TS-09 — the session's own rating. `getWorkout` is the derived bundle and
  // does not carry the column, so this is one primary-key read of the row.
  try {
    final rpe = (await LocalDb.session(w.id))?['rpe'] as num?;
    if (rpe != null) out = out.copyWith(rpe: rpe.toDouble());
  } catch (_) {
    // An unrated session and an unreadable row both render as unrated.
  }
  try {
    final sets = await LocalDb.strengthSets(w.id);
    if (sets.isNotEmpty) out = out.copyWith(strength: _logFrom(sets));
  } catch (_) {
    /* no sets is a normal session */
  }
  try {
    final route = await repo.getWorkoutRoute(w.id);
    if (route != null && route.hasPath) {
      out = await _withPhone(_withRoute(out, route));
    } else {
      out = await _withMotion(out);
    }
  } catch (_) {
    /* no route is a normal session */
  }
  return _withCalculation(out, app);
}

Future<ActivityResult> _withCalculation(ActivityResult r, AppState app) async {
  final id = r.sessionId, repo = app.repo;
  if (id == null || repo == null) return r;
  final row = await LocalDb.session(id);
  final end = (row?['end_ts'] as num?)?.toInt();
  if (end == null) return r;
  final m = await WorkoutMeasurements.read(
    repo,
    id,
    r.start,
    DateTime.fromMillisecondsSinceEpoch(end * 1000),
    Profile.fromMap(app.user),
    bandSteps: r.steps,
  );
  final c = m.clock;
  var out = r.copyWith(
    calculationProfile: m.profile,
    duration: c.activeDuration(),
    phoneSteps: m.steps,
    hr: c.results['hr'] is List
        ? [for (final v in c.results['hr']) (v as num?)?.toDouble()]
        : null,
    zoneMinutes: c.results['zones'] is List
        ? [for (final v in c.results['zones']) (v as num).toDouble()]
        : null,
  );
  if (m.points.length > 1) {
    final original = await repo.getWorkoutRoute(id);
    final hr = [
      for (final sample in original?.hr ?? const <HrSample>[])
        if (c.includes(DateTime.fromMillisecondsSinceEpoch(sample.tsMs)))
          sample,
    ];
    final route = WorkoutRoute(
      sessionId: id,
      points: m.points,
      hr: hr,
      distanceMeters: totalDistanceMeters(m.points),
      movingSec: movingSeconds(m.points),
      splitsKm: computeSplits(m.points, hr, unitMeters: kMetersPerKm),
      splitsMi: computeSplits(m.points, hr, unitMeters: kMetersPerMile),
    );
    out = _withRoute(out, route);
  }
  return out;
}

/// A run or walk with no GPS: distance, splits and cadence from the phone's
/// motion data, when the phone was carried. Anything else comes back as it
/// went in.
Future<ActivityResult> _withMotion(ActivityResult r) async {
  final id = r.sessionId;
  final type = r.activity.typeKey;
  if (id == null || !(isRunType(type) || isWalkType(type))) return r;
  try {
    final row = await LocalDb.session(id);
    final end = (row?['end_ts'] as num?)?.toInt();
    if (end == null) return r;
    final w = await sessionMotionWindow(
      id,
      r.start,
      DateTime.fromMillisecondsSinceEpoch(end * 1000),
    );
    final m = w?.totalMeters;
    if (w == null) return r;
    if (m == null || m < 100) {
      return r.copyWith(
        phoneSteps: w.totalSteps,
        cadence: w.cadence,
        cadenceSeries: _perMinute(w),
      );
    }
    final hr = r.hr;
    return r.copyWith(
      distanceKm: m / 1000,
      splits: [
        for (final s in w.splits(
          hrAtMinute: (i) => i >= 0 && i < hr.length ? hr[i] : null,
        ))
          KmSplit(s.km, s.sec, avgHr: s.hr),
      ],
      movingSec: (w.activeMinutes * 60).round(),
      mix: motionMix(
        steps: w.steps,
        meters: w.meters,
        chunkSec: w.chunkSec,
        seconds: w.seconds,
      ),
      motionDistance: true,
      cadence: w.cadence,
      phoneSteps: w.totalSteps,
      cadenceSeries: _perMinute(w),
    );
  } catch (_) {
    return r;
  }
}

/// A GPS run or walk: the phone's own steps and cadence for its window, when
/// the phone was counting (phone first; the wrist reads a run low).
Future<ActivityResult> _withPhone(ActivityResult r) async {
  final id = r.sessionId;
  final type = r.activity.typeKey;
  if (id == null || !(isRunType(type) || isWalkType(type))) return r;
  try {
    final row = await LocalDb.session(id);
    final end = (row?['end_ts'] as num?)?.toInt();
    if (end == null) return r;
    final w = await sessionMotionWindow(
      id,
      r.start,
      DateTime.fromMillisecondsSinceEpoch(end * 1000),
    );
    if (w == null) return r;
    return r.copyWith(
      phoneSteps: w.totalSteps,
      cadence: w.cadence,
      cadenceSeries: _perMinute(w),
    );
  } catch (_) {
    return r;
  }
}

/// Steps a minute from the phone's chunks, one slot per minute from the
/// window start; null where nothing was counted.
List<double?> _perMinute(MotionWindow w) {
  final perChunk = w.chunkSec / 60;
  if (perChunk <= 0) return const [];
  return [
    for (var i = 0; i < w.steps.length; i++)
      w.steps[i] <= 0 || w.secondsAt(i) <= 0
          ? null
          : w.steps[i] * 60 / w.secondsAt(i),
  ];
}

/// `strength_set` rows → the log the summary renders. `load_kg` stays null
/// when it was null: a bodyweight set is not a zero-kilo set.
StrengthLog _logFrom(List<Map<String, Object?>> rows) => StrengthLog([
  for (final r in rows)
    LoggedSet(
      (r['exercise_key'] as String?) ?? '',
      (r['reps'] as num?)?.toInt() ?? 0,
      loadKg: (r['load_kg'] as num?)?.toDouble(),
      rpe: (r['rpe'] as num?)?.toInt(),
      restSec: (r['rest_sec'] as num?)?.toInt(),
      at: DateTime.fromMillisecondsSinceEpoch(
        ((r['at_ts'] as num?)?.toInt() ?? 0) * 1000,
      ),
    ),
]);

// ── the data this screen reads ─────────────────────────────────────────────

class _PastWorkout {
  final String id;
  final Activity activity;
  final DateTime start;
  final Duration duration;
  final double? strain;
  final int? calories, avgHr, maxHr;
  final double? acsmCalories;

  /// `sessions.hrr_bpm` — the bpm drop in the 60 s after the session. Carried
  /// from the list row because that is where the repository already serves it.
  final int? hrr60;

  /// `sessions.steps` — banked at finish from the live 100 Hz pedometer and
  /// never recomputed. It is a COLUMN, so unlike the trace it does not depend
  /// on the 1 Hz substrate and does not go blank when that is pruned; a session
  /// that never measured one reads NULL forever, which is the truth for it.
  final int? steps;
  final List<double> zoneMinutes;

  /// The user's "keep this one off the shared surfaces" flag, read back from
  /// `sessions.private`.
  final bool private;

  /// The app or watch that recorded this, when it was not us — "Apple Watch",
  /// "Strava". Null for a session this band measured, and that null is the ONE
  /// test everything below reads: what a row may be counted in, whether it
  /// opens, and what is printed under its name all come off this field.
  final String? importedFrom;

  /// The health store's own name for the activity, already prettified.
  ///
  /// Carried because `activityByName` only resolves the types this app's own
  /// catalogue has, and printing "Workout" over a HealthKit `SURFING` throws
  /// away the one thing the store did tell us.
  final String? importedTitle;

  /// Metres, from the recording app. Only imported rows carry it — a band
  /// session's distance is read on open with its route.
  final double? distanceM;

  const _PastWorkout(
    this.id,
    this.activity,
    this.start,
    this.duration, {
    this.strain,
    this.calories,
    this.acsmCalories,
    this.avgHr,
    this.maxHr,
    this.hrr60,
    this.steps,
    this.zoneMinutes = const [],
    this.private = false,
    this.importedFrom,
    this.importedTitle,
    this.distanceM,
  });

  List<double> get zoneFractions {
    final total = zoneMinutes.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const [0, 0, 0, 0, 0];
    return [for (final z in zoneMinutes) z / total];
  }

  String when(AppLocalizations? loc) {
    final days = calendarDaysBetween(start, DateTime.now());
    final names = [
      loc?.workoutWeekdayAbbrMon ?? 'Mon',
      loc?.workoutWeekdayAbbrTue ?? 'Tue',
      loc?.workoutWeekdayAbbrWed ?? 'Wed',
      loc?.workoutWeekdayAbbrThu ?? 'Thu',
      loc?.workoutWeekdayAbbrFri ?? 'Fri',
      loc?.workoutWeekdayAbbrSat ?? 'Sat',
      loc?.workoutWeekdayAbbrSun ?? 'Sun',
    ];
    final t =
        '${start.hour.toString().padLeft(2, '0')}:'
        '${start.minute.toString().padLeft(2, '0')}';
    if (days == 0) return loc?.workoutWhenToday(t) ?? 'Today, $t';
    if (days == 1) return loc?.workoutWhenYesterday(t) ?? 'Yesterday, $t';
    if (days < 7) return '${names[start.weekday - 1]}, $t';
    return '${start.day}/${start.month}, $t';
  }

  ActivityResult toResult() => ActivityResult(
    activity,
    start: start,
    duration: duration,
    private: private,
    // TS-09 — the id travels so the summary can write a rating against
    // it; the rating itself is read on open by `_detailOf`, not carried on
    // this row (the list does not show it).
    sessionId: id,
    strain: strain,
    calories: calories,
    avgHr: avgHr,
    maxHr: maxHr,
    hrr60: hrr60,
    steps: steps,
    zoneMinutes: zoneMinutes,
  );
}

class _WorkoutData {
  final double? weightKg;

  /// Daily strain, one slot per calendar day for the seven ending [weekEnd].
  /// Null is a day that derived nothing — drawn as a hole.
  final List<double?> strain7;

  /// The day slot 6 belongs to.
  final DateTime? weekEnd;
  final List<_PastWorkout> workouts;

  /// Every recorded run, oldest first, for the running trends.
  final List<RunSummary> runs;
  final Set<int> weekDays; // 0 = Monday
  final int weekCount;

  /// How many of [weekCount] came from the phone's health store. Carried so
  /// the gap between "This week" and "Weekly load" can be explained where the
  /// two sit side by side, rather than left to look like a bug.
  final int weekImported;
  final double? weekLoad;
  final int? workoutsTracked;

  /// The run-or-walk streak, or null when it could not be read.
  final MoveStreak? streak;

  /// The activities this user actually started, most recent first, deduped.
  final List<Activity> recent;

  /// Previous and best set per exercise, from this user's own log.
  final Map<String, SetHistory> setHistory;

  /// The detector's active bouts — every "did you work out?" that has neither
  /// been logged nor dismissed. Empty when auto-detection is switched off.
  ///
  /// These rows have been written on every derive since the detector shipped
  /// and read by nothing, so a detected effort was invisible unless a
  /// notification happened to catch you — and until the emit moved off the
  /// dropped `recovery` channel, no notification ever did.
  final List<Suggestion> suggestions;

  /// When the phone's health store last handed us a workout, or null for
  /// never. It is the whole difference between an Import button and a Refresh
  /// one — see health_import_state.dart for why the store cannot be asked.
  final DateTime? importedLast;

  const _WorkoutData({
    this.weightKg,
    this.strain7 = const [],
    this.weekEnd,
    this.workouts = const [],
    this.runs = const [],
    this.weekDays = const {},
    this.weekCount = 0,
    this.weekImported = 0,
    this.weekLoad,
    this.workoutsTracked,
    this.recent = const [],
    this.streak,
    this.setHistory = const {},
    this.suggestions = const [],
    this.importedLast,
  });

  const _WorkoutData.empty() : this();
}

/// Band sessions and imported workouts for [range] ('month' on Train, 'all'
/// on the history page), newest first.
Future<List<_PastWorkout>> _pastWorkouts(
  AppState app,
  LocalRepository repo,
  String range,
) async {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day);
  final past = <_PastWorkout>[];
  try {
    final rows = (await repo.getWorkouts(range: range))['workouts'];
    if (rows is List) {
      for (final r in rows) {
        if (r is! Map) continue;
        final ts = (r['start_ts'] as num?)?.toInt();
        if (ts == null) continue;
        final a =
            activityByName(r['type'] as String?) ??
            const Activity(
              'Workout',
              LucideIcons.activity,
              C.purple,
              Track.duration,
              5.0,
            );
        final id = (r['id'] as String?) ?? '';
        final start = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        final endTs = (r['end_ts'] as num?)?.toInt();
        WorkoutMeasurements? measured;
        if ((isRunType(a.typeKey) || isWalkType(a.typeKey)) &&
            endTs != null &&
            endTs > ts &&
            r['status'] != 'live' &&
            r['end_ts_fabricated'] != true &&
            r['end_ts_fabricated'] != 1) {
          measured = await WorkoutMeasurements.read(
            repo,
            id,
            start,
            DateTime.fromMillisecondsSinceEpoch(endTs * 1000),
            Profile.fromMap(app.user),
            bandSteps: (r['steps'] as num?)?.toInt(),
          );
        }
        past.add(
          _PastWorkout(
            id,
            a,
            DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            // duration_min is minutes; Motion.tick × 60 × n keeps the one
            // Duration literal in theme.dart.
            // Active time (start to stop minus pauses) wherever a clock
            // exists, the same time the calories below are priced on.
            measured != null
                ? Motion.tick * measured.clock.activeSeconds()
                : endTs != null && endTs > ts
                ? Motion.tick *
                      WorkoutClock.read(
                        id,
                        start,
                        end: DateTime.fromMillisecondsSinceEpoch(endTs * 1000),
                      ).activeSeconds()
                : Motion.tick * 60 * ((r['duration_min'] as num?)?.toInt() ?? 0),
            strain: (r['strain'] as num?)?.toDouble(),
            // Every band session shows active (net) energy by a conservative
            // method: distance/steps for runs and walks, MET only for lifting,
            // otherwise the lower of net heart-rate and net activity energy
            // (sessionActiveKcal). Recomputed here so older sessions read the
            // same way as the session screen and the maintenance Lifting line.
            calories: (isRunType(a.typeKey) || isWalkType(a.typeKey))
                ? measured?.method1(a.typeKey)?.round()
                : sessionActiveKcal(
                    p: await sessionProfile(
                      id,
                      start,
                      Profile.fromMap(app.user),
                      end: endTs == null
                          ? null
                          : DateTime.fromMillisecondsSinceEpoch(endTs * 1000),
                    ),
                    type: a.typeKey,
                    minutes: endTs != null && endTs > ts
                        ? WorkoutClock.read(
                                id,
                                start,
                                end: DateTime.fromMillisecondsSinceEpoch(
                                  endTs * 1000,
                                ),
                              ).activeSeconds() /
                              60
                        : ((r['duration_min'] as num?)?.toDouble() ?? 0),
                    meanHr: (r['avg_hr'] as num?)?.toDouble(),
                    catalogueMet: a.met,
                  )?.round(),
            acsmCalories: measured?.acsm(a.typeKey),
            // The session's mean over its own HR stream, computed by the repo
            // — not the last sample anybody happened to see.
            avgHr: (r['avg_hr'] as num?)?.round(),
            maxHr: (r['max_hr'] as num?)?.toInt(),
            hrr60: (r['hrr60'] as num?)?.round(),
            steps: measured?.steps ?? (r['steps'] as num?)?.toInt(),
            zoneMinutes: _decodeZoneMinutes(r['zone_min']),
            private: r['private'] == true,
          ),
        );
      }
    }
  } catch (_) {
    // A failed session read must not become "no sessions recorded".
    rethrow;
  }
  // Workouts another app recorded, on the SAME window the band's own list
  // uses. The store is read 90 days back (30 on Android) because that is the
  // most history worth carrying, but showing three months of imports beside
  // one month of sessions would read as a band that stopped measuring.
  try {
    final since = range == 'all'
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : end.subtract(Motion.tick * 86400 * 31);
    for (final r in await LocalDb.importedWorkouts(limit: 200)) {
      final ts = (r['start_ts'] as num?)?.toInt();
      final endTs = (r['end_ts'] as num?)?.toInt();
      final src = (r['source'] as String?)?.trim();
      // `source` is NOT NULL in the table for exactly this reason: a workout
      // shown without the app that recorded it is a workout this app is
      // implicitly claiming. No source, no row.
      if (ts == null || endTs == null || endTs <= ts) continue;
      if (src == null || src.isEmpty) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      if (at.isBefore(since)) continue;
      final title = importedWorkoutTitle(r['kind']);
      past.add(
        _PastWorkout(
          (r['uuid'] as String?) ?? '',
          // The icon and colour only, when the catalogue happens to know the
          // type. The NAME always comes from the store — `activityByName`
          // resolves the ~40 types this app can start, and the fallback would
          // print "Workout" over a surf.
          activityByName(title) ??
              const Activity(
                'Workout',
                LucideIcons.activity,
                C.purple,
                Track.duration,
                5.0,
              ),
          at,
          Motion.tick * (endTs - ts),
          // No strain, ever. It is not omitted pending a better idea — there
          // is no heart-rate series behind this row to score one from, so
          // every load surface reads null and leaves it out on its own.
          calories: (r['energy_kcal'] as num?)?.round(),
          steps: (r['steps'] as num?)?.toInt(),
          importedFrom: src,
          importedTitle: title,
          distanceM: (r['distance_m'] as num?)?.toDouble(),
        ),
      );
    }
  } catch (_) {
    // Nothing imported is the normal state, and an unreadable table must not
    // take the band's own history down with it.
  }
  past.sort((a, b) => b.start.compareTo(a.start));
  return past;
}

/// One pass over the repo. Every call is defensive: this screen must render on
/// a device that has never synced, and a throw in any one of them must not
/// take the whole tab down.
Future<_WorkoutData> _loadWorkoutData(AppState app) async {
  final repo = app.repo;
  if (repo == null) throw StateError('Training repository unavailable');

  double? weight;
  try {
    weight = (await repo.getProfile())['weight_kg'] as double?;
  } catch (_) {
    weight = null;
  }

  // One slot per calendar day for the last seven, ending today. A day that
  // derived nothing is a hole, not a shifted neighbour: taking the last
  // seven STORED points stamped `M T W T F S S` on whatever was there, and
  // `metric_series` only gains a row on a day that derives — so after a sync
  // gap the letters named days the data did not come from, and the bar drawn
  // as "today" could be a week old.
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day);
  var strain7 = List<double?>.filled(7, null);
  try {
    strain7 = lastSevenDays((await repo.getChart('strain'))['points'], end);
  } catch (_) {
    strain7 = List<double?>.filled(7, null);
  }

  final past = await _pastWorkouts(app, repo, 'month');

  past.sort((a, b) => b.start.compareTo(a.start));

  final weekStart = end.subtract(Motion.tick * 86400 * (end.weekday - 1));
  final thisWeek = [
    for (final w in past)
      if (w.start.isAfter(weekStart)) w,
  ];

  int? tracked;
  try {
    tracked = ((await repo.getRecords())['workouts_tracked'] as num?)?.toInt();
  } catch (_) {
    tracked = null;
  }

  // Imported sessions fall out here on their own: they carry no strain,
  // because there is no heart-rate series behind them to score one from.
  // Nothing filters them — there is nothing to add.
  final weekLoad = thisWeek
      .where((w) => w.strain != null)
      .fold<double?>(null, (a, w) => (a ?? 0) + w.strain!);

  // Real recency, deduped, newest first — six tiles like the constant it
  // replaces, so the picker's row is the same shape either way.
  //
  // Band sessions only. These tiles START a session, and most imported types
  // land on the generic fallback activity — a row of "Workout" tiles that
  // begin a five-MET nothing is worse than the six real ones.
  final recent = <Activity>[];
  for (final w in past) {
    if (w.importedFrom != null) continue;
    if (!recent.any((x) => x.name == w.activity.name)) {
      recent.add(w.activity);
    }
    if (recent.length == 6) break;
  }

  // The live screen has to have previous/best in hand before the first set;
  // "First time on this lift" was showing forever because nothing loaded
  // them.
  final history = await loadSetHistory();

  return _WorkoutData(
    weightKg: weight,
    strain7: strain7,
    weekEnd: end,
    runs: await () async {
      try {
        return await loadRuns(repo);
      } catch (_) {
        return const <RunSummary>[];
      }
    }(),
    workouts: past,
    // Imported days light a dot too. This strip says "you trained", not
    // "this band measured you", and a Sunday run left dark because the watch
    // recorded it instead of the band is wrong in a way the user can see.
    weekDays: {for (final w in thisWeek) w.start.weekday - 1},
    weekCount: thisWeek.length,
    weekImported: thisWeek.where((w) => w.importedFrom != null).length,
    weekLoad: weekLoad,
    workoutsTracked: tracked,
    recent: recent,
    streak: await loadMoveStreak(),
    setHistory: history,
    suggestions: await activeSuggestions(),
    importedLast: await lastImportAt(HealthImport.workouts),
  );
}


/// Confirm, then delete [w]. Returns whether it was deleted. An imported
/// row's health-store uuid goes onto the tombstone list first, or the next
/// import would bring the removed row straight back. A copy in Apple Health /
/// Health Connect itself is out of reach by design and the confirm says so.
Future<bool> _confirmDeleteWorkout(BuildContext c, _PastWorkout w) async {
  final loc = AppLocalizations.of(c);
  final ok = await confirmRemove(
    c,
    title:
        loc?.workoutConfirmDeleteTitle(w.activity.name.toLowerCase()) ??
        'Delete this ${w.activity.name.toLowerCase()}?',
    body: w.importedFrom == null
        ? (loc?.workoutDeleteBodyOwn(storeName) ??
              'It disappears from $kAppName. A copy in $storeName, if there is '
                  'one, stays where it is.')
        : (loc?.workoutDeleteBodyImported(storeName) ??
              'It disappears from $kAppName and will not be re-imported. '
                  'The original in $storeName stays.'),
  );
  if (!ok) return false;
  forgetRun(w.id);
  if (w.importedFrom != null && w.id.isNotEmpty) {
    await rememberDeletedUuid(w.id);
    await LocalDb.deleteImportedWorkout(w.id);
  } else {
    await LocalDb.deleteSession(w.id);
  }
  return true;
}

String _rowKey(_PastWorkout w) =>
    '${w.importedFrom ?? ''}:${w.id}:${w.start.millisecondsSinceEpoch}';

/// A session row as Train and the history page show it: collapsed to one
/// line, opened in place, deleted with a swipe either way (confirmed), and
/// retimed from inside the open card.
Widget historyRow(
  BuildContext c,
  _PastWorkout w, {
  double? weightKg,
  required bool expanded,
  required VoidCallback onToggle,
  required VoidCallback onChanged,
}) {
  final loc = AppLocalizations.of(c);
  final row = _HistoryRow(
    w,
    weightKg: weightKg,
    expanded: expanded,
    onToggle: onToggle,
    onDelete: w.id.isEmpty
        ? null
        : () async {
            await _confirmDeleteWorkout(c, w);
            onChanged();
          },
    onRetime: w.importedFrom == null && w.id.isNotEmpty
        ? () async {
            await Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (_) => LogWorkout(
                  sessionId: w.id,
                  start: w.start,
                  end: w.start.add(w.duration),
                  activity: w.activity,
                  title: loc?.workoutFixTimes ?? 'Fix the times',
                ),
              ),
            );
            onChanged();
          }
        : null,
  );
  if (w.id.isEmpty) return KeyedSubtree(key: ValueKey(_rowKey(w)), child: row);
  return SwipeDelete(
    key: ValueKey(_rowKey(w)),
    onDelete: () async {
      await _confirmDeleteWorkout(c, w);
      onChanged();
    },
    child: row,
  );
}

/// Every session, grouped by calendar month: this month open, older months
/// folded to one line each ("September · 14 sessions · 9 h 20 min").
class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key, this.weightKg});
  final double? weightKg;

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen>
    with RevisionReload {
  List<_PastWorkout>? _all;
  bool _failed = false;
  final _openMonths = <String>{};
  String? _openId;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _openMonths.add('${n.year}-${n.month}');
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  @override
  void reload() => _read();

  Future<void> _read() async {
    final app = context.read<AppState>();
    final repo = app.repo;
    if (repo == null) return;
    final t = beginRead(#workoutHistory);
    try {
      final all = await _pastWorkouts(app, repo, 'all');
      if (stillNewest(#workoutHistory, t)) {
        setState(() => (_all = all, _failed = false));
      }
    } catch (_) {
      if (stillNewest(#workoutHistory, t)) setState(() => _failed = true);
    }
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final all = _all;
    final byMonth = <String, List<_PastWorkout>>{};
    for (final w in all ?? const <_PastWorkout>[]) {
      (byMonth['${w.start.year}-${w.start.month}'] ??= []).add(w);
    }
    return detailScaffold(c, 'All workouts', [
      if (_failed)
        StatusCard(
          'Workouts could not load',
          'Your saved sessions are intact.',
          fix: 'Retry',
          onFix: _read,
        )
      else if (all == null)
        const Center(child: CircularProgressIndicator())
      else if (all.isEmpty)
        const StatusCard(
          'No sessions recorded yet',
          'Start one from Train.',
          icon: LucideIcons.dumbbell,
        )
      else
        for (final e in byMonth.entries) ...[
          const SizedBox(height: S.x3),
          Pressable(
            onTap: () => setState(
              () => _openMonths.contains(e.key)
                  ? _openMonths.remove(e.key)
                  : _openMonths.add(e.key),
            ),
            semanticLabel: _monthLine(e.key, e.value),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _monthName(e.key),
                        style: F.body.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _monthLine(e.key, e.value),
                        style: F.over.copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _openMonths.contains(e.key)
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 18,
                  color: p.ink3,
                ),
              ],
            ),
          ),
          if (_openMonths.contains(e.key))
            for (final w in e.value) ...[
              const SizedBox(height: S.x2),
              historyRow(
                c,
                w,
                weightKg: widget.weightKg,
                expanded: _openId == _rowKey(w),
                onToggle: () => setState(
                  () => _openId = _openId == _rowKey(w) ? null : _rowKey(w),
                ),
                onChanged: _read,
              ),
            ],
        ],
      const SizedBox(height: S.x5),
    ]);
  }

  String _monthName(String key) {
    final parts = key.split('-');
    final y = int.parse(parts[0]), m = int.parse(parts[1]);
    return y == DateTime.now().year ? _months[m - 1] : '${_months[m - 1]} $y';
  }

  /// "14 sessions · 9 h 20 min · 4 runs".
  String _monthLine(String key, List<_PastWorkout> ws) {
    final mins = ws.fold<int>(0, (a, w) => a + w.duration.inMinutes);
    final runs = ws.where((w) => isRunType(w.activity.typeKey)).length;
    final walks = ws.where((w) => isWalkType(w.activity.typeKey)).length;
    return [
      '${ws.length} session${ws.length == 1 ? '' : 's'}',
      mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min' : '$mins min',
      if (runs > 0) '$runs run${runs == 1 ? '' : 's'}',
      if (walks > 0) '$walks walk${walks == 1 ? '' : 's'}',
    ].join(' · ');
  }
}
