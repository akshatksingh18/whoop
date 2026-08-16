// WORKOUT — the interaction domain. Not "here are your numbers", but "what do
// you want to do, and what did you do".
//
// Three tabs. There is deliberately no Programs tab: a training programme is a
// data model this app does not have (UI_WIRING §2c), and a tab of four fake
// plans with fake progress bars is the exact thing the absence contract
// exists to stop.
//
// Everything numeric here comes from `AppState.repo`. Where the repo has
// nothing — and for training load it very often has nothing, because CTL/ATL
// need fourteen days — the card is a StatusCard that says which, why and what
// fixes it.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../gps/gps_source.dart';
import '../../gps/route_models.dart';
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart';
import '../activity/live.dart';
import '../activity/picker.dart';
import '../activity/setup.dart';
import '../activity/summary.dart';
import '../charts.dart';
import '../grammar.dart';
import '../profile/profile.dart';
import '../theme.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int tab = 0;
  static const _tabs = ['For you', 'Activities', 'History'];

  Future<_WorkoutData>? _load;

  /// The revision this screen's data was loaded at.
  ///
  /// `_load ??=` alone meant the screen read the database exactly once, for the
  /// life of the widget — so a session you had just finished was absent from
  /// History, "This week", "Tracked" and the weekly load until the app was
  /// restarted. `AppState.insightsRevision` already ticks after every derive
  /// and now after a session is durably written, so re-reading when it moves
  /// covers the manual finish, the gesture path and the Live Activity alike.
  int _loadedAt = -1;

  /// Held so the listener can be removed in [dispose], where `context.read`
  /// is not safe, and so a second `didChangeDependencies` cannot subscribe
  /// twice — `ValueNotifier.addListener` stacks duplicates.
  ValueNotifier<int>? _rev;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (!identical(_rev, app.insightsRevision)) {
      _rev?.removeListener(_onRevision);
      _rev = app.insightsRevision..addListener(_onRevision);
    }
    if (_load == null) {
      _loadedAt = app.insightsRevision.value;
      _load = _loadWorkoutData(app);
    }
  }

  void _onRevision() {
    if (!mounted) return;
    final app = context.read<AppState>();
    if (app.insightsRevision.value == _loadedAt) return;
    setState(() {
      _loadedAt = app.insightsRevision.value;
      _load = _loadWorkoutData(app);
    });
  }

  @override
  void dispose() {
    _rev?.removeListener(_onRevision);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    return FutureBuilder<_WorkoutData>(
      future: _load,
      builder: (c, snap) {
        final d = snap.data ?? const _WorkoutData.empty();
        return ListView(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x16),
          children: [
            const ScreenTitle('Workout'),
            SubTabs(_tabs, tab, (i) => setState(() => tab = i),
                color: C.domMove),
            const SizedBox(height: S.x5),
            ...switch (tab) {
              0 => _forYou(c, d),
              1 => _activities(c, d),
              _ => _history(c, d),
            },
          ],
        );
      },
    );
  }

  void _openPicker(BuildContext c, _WorkoutData d) =>
      Navigator.of(c).push(MaterialPageRoute(
          builder: (_) => ActivityPicker(
              weightKg: d.weightKg, host: _host(d), recent: d.recent)));

  ActivityHost _host(_WorkoutData d) =>
      activityHost(context.read<AppState>(), history: d.setHistory);

  // ─────────────── FOR YOU ───────────────
  List<Widget> _forYou(BuildContext c, _WorkoutData d) {
    final p = P.of(c);
    return [
      Pressable(
        onTap: () => _openPicker(c, d),
        semanticLabel: 'Start a workout',
        child: Container(
          height: 190,
          decoration: BoxDecoration(
            borderRadius: R.rLg,
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(C.n900, C.purple, .35)!,
                  p.fill(C.purple),
                ]),
            boxShadow: p.el(3),
          ),
          child: Stack(children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(LucideIcons.dumbbell,
                  size: 180, color: C.white.withValues(alpha: .10)),
            ),
            Padding(
              padding: const EdgeInsets.all(S.x5),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('START A SESSION',
                        style: F.over
                            .copyWith(color: C.white.withValues(alpha: .75))),
                    const Spacer(),
                    Text('${allActivities.length} activities',
                        style: F.t2.copyWith(color: C.white)),
                    const SizedBox(height: S.x1),
                    Text('Each one with a published energy cost',
                        style: F.cap
                            .copyWith(color: C.white.withValues(alpha: .8))),
                    const SizedBox(height: S.x4),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                          color: C.white, shape: BoxShape.circle),
                      child: Icon(LucideIcons.play,
                          size: 22, color: p.fill(C.purple)),
                    ),
                  ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: S.x3),
      Row(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: S.x3),
          Expanded(
            child: _QuickTile(
              quickStart[i],
              () => Navigator.of(c).push(MaterialPageRoute(
                  builder: (_) => ActivitySetup(quickStart[i],
                      weightKg: d.weightKg, host: _host(d)))),
            ),
          ),
        ],
      ]),
      Section(
        'This week',
        Surface(
          child: Row(
            children: List.generate(7, (i) {
              const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
              final today = DateTime.now().weekday - 1;
              final done = d.weekDays.contains(i);
              return Expanded(
                child: Column(children: [
                  Text(days[i], style: F.over.copyWith(color: p.ink3)),
                  const SizedBox(height: S.x2),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? p.wash(C.green, strength: 1.5)
                            : (i == today ? p.fill(C.purple) : p.card2)),
                    child: Icon(
                        done
                            ? LucideIcons.check
                            : (i == today ? LucideIcons.play : null),
                        size: 14,
                        color: done ? p.on(C.green) : p.inkOnFill),
                  ),
                ]),
              );
            }),
          ),
        ),
      ),
      Section('Training load', _loadCard(c, p, d)),
    ];
  }

  Widget _loadCard(BuildContext c, P p, _WorkoutData d) {
    if (d.load == null) {
      return StatusCard(
        'No training load yet',
        d.loadNote ??
            'Fitness and fatigue are 42-day and 7-day averages. They need '
                'about two weeks of sessions.',
        icon: LucideIcons.trendingUp,
      );
    }
    final l = d.load!;
    return Surface(
      child: Column(children: [
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(l.ctl.round().toString(),
                  style: F.n34.copyWith(color: p.ink)),
              const SizedBox(width: S.x2),
              Text('fitness', style: F.cap.copyWith(color: p.ink3)),
              const Spacer(),
              if (l.tsb != null)
                Pill(_form(l.tsb!), l.tsb! >= 0 ? C.green : C.orange),
            ]),
        if (d.trimp7.any((v) => v != null)) ...[
          const SizedBox(height: S.x4),
          Builder(builder: (_) {
            final end = d.trimpEnd ?? DateTime.now();
            final axis = AxisSpec.of([for (final v in d.trimp7) ?v], floor: 0);
            final days = d.trimp7.where((v) => v != null).length;
            return ChartFrame(
              title: 'DAILY LOAD',
              unit: 'TRIMP',
              height: 88,
              yAxis: axis,
              // Seven slots, seven real dates. A day with nothing keeps its
              // place and its letter, and draws as the gap it is.
              xLabels: [
                for (var i = 6; i >= 0; i--)
                  _weekdayLetter(end.subtract(Motion.tick * 86400 * i)),
              ],
              footnote: 'Banister training impulse — minutes weighted by '
                  'heart-rate reserve. '
                  '${days == 7 ? 'Last seven days.' : '$days of the last '
                      'seven days produced a figure.'}',
              series: d.trimp7,
              child: CustomPaint(
                  size: Size.infinite,
                  // Today is the last slot, always — not "the newest value".
                  painter: Bars(d.trimp7, p.on(C.purple), p.track,
                      highlight: d.trimp7.last == null ? -1 : 6,
                      axis: axis,
                      t: animate(context, 1))),
            );
          }),
        ],
        const SizedBox(height: S.x4),
        // Absent is absent. `?? 0` used to render "Fatigue 0" — a rest week —
        // for a pipeline that had simply not produced the number.
        InlineMetrics([
          ('Fitness', l.ctl.round().toString(), C.blue),
          ('Fatigue', l.atl?.round().toString() ?? 'Not yet', C.orange),
          (
            'Form',
            l.tsb == null
                ? 'Not yet'
                : '${l.tsb! >= 0 ? '+' : '−'}${l.tsb!.abs().round()}',
            C.purple
          ),
        ]),
      ]),
    );
  }

  /// Coggan's form bands, named rather than numbered.
  String _form(double tsb) => tsb > 5
      ? 'Fresh'
      : tsb >= -10
          ? 'Steady'
          : tsb >= -30
              ? 'Building'
              : 'Overreaching';

  // ─────────────── ACTIVITIES ───────────────
  List<Widget> _activities(BuildContext c, _WorkoutData d) {
    final p = P.of(c);
    return [
      Pressable(
        onTap: () => _openPicker(c, d),
        semanticLabel: 'Search activities',
        child: Container(
          constraints: const BoxConstraints(minHeight: S.tap),
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
          child: Row(children: [
            Icon(LucideIcons.search, size: 17, color: p.ink3),
            const SizedBox(width: S.x2),
            Text('Search ${allActivities.length} activities',
                style: F.body.copyWith(color: p.ink3)),
          ]),
        ),
      ),
      const SizedBox(height: S.x5),
      Text('QUICK START', style: F.over.copyWith(color: p.ink3)),
      const SizedBox(height: S.x3),
      for (var row = 0; row < 2; row++) ...[
        if (row > 0) const SizedBox(height: S.x3),
        Row(children: [
          for (var i = row * 3; i < row * 3 + 3; i++) ...[
            if (i % 3 > 0) const SizedBox(width: S.x3),
            Expanded(
              child: _QuickTile(
                quickStart[i],
                () => Navigator.of(c).push(MaterialPageRoute(
                    builder: (_) => ActivitySetup(quickStart[i],
                        weightKg: d.weightKg, host: _host(d)))),
              ),
            ),
          ],
        ]),
      ],
      for (final g in activityLibrary)
        Section(
          g.name,
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(children: [
              for (var i = 0; i < g.items.length; i++) ...[
                ActivityRow(g.items[i],
                    weightKg: d.weightKg,
                    onTap: () => Navigator.of(c).push(MaterialPageRoute(
                        builder: (_) => ActivitySetup(g.items[i],
                            weightKg: d.weightKg, host: _host(d))))),
                if (i < g.items.length - 1) Divider(color: p.line, height: 1),
              ],
            ]),
          ),
        ),
      const SizedBox(height: S.x5),
      if (d.weightKg == null)
        StatusCard(
          'Calorie estimates need your weight',
          kCalorieNeedsWeight,
          fix: 'Add weight in profile',
          // A CTA that cannot be tapped is worse than no CTA. Health's copy of
          // this card has always gone here.
          onFix: () => openProfile(c),
          icon: LucideIcons.flame,
        )
      else
        const StatusCard(
          'Calorie figures are estimates',
          kCalorieWhy,
          icon: LucideIcons.flame,
        ),
    ];
  }

  // ─────────────── HISTORY ───────────────
  List<Widget> _history(BuildContext c, _WorkoutData d) {
    final p = P.of(c);
    if (d.workouts.isEmpty) {
      return [
        StatusCard(
          'No sessions recorded yet',
          // Auto-detection writes `workout_suggestions` and nothing reads it
          // (lib/app.dart:339), so a detected effort never arrives here. The
          // string used to tell the user to wait for it.
          'Sessions appear here once you start one.',
          fix: 'Start a workout',
          onFix: () => _openPicker(c, d),
          icon: LucideIcons.dumbbell,
        ),
      ];
    }
    return [
      Row(children: [
        Expanded(child: _sum(p, '${d.workoutsTracked ?? d.workouts.length}',
            'Tracked')),
        const SizedBox(width: S.x3),
        Expanded(child: _sum(p, '${d.weekCount}', 'This week')),
        const SizedBox(width: S.x3),
        Expanded(
            child: _sum(
                p,
                d.weekLoad == null ? 'None' : d.weekLoad!.round().toString(),
                'Weekly load')),
      ]),
      const SizedBox(height: S.x5),
      for (final w in d.workouts) ...[
        _HistoryRow(w, weightKg: d.weightKg),
        const SizedBox(height: S.x3),
      ],
    ];
  }

  Widget _sum(P p, String v, String l) => Surface(
        pad: const EdgeInsets.symmetric(vertical: S.x4),
        child: Column(children: [
          Text(v, style: F.n24.copyWith(color: p.ink), maxLines: 1),
          const SizedBox(height: S.x1),
          Text(l,
              style: F.over.copyWith(color: p.ink3),
              textAlign: TextAlign.center),
        ]),
      );
}

