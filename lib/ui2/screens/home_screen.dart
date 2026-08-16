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

import '../../data/db.dart' show DbRebuild;
import '../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../data/local_repository.dart';
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../../theme/theme_switcher.dart' show themedRoute;
import '../profile/profile.dart';
import '../ui2.dart';
import 'metric_detail.dart';
import 'readiness_detail.dart';
import 'sleep_detail.dart';

// ═══════════════════ shared plumbing ═══════════════════

/// Page padding. The bottom inset clears the shell's floating nav.
const pad = EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16 + S.x8);

/// Push a detail screen. Every drill-down in ui2 goes through here.
///
/// This was a raw `PageRouteBuilder` with its own fade+slide, which silently
/// killed the iOS edge-swipe-back on all ~20 screens it pushes — a
/// PageRouteBuilder has no interactive back-gesture machinery. The app's own
/// transition is registered in the theme instead (see page_transitions.dart),
/// so a plain route gets the fade-through on Android and the Cupertino slide
/// WITH swipe-back on iOS. [themedRoute] also keeps the pushed screen
/// re-colouring on an appearance change and names the route for Crashlytics.
void go(BuildContext c, Widget w) => Navigator.of(c)
    .push(themedRoute((_) => w, name: w.runtimeType.toString()));

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

/// Whether the database had to be rebuilt to start this launch, or null in a
/// golden. Same shape as [repoOf] and [syncOf].
DbRebuild? dbRebuildOf(BuildContext c) {
  try {
    return c.read<AppState>().dbRebuild;
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
/// honesty (tier, confidence, note) so `StatusCard.forMetric` still works on
/// it.
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

/// One stored chart point: `t` is the epoch SECONDS `getChart` stamps on it
/// (local noon of the day the value was derived on), `v` the value.
typedef ChartPoint = ({int t, double v});

/// A `[{t, v}]` point list from `getChart`, timestamps INTACT.
///
/// [seriesOf] drops `t`, and everything downstream then labelled its x axis off
/// the ARRAY INDEX — `'Today'`, `'N days ago'`, weekday letters. `metric_series`
/// stores one row per DERIVED day, not one per calendar day, so after a sync gap
/// the newest stored point is days old and was still being called "Today".
/// Anything that draws a dated axis reads this.
List<ChartPoint> pointsOf(Object? chart) {
  final pts = chart is Map ? chart['points'] : null;
  if (pts is! List) return const [];
  return [
    for (final e in pts)
      if (e is Map && e['v'] is num && e['t'] is num)
        (t: (e['t'] as num).round(), v: (e['v'] as num).toDouble()),
  ];
}

/// The bare values of a point list, for statistics — a mean, a last reading,
/// an [AxisSpec]. NEVER for a painter: a compacted list is the bug, because it
/// lets 22 stored days masquerade as 30 continuous ones.
List<double> valuesOf(List<ChartPoint> pts) => [for (final p in pts) p.v];

/// [pts] laid out DENSE: one slot per calendar day, [days] slots long, ending
/// today. A day `metric_series` has no row for is `null`, which the painter
/// draws as a break rather than joining across.
///
/// This is the shape every chart in this app takes. `metric_series` gets a row
/// only on a day that derives, so the stored list is already compacted: after a
/// four-day sync gap the newest point sat at the right-hand edge under the
/// label "Today", and the line ran straight through the missing week as though
/// it had been measured.
List<double?> denseDays(List<ChartPoint> pts, int days) {
  final out = List<double?>.filled(days, null);
  for (final p in pts) {
    final behind = daysBehind(p.t);
    if (behind == null || behind < 0 || behind >= days) continue;
    out[days - 1 - behind] = p.v;
  }
  return out;
}

/// A `[{t, v}]` point list from `getChart` as a plain series.
///
/// Values only — the caller cannot tell WHEN any of them was recorded. Use
/// [pointsOf] for anything that labels, spans or dates the series; this is for
/// sparklines, which claim nothing about time.
List<double> seriesOf(Object? chart) => valuesOf(pointsOf(chart));

/// An x-axis label for a stored point: [todayWord] when the point really is
/// today's, otherwise "N days ago" counted from the point's OWN date.
///
/// The same vocabulary the axes already spoke. What changed is where N comes
/// from: it used to be the point's position in the array, and `metric_series`
/// holds one row per DERIVED day, so a thirty-point series can span two months
/// and both its edges were labelled as though it spanned thirty days.
String axisDay(int? epochSec,
    {String todayWord = 'Today', String unitWord = 'days'}) {
  final behind = daysBehind(epochSec);
  if (behind == null) return '';
  if (behind <= 0) return todayWord;
  return '$behind $unitWord ago';
}

/// Whole calendar days between a stored point and today, or null when there is
/// no point. Anything above zero means the number drawn is not today's, and a
/// card that presents it as today's has to say so.
int? daysBehind(int? epochSec) {
  if (epochSec == null) return null;
  return calendarDaysBetween(
      DateTime.fromMillisecondsSinceEpoch(epochSec * 1000), DateTime.now());
}

/// Whole calendar days from [from] to [to], reading both as LOCAL wall-clock
/// dates and subtracting them in UTC — the same shape as
/// `LocalRepositoryImpl._dayGap`, which is where this rule already lived.
///
/// Subtracting two local midnights across a DST boundary is 23 or 25 hours and
/// `inDays` truncates the short one, so on 10 March in New York both 9 March
/// and 8 March came back as 1 day behind: [denseDays] wrote them into the same
/// slot, lost the older one, and every dated axis before the spring-forward
/// shifted by a position.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// The withheld-rollup reason inside a `getInsights()` result, or null when the
/// result is real (or simply empty).
Map<String, dynamic>? staleReasonOf(Map<String, dynamic> insights) =>
    insights['stale'] is Map
        ? (insights['stale'] as Map).cast<String, dynamic>()
        : null;

/// The cross-day rollup was WITHHELD: `getInsights` returned the reason it
/// refused instead of the numbers (`LocalRepositoryImpl.crossDayStaleReason`).
///
/// Every screen that reads the rollup renders this rather than quietly showing
/// nothing — "you have no drivers yet" and "we have drivers we will not stand
/// behind" are different states, and the cold-start copy is a wrong answer to
/// the second one.
/// The database could not be opened on this launch and was rebuilt.
///
/// This is the loudest thing this screen can say, and it should be: the old
/// file is parked on disk and only what `salvaged` lists came back. A rebuild
/// the user never hears about is indistinguishable from their data quietly
/// vanishing — which is the one thing a local-first app must never do.
///
/// The counts are stated per table rather than summed. "1,204 rows recovered"
/// reads as reassurance; "nutrition 0" is the sentence that actually tells
/// someone their food log is gone.
StatusCard? dbRebuiltCard(DbRebuild? r) {
  if (r == null) return null;
  final saved = r.salvaged.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final lost = r.salvaged.entries.where((e) => e.value == 0).toList();
  return StatusCard(
    'Your database was rebuilt to start the app',
    '${r.cause}\n\n'
        '${saved.isEmpty ? 'Nothing could be read back.' : 'Recovered: ${saved.map((e) => '${e.key} ${thousands(e.value)}').join(' · ')}.'}'
        '${lost.isEmpty ? '' : ' Empty: ${lost.map((e) => e.key).join(' · ')}.'}'
        '\n\nThe original file is kept at ${r.quarantinePath} — nothing was '
        'deleted.',
    icon: LucideIcons.databaseBackup,
  );
}

StatusCard? staleInsightsCard(
    Map<String, dynamic>? reason, VoidCallback? onSync) {
  final s = reason;
  if (s == null) return null;
  final built = s['built_for_day']?.toString();
  return StatusCard(
    'Your cross-day insights are being rebuilt',
    switch (s['kind']) {
      'algo_version' =>
        'How these are computed changed with the last update.',
      'stale' => 'The last rollup was built '
          '${built == null || built.isEmpty ? 'over a week ago' : 'on ${prettyDay(built)}'}'
          ', which is too old to stand behind.',
      _ => 'The stored rollup carries no version stamp.',
    },
    fix: onSync == null ? '' : 'Sync the band',
    icon: LucideIcons.refreshCw,
    onFix: onSync,
  );
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
/// banding is ours and lives in one place — this one.
///
/// [tier] is that same banding in a form the native surfaces can read.
/// `WidgetService.push` publishes it as `readiness_tier` (and [label] as
/// `readiness_band`) so the widget, the Watch and Siri paint it in their own
/// palettes instead of each keeping a private copy of the cut-offs. They did,
/// and a 65 rendered green on the phone, orange on the widget and yellow on
/// the wrist. -1 = not scored.
({String label, Color color, int tier}) readinessBand(num? v) {
  if (v == null) return (label: 'Not scored', color: C.n400, tier: -1);
  if (v >= 80) return (label: 'Good to go', color: C.green, tier: 3);
  if (v >= 60) return (label: 'Steady', color: C.green, tier: 2);
  if (v >= 40) return (label: 'Take it easy', color: C.orange, tier: 1);
  return (label: 'Rest today', color: C.red, tier: 0);
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

  /// Non-null when the cross-day rollup was withheld rather than absent — see
  /// [staleInsightsCard]. Drivers, sleep need and bedtime are all empty in that
  /// case, and the screen owes the user the reason.
  final Map<String, dynamic>? insightsStale;

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
    this.insightsStale,
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
      insightsStale: staleReasonOf(cd),
    );
  }
}

class HomeScreen extends StatefulWidget {
  /// Injected only by goldens; production always loads.
  final HomeData? data;

  /// Hour of day, injected only by goldens. The greeting reads the clock, so a
  /// golden baked in the evening fails the next morning on nothing but the
  /// word "evening" — a test that breaks by being run at a different time is
  /// noise that trains you to regenerate without looking.
  final int? hour;

  const HomeScreen({super.key, this.data, this.hour});

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
    final evening = (widget.hour ?? DateTime.now().hour) >= 18;

    if (d == null) {
      return ListView(padding: pad, children: [
        const SizedBox(height: S.x8),
        _loading
            ? const Center(child: CircularProgressIndicator())
            : StatusCard(
                'Nothing derived yet',
                'No band recordings processed yet.',
                fix: syncOf(c) == null ? '' : 'Sync the band',
                icon: LucideIcons.watch,
                onFix: syncOf(c),
              ),
      ]);
    }

    final rv = d.readiness.value;
    final band = readinessBand(rv);
    final stale = staleInsightsCard(d.insightsStale, syncOf(c));
    // Above the greeting, not below it: if the app had to rebuild the database
    // to start, that outranks anything else this screen has to say today.
    final rebuilt = dbRebuiltCard(dbRebuildOf(c));

    return ListView(padding: pad, children: [
      if (rebuilt != null) ...[const SizedBox(height: S.x3), rebuilt],
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
                why: 'Needs a night of beat-to-beat data, plus your own history'
                     ' to compare it to.') ??
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
                  painter: Ring(d.readiness.normalized(100), p.on(band.color),
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

      // ── the rollup was withheld, not absent ──
      if (stale != null) ...[const SizedBox(height: S.x3), stale],

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
          hm(d.sleepMin.value),
          sub: _sleepWord(d.sleepEff.value),
          onTap: () => go(c, const SleepDetail())),
      () => StatusCard.forMetric('No sleep last night', d.sleepMin,
          why: 'No night long enough to score was recorded.'),
    );
    add(
      d.rhr,
      () => SignalCard(LucideIcons.heart, C.red, 'Heart rate',
          '${d.rhr.value!.round()}',
          unit: 'bpm',
          sub: 'Resting',
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
          onTap: () => go(c, const MetricDetail('calories'))),
      () => StatusCard.forMetric('No energy estimate', d.calories,
          why: 'Estimated from heart rate. Needs your weight and age.'),
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
              // "none are established yet" is the COLD-START reason, and it is
              // a wrong answer when the baselines exist and are being withheld.
              why: d.insightsStale != null
                  ? 'The cross-day rollup they come from is being rebuilt.'
                  : 'A plan comes from your own baselines. None are established'
                    ' yet.') ??
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
