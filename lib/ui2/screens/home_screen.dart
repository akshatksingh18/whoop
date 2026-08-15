// HOME — decision-oriented. "What matters today?"
//
// One number that decides the day, four signals worth a glance, and the small
// set of things the app can honestly say are worth doing. No insight feed and
// no health-observation card: those are OBSERVATION, and observation lives on
// Health. A home screen that also observes is a dashboard, and a dashboard is
// what this rebuild is replacing.
//
// This file also carries the plumbing every screen in this folder shares —
// navigation, the repo handle, and the three ways a value arrives from the
// data layer. They live here rather than in a fourth file because there are
// only three of them and they are read together.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../data/local_repository.dart';
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../profile/profile.dart';
import '../ui2.dart';
import 'metric_detail.dart';
import 'readiness_detail.dart';
import 'sleep_detail.dart';

// ═══════════════════ shared plumbing ═══════════════════

/// Page padding. The bottom inset clears the shell's floating nav.
const pad = EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16 + S.x8);

/// Push a detail screen. The transition goes through the motion gate, so
/// reduced motion gets an instant cut rather than a slower slide.
void go(BuildContext c, Widget w) => Navigator.of(c).push(PageRouteBuilder(
      transitionDuration: motion(c, Motion.slow),
      reverseTransitionDuration: motion(c, Motion.base),
      pageBuilder: (_, a, _) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(.04, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: w,
        ),
      ),
    ));

/// The repo, or null when there is no AppState above us — which is the case in
/// every golden. A screen with no repo renders its absent states, which is
/// exactly what we want a golden to capture.
LocalRepository? repoOf(BuildContext c) {
  try {
    return c.read<AppState>().repo;
  } catch (_) {
    return null;
  }
}

/// The user's unit system, or null in a golden. A screen that cannot reach it
/// renders what the store holds, which is metric.
UnitsController? unitsOf(BuildContext c) {
  try {
    return c.watch<UnitsController>();
  } catch (_) {
    return null;
  }
}

/// "72.4 kg" → `('72.4', 'kg')`. [UnitsController] owns every conversion and
/// hands back one string; this only puts the two halves in the two slots a
/// row has. Never convert in a screen.
(String, String) splitUnit(String s) {
  final i = s.lastIndexOf(' ');
  return i < 0 ? (s, '') : (s.substring(0, i), s.substring(i + 1));
}

/// The band-sync trigger, or null when there is no AppState above us. Every
/// "Sync the band" CTA in this folder goes through here — a call to action
/// with no action behind it is worse than no call to action.
VoidCallback? syncOf(BuildContext c) {
  try {
    final app = c.read<AppState>();
    return app.syncNow;
  } catch (_) {
    return null;
  }
}

/// Read a metric envelope. `_scalarMetric` writes the literal string `'—'` for
/// an absent value, so this must never be replaced by `map['value'] as num`.
Metric metricOf(Object? raw) => Metric.parse(raw);

/// The inner object of an envelope whose `value` is a MAP, not a number —
/// every cross-day metric is one of these (`regularity.value.sri`,
/// `sleep_coach.need.value.need_sec`). `Metric.parse` reads those as absent,
/// because a map is not a num, so the object has to come out by hand.
Map<String, dynamic>? envValue(Object? raw) {
  if (raw is! Map) return null;
  final v = raw['value'];
  return v is Map ? v.cast<String, dynamic>() : null;
}

/// A scalar lifted out of an object-valued envelope, wearing that envelope's
/// honesty (tier, confidence, note) so `ConfDots` and `StatusCard.forMetric`
/// still work on it.
Metric envMetric(Object? raw, num? scalar, {String? unit}) {
  final m = raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
  final env = Metric.parse({...m, 'value': scalar});
  return scalar == null && env.note == null
      ? Metric(unit: unit, note: m['note']?.toString())
      : Metric(
          value: scalar,
          unit: unit ?? env.unit,
          confidence: env.confidence,
          tier: env.tier,
          inputsUsed: env.inputsUsed,
          note: env.note,
        );
}