class _QuickTile extends StatelessWidget {
  final Activity a;
  final VoidCallback onTap;
  const _QuickTile(this.a, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      pad: const EdgeInsets.symmetric(vertical: S.x4, horizontal: S.x2),
      onTap: onTap,
      semanticLabel: a.name,
      child: Column(children: [
        Container(
          width: 40,
          height: 40,
          decoration:
              BoxDecoration(color: p.wash(a.color), borderRadius: R.rMd),
          child: Icon(a.icon, size: 19, color: p.on(a.color)),
        ),
        const SizedBox(height: S.x2),
        Text(a.name,
            style: F.over.copyWith(color: p.ink2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// One past session. Taps through to the same summary a live session lands
/// on, built from the stores rather than from the six columns in this row —
/// the heart-rate curve, the sets and the route are all read on open.
class _HistoryRow extends StatelessWidget {
  final _PastWorkout w;
  final double? weightKg;
  const _HistoryRow(this.w, {this.weightKg});

  Future<void> _open(BuildContext c) async {
    final nav = Navigator.of(c);
    final r = await _detailOf(c.read<AppState>(), w);
    await nav.push(MaterialPageRoute(
        builder: (_) => ActivitySummary(r, weightKg: weightKg)));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final a = w.activity;
    return Surface(
      onTap: () => _open(c),
      child: Column(children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration:
                BoxDecoration(color: p.wash(a.color), borderRadius: R.rMd),
            child: Icon(a.icon, size: 19, color: p.on(a.color)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: F.body.copyWith(
                          color: p.ink, fontWeight: FontWeight.w600)),
                  Text(w.when, style: F.over.copyWith(color: p.ink3)),
                ]),
          ),
          if (w.strain != null) ...[
            Text(w.strain!.toStringAsFixed(1),
                style: F.n17.copyWith(color: p.ink)),
            const SizedBox(width: S.x1),
            Padding(
              padding: const EdgeInsets.only(top: S.x1),
              // "strain", not "load". Training load is CTL/ATL over weeks;
              // this is one session's 0–21 strain, and the two were being
              // shown under the same word on the same screen.
              child: Text('strain', style: F.over.copyWith(color: p.ink3)),
            ),
          ],
        ]),
        if (w.zoneMinutes.length == 5) ...[
          const SizedBox(height: S.x4),
          ChartFrame(
            title: 'TIME IN ZONES',
            unit: 'minutes',
            height: 8,
            legend: [
              for (var i = 0; i < 5; i++)
                ('Z${i + 1} · ${w.zoneMinutes[i].round()}m', ZoneBar.cols(p)[i]),
            ],
            child: CustomPaint(
                size: Size.infinite, painter: ZoneBar(w.zoneFractions, p)),
          ),
        ],
        const SizedBox(height: S.x4),
        Row(children: [
          Expanded(child: _st(p, hms(w.duration), 'Duration')),
          Expanded(
              child: _st(
                  p,
                  w.calories == null ? 'Not costed' : grouped(w.calories!),
                  'Calories · kcal')),
          Expanded(
              child: _st(p, w.maxHr == null ? 'No HR' : '${w.maxHr}',
                  'Max HR · bpm')),
        ]),
      ]),
    );
  }

  Widget _st(P p, String v, String l) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l,
              style: F.over.copyWith(color: p.ink3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: S.x1),
          Text(v,
              style: F.n17.copyWith(color: p.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      );
}

/// One day's initial. Taken from the date the point carries — deriving it from
/// the point's position in the list is how a chart comes to name days its data
/// did not come from.
String _weekdayLetter(DateTime d) =>
    const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1];

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
    final at =
        DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt() * 1000);
    final slot = 6 - end.difference(DateTime(at.year, at.month, at.day)).inDays;
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
ActivityHost activityHost(AppState app,
        {Map<String, SetHistory> history = const {}}) =>
    ActivityHost(
      feed: () => _feedOf(app),
      onStart: (a) => _startSession(app, a),
      onFinish: (draft) => _finishSession(app, draft),
      onSets: (sets) => _bankSets(app, sets),
      history: history,
      bandConnected: app.isConnected,
    );

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
    calories: w?.caloriesOrNull,
    strain: w?.strain,
    steps: app.workoutStepsMeasured,
    zoneMinutes: w?.zoneMinutes() ?? const [],
    // DENSE, not the hole-free variant: this feeds the summary's chart, whose
    // x axis is the session clock. `perMinuteHr()` is for statistics.
    hrCurve: w?.perMinuteHrDense() ?? const [],
    distanceKm: app.liveDistanceKm,
    gpsActive: app.routeTracking,
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