/// The confidence of an envelope whose value is a LABEL or an object rather
/// than a number — chronotype, a rhythm class. The tier and confidence beside
/// it are real measurements of that classification; only the value is not a
/// number. Returns `Conf.none` when the envelope has no value at all.
///
/// This exists so no screen has to put a fake `1` in the value slot to make
/// the dots light up.
Conf confOfEnv(Object? raw) {
  if (raw is! Map || raw['value'] == null) return Conf.none;
  final env = Metric.parse(raw);
  return ConfX.of(Metric(
    value: 1,
    confidence: env.confidence == 0 ? 1 : env.confidence,
    tier: env.tier,
  ));
}

/// A `[{t, v}]` point list from `getChart` as a plain series.
List<double> seriesOf(Object? chart) {
  final pts = chart is Map ? chart['points'] : null;
  if (pts is! List) return const [];
  return [
    for (final e in pts)
      if (e is Map && e['v'] is num) (e['v'] as num).toDouble(),
  ];
}

// ── formatting ──

String hm(num? minutes) {
  if (minutes == null) return '';
  final m = minutes.round();
  return m < 60 ? '${m}m' : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

String thousands(num? v) {
  if (v == null) return '';
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// Minute-of-day → "10:40 PM".
///
/// ONE clock format in the app. This used to render 24-hour while Wellness
/// rendered the same field 12-hour, so a target bedtime read `22:40` on Home
/// and `10:40 PM` two screens away. Both now go through the journal layer's
/// [formatMinuteOfDay], which is the format the rest of the app already uses
/// and the one that already has a test.
String clock(num? minOfDay) =>
    minOfDay == null ? '' : formatMinuteOfDay(minOfDay.round());

/// Epoch seconds → "11:08 PM" in the device zone.
String clockOfTs(num? ts) {
  if (ts == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts.round() * 1000);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

/// 'YYYY-MM-DD' → "Saturday, 20 May".
String prettyDay(String? dayId) {
  final d = dayId == null ? null : DateTime.tryParse(dayId);
  if (d == null) return '';
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

/// The readiness band. `readiness_glassbox` carries no label of its own, so the
/// banding is ours and lives in one place.
({String label, Color color}) readinessBand(num? v) {
  if (v == null) return (label: 'Not scored', color: C.n400);
  if (v >= 80) return (label: 'Good to go', color: C.green);
  if (v >= 60) return (label: 'Steady', color: C.green);
  if (v >= 40) return (label: 'Take it easy', color: C.orange);
  return (label: 'Rest today', color: C.red);
}

/// Glass-box driver keys are the pipeline's own short names.
const driverLabels = {
  'hrv': 'HRV',
  'rhr': 'Resting heart rate',
  'resp': 'Breathing rate',
  'temp': 'Skin temperature',
};

/// A pipeline key the map does not cover is HUMANISED, never printed raw. The
/// glass-box emits whatever inputs the composite used, so a new one used to
/// surface on Home as `resp_rate_slope`.
String driverLabel(Object? key) {
  final k = key?.toString() ?? '';
  final known = driverLabels[k];
  if (known != null) return known;
  if (k.isEmpty) return '';
  final words = k.replaceAll('_', ' ').trim();
  return words.isEmpty
      ? ''
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

// ═══════════════════ the screen ═══════════════════

class HomeData {
  final String? name;
  final String? dayId;
  final Metric readiness;
  final List<Map<String, dynamic>> drivers;
  final Metric sleepMin, sleepEff, rhr, steps, calories, caloriesTotal;
  final int stepGoal;
  final Metric sleepNeedMin;
  final Metric bedtime;
  final Map<String, dynamic>? strainTarget;

  const HomeData({
    this.name,
    this.dayId,
    this.readiness = Metric.empty,
    this.drivers = const [],
    this.sleepMin = Metric.empty,
    this.sleepEff = Metric.empty,
    this.rhr = Metric.empty,
    this.steps = Metric.empty,
    this.calories = Metric.empty,
    this.caloriesTotal = Metric.empty,
    this.stepGoal = kDefaultStepGoal,
    this.sleepNeedMin = Metric.empty,
    this.bedtime = Metric.empty,
    this.strainTarget,
  });

  static Future<HomeData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final profile = await repo.getProfile();

    final daily = today['daily'];
    final sleep = today['sleep'];
    Object? d(String k) => daily is Map ? daily[k] : null;
    Object? s(String k) => sleep is Map ? sleep[k] : null;

    final gb = cd['readiness_glassbox'];
    final gbDrivers = gb is Map ? gb['drivers'] : null;

    final coach = cd['sleep_coach'];
    final needEnv = coach is Map ? coach['need'] : null;
    final bedEnv = coach is Map ? coach['bedtime'] : null;
    final needSec = (envValue(needEnv)?['need_sec'] as num?);

    final strain = today['coach'];

    return HomeData(
      name: profile['name']?.toString(),
      dayId: (today['status'] as Map?)?['today_day']?.toString(),
      readiness: metricOf(d('readiness')),
      drivers: [
        for (final e in (gbDrivers is List ? gbDrivers : const []))
          if (e is Map) e.cast<String, dynamic>(),
      ],
      sleepMin: metricOf(s('duration_min')),
      sleepEff: metricOf(s('efficiency')),
      rhr: metricOf(d('resting_hr')),
      steps: metricOf(d('steps')),
      calories: metricOf(d('calories')),
      caloriesTotal: metricOf(d('calories_total')),
      stepGoal: (today['step_goal'] as num?)?.toInt() ?? kDefaultStepGoal,
      // sleep_coach.need is the COMPUTED need. `sleep.need_min` is a hardcoded
      // 480 and must never be shown as "your sleep need".
      sleepNeedMin: envMetric(needEnv, needSec == null ? null : needSec / 60,
          unit: 'min'),
      bedtime: envMetric(
          bedEnv, envValue(bedEnv)?['bedtime_min_of_day'] as num?),
      strainTarget: strain is Map && strain['strain_target'] is Map
          ? (strain['strain_target'] as Map).cast<String, dynamic>()
          : null,
    );
  }
}

class HomeScreen extends StatefulWidget {
  /// Injected only by goldens; production always loads.
  final HomeData? data;
  const HomeScreen({super.key, this.data});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeData? _d;
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
      final d = await HomeData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d;
    final evening = DateTime.now().hour >= 18;

    if (d == null) {
      return ListView(padding: pad, children: [
        const SizedBox(height: S.x8),
        _loading
            ? const Center(child: CircularProgressIndicator())
            : StatusCard(
                'Nothing derived yet',
                'Your day is built from the band\'s own recordings, and none '
                    'have been processed yet.',
                fix: syncOf(c) == null ? '' : 'Sync the band',
                icon: LucideIcons.watch,
                onFix: syncOf(c),
              ),
      ]);
    }

    final rv = d.readiness.value;
    final band = readinessBand(rv);

    return ListView(padding: pad, children: [
      // ── greeting ──
      Padding(
        padding: const EdgeInsets.only(top: S.x3, bottom: S.x5),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(
                    d.name == null || d.name!.isEmpty
                        ? (evening ? 'Good evening' : 'Good morning')
                        : '${evening ? 'Good evening' : 'Good morning'}, ${d.name}',
                    style: F.t2.copyWith(color: p.ink),
                  ),
                ),
                const SizedBox(width: S.x2),
                Icon(evening ? LucideIcons.moon : LucideIcons.sun,
                    size: 17, color: p.on(evening ? C.indigo : C.yellow)),
              ]),
              const SizedBox(height: 2),
              Text(prettyDay(d.dayId), style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          const SizedBox(width: S.x3),
          Pressable(
            expand: false,
            semanticLabel: 'Profile and settings',
            onTap: () => go(c, const ProfileHome()),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: p.fill(C.domHome)),
              child: Icon(LucideIcons.user, size: 18, color: p.inkOnFill),
            ),
          ),
        ]),
      ),

      // ── the one number ──
      if (rv == null)
        StatusCard.forMetric('Readiness is not scored today', d.readiness,
                why: 'Readiness needs a night of beat-to-beat data plus enough '
                    'history to know what normal looks like for you.') ??
            const SizedBox.shrink()
      else
        Surface(
          elevation: 2,
          onTap: () => go(c, const ReadinessDetail()),
          semanticLabel: 'Readiness ${rv.round()} of 100. ${band.label}.',
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Today's readiness",
                          style: F.cap.copyWith(color: p.ink2)),
                      const SizedBox(height: S.x3),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('${rv.round()}',
                                style: F.n48.copyWith(color: p.ink)),
                            Text(' /100', style: F.cap.copyWith(color: p.ink3)),
                          ]),
                      const SizedBox(height: S.x3),
                      Pill(band.label, band.color),
                    ]),
              ),
              SizedBox(
                width: 96,
                height: 96,
                child: CustomPaint(
                  painter: Ring(d.readiness.normalized(100), band.color,
                      p.track,
                      stroke: 11, t: animate(c, 1)),
                ),
              ),
            ]),
            if (d.drivers.isNotEmpty) ...[
              const SizedBox(height: S.x4),
              Divider(color: p.line, height: 1),
              const SizedBox(height: S.x3),
              Row(children: [
                Text('Why?', style: F.cap.copyWith(color: p.ink3)),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(
                    d.drivers
                        .take(3)
                        .map((e) => driverLabel(e['label']))
                        .join(' · '),
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 15, color: p.ink3),
              ]),
            ],
          ]),
        ),

      // ── at a glance ──
      Section('At a glance', _glance(c, d)),

      // ── today's plan: only what the app can actually stand behind ──
      Section("Today's plan", _plan(c, p, d)),
    ]);
  }

  Widget _glance(BuildContext c, HomeData d) {
    final cards = <Widget>[];
    final absent = <Widget>[];

    void add(Metric m, Widget Function() card, StatusCard? Function() gap) {
      if (m.isEmpty) {
        final s = gap();
        if (s != null) absent.add(s);
      } else {
        cards.add(card());
      }
    }

    add(
      d.sleepMin,
      () => SignalCard(LucideIcons.moon, C.blue, 'Sleep',
          hm(d.sleepMin.value), sub: _sleepWord(d.sleepEff.value),
          conf: ConfX.of(d.sleepMin), onTap: () => go(c, const SleepDetail())),
      () => StatusCard.forMetric('No sleep last night', d.sleepMin,
          why: 'No night long enough to score was recorded.'),
    );
    add(
      d.rhr,
      () => SignalCard(LucideIcons.heart, C.red, 'Heart rate',
          '${d.rhr.value!.round()}',
          unit: 'bpm',
          sub: 'Resting',
          conf: ConfX.of(d.rhr),
          onTap: () => go(c, const MetricDetail('resting_hr'))),
      () => StatusCard.forMetric('No resting heart rate', d.rhr,
          why: 'Resting heart rate is read from sleep, and no sleep was '
              'recorded.'),
    );
    add(
      d.steps,
      () => SignalCard(LucideIcons.footprints, C.green, 'Steps',
          thousands(d.steps.value),
          sub:
              '${((d.steps.value! / d.stepGoal) * 100).clamp(0, 999).round()}% of goal',
          conf: ConfX.of(d.steps),
          onTap: () => go(c, const MetricDetail('steps'))),
      () => StatusCard.forMetric('No step count today', d.steps,
          why: 'Steps come from wrist motion while the band is worn.'),
    );
    add(
      d.calories,
      () => SignalCard(LucideIcons.flame, C.orange, 'Active energy',
          thousands(d.calories.value),
          unit: 'kcal',
          sub: d.caloriesTotal.value == null
              ? 'Estimated'
              : '${thousands(d.caloriesTotal.value)} total',
          conf: ConfX.of(d.calories),
          onTap: () => go(c, const MetricDetail('calories'))),
      () => StatusCard.forMetric('No energy estimate', d.calories,
          why: 'Calories are estimated from heart rate, and need your weight '
              'and age.'),
    );

    return Column(children: [
      for (var i = 0; i < cards.length; i += 2) ...[
        if (i > 0) const SizedBox(height: S.x3),
        // IntrinsicHeight, because `stretch` inside a ListView asks for an
        // infinite height. The two cards in a row must match: a short card
        // beside a tall one reads as a layout bug, not as less data.
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: cards[i]),
            const SizedBox(width: S.x3),
            if (i + 1 < cards.length)
              Expanded(child: cards[i + 1])
            else
              const Spacer(),
          ]),
        ),
      ],
      for (final s in absent) ...[const SizedBox(height: S.x3), s],
    ]);
  }

  String _sleepWord(num? efficiency) {
    if (efficiency == null) return 'Recorded';
    final pct = efficiency <= 1 ? efficiency * 100 : efficiency;
    if (pct >= 88) return 'Efficient';
    if (pct >= 80) return 'Settled';
    return 'Broken';
  }

  Widget _plan(BuildContext c, P p, HomeData d) {
    final rows = <Widget>[];

    final stepsLeft = d.steps.value == null
        ? null
        : (d.stepGoal - d.steps.value!).round();
    if (stepsLeft != null && stepsLeft > 0) {
      rows.add(_row(p, LucideIcons.footprints, C.green,
          '${thousands(stepsLeft)} steps left', 'Movement',
          'Goal ${thousands(d.stepGoal)}', false));
    } else if (stepsLeft != null) {
      rows.add(_row(p, LucideIcons.footprints, C.green, 'Step goal met',
          'Movement', 'Done', true));
    }

    final target = d.strainTarget;
    if (target != null && target['value'] is num) {
      rows.add(_row(
          p,
          LucideIcons.zap,
          C.purple,
          'Aim for ${(target['value'] as num).toStringAsFixed(1)} strain',
          'Training',
          '${(target['low'] as num?)?.toStringAsFixed(1) ?? ''}–'
              '${(target['high'] as num?)?.toStringAsFixed(1) ?? ''}',
          false));
    }

    final need = d.sleepNeedMin.value;
    if (need != null) {
      rows.add(_row(
          p,
          LucideIcons.bedDouble,
          C.blue,
          '${hm(need)} of sleep',
          'Tonight',
          d.bedtime.value == null ? 'Need' : 'Bed ${clock(d.bedtime.value)}',
          false));
    }

    if (rows.isEmpty) {
      return StatusCard.forMetric('No plan for today yet', d.sleepNeedMin,
              why: 'A plan comes from your own baselines — sleep need, a '
                  'training target, a step goal — and none are established '
                  'yet.') ??
          const SizedBox.shrink();
    }

    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          rows[i],
        ],
      ]),
    );
  }

  Widget _row(P p, IconData i, Color col, String title, String kind,
          String meta, bool done) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration:
                BoxDecoration(color: p.wash(col), borderRadius: R.rSm),
            child: Icon(i, size: 16, color: p.on(col)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind, style: F.over.copyWith(color: p.ink3)),
                  const SizedBox(height: 2),
                  Text(title, style: F.body.copyWith(color: p.ink)),
                ]),
          ),
          const SizedBox(width: S.x2),
          Text(meta,
              textAlign: TextAlign.right,
              style: F.cap.copyWith(
                  color: done ? p.on(C.green) : p.ink3,
                  fontWeight: done ? FontWeight.w600 : FontWeight.w400)),
        ]),
      );
}