/// Open a real session. Until this existed the live screens ran their own
/// clock over an app that had recorded nothing: no `sessions` row, no zone
/// tally, no calorie scoring, no GPS.
Future<bool> _startSession(AppState app, Activity a) async {
  if (app.activeWorkout != null) return false;
  app.startWorkout(type: a.typeKey);
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
        'set_index':
            perExercise[s.exerciseKey] = (perExercise[s.exerciseKey] ?? 0) + 1,
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

/// Close it: finalize the session, persist the sets the user typed against
/// its id, then hand back the result with the recorded route folded in.
Future<ActivityResult> _finishSession(AppState app, ActivityResult draft) async {
  // Read the id BEFORE stopping — stopWorkout clears the live state.
  final id = app.activeWorkout?.workoutId;
  await app.stopWorkout();
  if (id == null) return draft;

  // Written on every set already; written again here because the last one
  // may have landed while the app was being torn down.
  if (draft.strength.sets.isNotEmpty) {
    await LocalDb.saveStrengthSets(id, _setRows(draft.strength.sets));
  }

  // The GPS tail is flushed by stopWorkout before it returns, so the route
  // read here is the whole route.
  try {
    final route = await app.repo?.getWorkoutRoute(id);
    if (route != null && route.hasPath) return _withRoute(draft, route);
  } catch (_) {
    // A missing map is a missing map; the session itself is already banked.
  }
  return draft;
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
    routePace: haveSpeed ? _spread([for (final s in speeds) s!]) : null,
    distanceKm: route.distanceMeters / 1000,
    elevationM: haveAlt ? [for (final a in alt) a!] : const [],
    gainM: gain,
    lossM: loss,
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
List<double?> _denseMinutes(Object? hr) {
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
  final out = List<double?>.filled(n, null);
  for (final p in pts) {
    final i = (p.$1 - t0) ~/ 60;
    if (i >= 0 && i < n) out[i] = p.$2;
  }
  return out;
}

/// One past session, opened from history — built from what the stores hold
/// rather than from the six columns the list row carries.
Future<ActivityResult> _detailOf(AppState app, _PastWorkout w) async {
  var out = w.toResult();
  final repo = app.repo;
  if (repo == null) return out;
  try {
    final b = await repo.getWorkout(w.id);
    out = out.copyWith(
      hr: _denseMinutes(b['hr']),
      // The session's own mean, computed over its heart-rate stream.
      avgHr: (b['avg_hr'] as num?)?.round(),
      maxHr: (b['max_hr'] as num?)?.round(),
    );
  } catch (_) {
    // Enrichment is best-effort; the scalars on the row still render.
  }
  try {
    final sets = await LocalDb.strengthSets(w.id);
    if (sets.isNotEmpty) out = out.copyWith(strength: _logFrom(sets));
  } catch (_) {
    /* no sets is a normal session */
  }
  try {
    final route = await repo.getWorkoutRoute(w.id);
    if (route != null && route.hasPath) out = _withRoute(out, route);
  } catch (_) {
    /* no route is a normal session */
  }
  return out;
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
              ((r['at_ts'] as num?)?.toInt() ?? 0) * 1000),
        ),
    ]);

// ── the data this screen reads ─────────────────────────────────────────────

class _Load {
  final double ctl;

  /// Nullable: the pipeline can produce fitness without fatigue and form, and
  /// zero is a real training state that must not stand in for "not computed".
  final double? atl, tsb;
  const _Load(this.ctl, this.atl, this.tsb);
}

class _PastWorkout {
  final String id;
  final Activity activity;
  final DateTime start;
  final Duration duration;
  final double? strain;
  final int? calories, avgHr, maxHr;
  final List<double> zoneMinutes;

  const _PastWorkout(this.id, this.activity, this.start, this.duration,
      {this.strain,
      this.calories,
      this.avgHr,
      this.maxHr,
      this.zoneMinutes = const []});

  List<double> get zoneFractions {
    final total = zoneMinutes.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const [0, 0, 0, 0, 0];
    return [for (final z in zoneMinutes) z / total];
  }

  String get when {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final t = '${start.hour.toString().padLeft(2, '0')}:'
        '${start.minute.toString().padLeft(2, '0')}';
    if (days == 0) return 'Today, $t';
    if (days == 1) return 'Yesterday, $t';
    if (days < 7) return '${names[start.weekday - 1]}, $t';
    return '${start.day}/${start.month}, $t';
  }

  ActivityResult toResult() => ActivityResult(
        activity,
        start: start,
        duration: duration,
        strain: strain,
        calories: calories,
        avgHr: avgHr,
        maxHr: maxHr,
        zoneMinutes: zoneMinutes,
      );
}

class _WorkoutData {
  final double? weightKg;
  final _Load? load;
  final String? loadNote;

  /// Daily TRIMP, one slot per calendar day for the seven ending [trimpEnd].
  /// Null is a day that derived nothing — a hole the painter draws as a hole,
  /// rather than a value that silently shifts the whole week along.
  final List<double?> trimp7;

  /// The day slot 6 belongs to. Carried so the x labels are read off the same
  /// anchor the buckets were built with, not off a second `DateTime.now()`.
  final DateTime? trimpEnd;
  final List<_PastWorkout> workouts;
  final Set<int> weekDays; // 0 = Monday
  final int weekCount;
  final double? weekLoad;
  final int? workoutsTracked;

  /// The activities this user actually started, most recent first, deduped.
  final List<Activity> recent;

  /// Previous and best set per exercise, from this user's own log.
  final Map<String, SetHistory> setHistory;

  const _WorkoutData({
    this.weightKg,
    this.load,
    this.loadNote,
    this.trimp7 = const [],
    this.trimpEnd,
    this.workouts = const [],
    this.weekDays = const {},
    this.weekCount = 0,
    this.weekLoad,
    this.workoutsTracked,
    this.recent = const [],
    this.setHistory = const {},
  });

  const _WorkoutData.empty() : this();
}

/// One pass over the repo. Every call is defensive: this screen must render on
/// a device that has never synced, and a throw in any one of them must not
/// take the whole tab down.
Future<_WorkoutData> _loadWorkoutData(AppState app) async {
    final repo = app.repo;
    if (repo == null) return const _WorkoutData.empty();

    double? weight;
    try {
      weight = (await repo.getProfile())['weight_kg'] as double?;
    } catch (_) {
      weight = null;
    }

    _Load? load;
    String? note;
    try {
      final raw = (await repo.getInsights())['load'];
      if (raw is Map) {
        note = needMessageFromNote(raw['note'] as String?, unit: 'days');
        final v = raw['value'];
        if (v is Map && v['ctl'] is num) {
          load = _Load(
            (v['ctl'] as num).toDouble(),
            (v['atl'] as num?)?.toDouble(),
            (v['tsb'] as num?)?.toDouble(),
          );
        }
      }
    } catch (_) {
      load = null;
    }

    // One slot per calendar day for the last seven, ending today. A day that
    // derived nothing is a hole, not a shifted neighbour: taking the last
    // seven STORED points stamped `M T W T F S S` on whatever was there, and
    // `metric_series` only gains a row on a day that derives — so after a sync
    // gap the letters named days the data did not come from, and the bar drawn
    // as "today" could be a week old.
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    var trimp = List<double?>.filled(7, null);
    try {
      trimp = lastSevenDays((await repo.getChart('trimp'))['points'], end);
    } catch (_) {
      trimp = List<double?>.filled(7, null);
    }

    final past = <_PastWorkout>[];
    try {
      final rows = (await repo.getWorkouts(range: 'month'))['workouts'];
      if (rows is List) {
        for (final r in rows) {
          if (r is! Map) continue;
          final ts = (r['start_ts'] as num?)?.toInt();
          if (ts == null) continue;
          final a = activityByName(r['type'] as String?) ??
              const Activity('Workout', LucideIcons.activity, C.purple,
                  Track.duration, 5.0);
          past.add(_PastWorkout(
            (r['id'] as String?) ?? '',
            a,
            DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            // duration_min is minutes; Motion.tick × 60 × n keeps the one
            // Duration literal in theme.dart.
            Motion.tick * 60 * ((r['duration_min'] as num?)?.toInt() ?? 0),
            strain: (r['strain'] as num?)?.toDouble(),
            calories: (r['calories'] as num?)?.round(),
            // The session's mean over its own HR stream, computed by the repo
            // — not the last sample anybody happened to see.
            avgHr: (r['avg_hr'] as num?)?.round(),
            maxHr: (r['max_hr'] as num?)?.toInt(),
            zoneMinutes: [
              for (final z in (r['zone_min'] as List? ?? const []))
                if (z is num) z.toDouble(),
            ],
          ));
        }
      }
    } catch (_) {
      // leave `past` as-is
    }
    past.sort((a, b) => b.start.compareTo(a.start));

    final weekStart = end.subtract(Motion.tick * 86400 * (end.weekday - 1));
    final thisWeek = [for (final w in past) if (w.start.isAfter(weekStart)) w];

    int? tracked;
    try {
      tracked = ((await repo.getRecords())['workouts_tracked'] as num?)
          ?.toInt();
    } catch (_) {
      tracked = null;
    }

    final weekLoad = thisWeek
        .where((w) => w.strain != null)
        .fold<double?>(null, (a, w) => (a ?? 0) + w.strain!);

    // Real recency, deduped, newest first — six tiles like the constant it
    // replaces, so the picker's row is the same shape either way.
    final recent = <Activity>[];
    for (final w in past) {
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
      load: load,
      loadNote: note,
      trimp7: trimp,
      trimpEnd: end,
      workouts: past,
      weekDays: {for (final w in thisWeek) w.start.weekday - 1},
      weekCount: thisWeek.length,
      weekLoad: weekLoad,
      workoutsTracked: tracked,
      recent: recent,
      setHistory: history,
    );
}
