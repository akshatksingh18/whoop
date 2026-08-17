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

/// WHICH SENSOR counted the steps, in the two words a card has room for — or
/// null when nothing counted (and on days derived before the ladder existed,
/// whose envelopes name no sensor).
///
/// Read off `inputs_used`, which names the sensor rather than the table the
/// count was stored in. The strap's 100 Hz pedometer and its on-chip counter
/// are BOTH "Strap" here: they are genuinely different measurements, but that
/// difference is a density-3 fact and it is spelled out on Nerd stats. What
/// this must never blur is strap versus phone — a card that lets the phone's
/// count read as the wrist's, or the other way round, defeats the whole point
/// of resolving the day per window.
String? stepSensorLabel(Metric m) {
  final used = m.inputsUsed;
  final strap = used.contains('band_pedometer_100hz') ||
      used.contains('band_step_counter');
  final phone = used.contains('phone_pedometer');
  if (strap && phone) return 'Strap + phone';
  if (strap) return 'Strap';
  if (phone) return 'Phone';
  return null;
}

/// The inner object of an envelope whose `value` is a MAP, not a number —
/// every cross-day metric is one of these (`regularity.value.sri`,
/// `sleep_coach.need.value.need_sec`). `Metric.parse` reads those as absent,
/// because a map is not a num, so the object has to come out by hand.
Map<String, dynamic>? envValue(Object? raw) {
  if (raw is! Map) return null;
  final v = raw['value'];
  return v is Map ? v.cast<String, dynamic>() : null;
}

/// The night the overnight block in a `getToday()` result actually came from,
/// when that is NOT today's — otherwise null.
///
/// `getToday` holds the last scored night over until today's settles, which is
/// every morning before the first sync and the whole of any gap after one.
/// Readiness, sleep, resting HR, HRV and skin temperature then all describe
/// that night while steps and active energy describe today. Every screen that
/// shows one of those five resolves the night HERE, so Home, Readiness, Sleep
/// and Health cannot each answer "which night is this?" differently.
String? heldOverNightOf(Map<String, dynamic> today) {
  final st = today['status'];
  if (st is! Map) return null;
  return st['showing_prior_overnight'] == true
      ? st['overnight_day']?.toString()
      : null;
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

/// A metric value at the precision its unit actually carries.
///
/// ONE rule, so the same reading is not `71.6` on the detail screen and `72`
/// on the card that links to it. A tenth of a bpm on a nocturnal minimum — or
/// of a millisecond on beat timing recovered from 1 Hz records — is precision
/// the measurement does not have, and a number printing more digits than it
/// knows reads as a more careful measurement than it is. Unitless scores keep
/// a decimal only while they are small enough for one to mean something.
String metricValue(String unit, num? value) {
  if (value == null) return '';
  final v = value.toDouble();
  switch (unit) {
    case 'min':
      return hm(v);
    case 'steps':
    case 'kcal':
      return thousands(v);
    case 'bpm':
    case 'ms':
    case '%':
      return v.round().toString();
    case 'br/min':
    case '°':
      return v.toStringAsFixed(1);
  }
  if (v.abs() >= 100) return v.round().toString();
  if (v.abs() >= 10) return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  return v.toStringAsFixed(1);
}

/// The unit to print BESIDE [metricValue]'s output, which is empty when the
/// format already carries it: `metricValue('min', 443)` is "7h 23m", and a
/// `min` label next to that reads "7h 23m min".
String unitBeside(String unit) => unit == 'min' ? '' : unit;

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

/// The one number, and why.
///
/// Lifted out of the Home list so the gallery can photograph it. It was the
/// card the whole app is judged by and the only one the component gallery
/// could not show, because it lived inline in a `ListView` behind a database.
/// Only rendered for a scored day — the absent case is a [StatusCard], not a
/// ring with nothing in it.
class ReadinessHero extends StatelessWidget {
  final Metric readiness;
  final List<Map<String, dynamic>> drivers;

  /// The night this score describes, when that is not last night.
  final String? heldOverNight;
  final VoidCallback? onTap;

  const ReadinessHero({
    super.key,
    required this.readiness,
    this.drivers = const [],
    this.heldOverNight,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final rv = readiness.value!;
    final band = readinessBand(rv);
    return Surface(
      elevation: 2,
      onTap: onTap,
      semanticLabel: 'Readiness ${rv.round()} of 100. ${band.label}.',
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Names the night it came from when that is not last
                  // night. The overnight block is held over until today's
                  // settles, so before the first sync of the morning — and
                  // for the whole of any gap after one — this number
                  // describes an older night while the steps and energy
                  // beside it describe today.
                  Text(
                      heldOverNight == null
                          ? "Today's readiness"
                          : 'Readiness · ${prettyDay(heldOverNight)}',
                      style: F.cap.copyWith(color: p.ink2)),
                  const SizedBox(height: S.x3),
                  // A Wrap: the ring beside this column is a fixed 96 pt that
                  // does not scale with text, so at an accessibility size
                  // "72 /100" had nowhere to go and overflowed Home's first
                  // card by 41 px. The "/100" drops to its own line instead.
                  Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
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
              painter: Ring(readiness.normalized(100), p.on(band.color),
                  p.track,
                  stroke: 11, t: animate(c, 1)),
            ),
          ),
        ]),
        if (drivers.isNotEmpty) ...[
          const SizedBox(height: S.x4),
          Divider(color: p.line, height: 1),
          const SizedBox(height: S.x3),
          Row(children: [
            Text('Why?', style: F.cap.copyWith(color: p.ink3)),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text(
                drivers.take(3).map((e) => driverLabel(e['label'])).join(' · '),
                style: F.cap.copyWith(color: p.ink2),
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 15, color: p.ink3),
          ]),
        ],
      ]),
    );
  }
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

  /// The night the overnight block actually came from, when it is NOT today's.
  ///
  /// `getToday` holds the last scored night over whenever today's has not
  /// settled — which is every morning before the first sync, and the whole of
  /// any gap after one. Readiness, sleep, resting HR, HRV and skin temperature
  /// then all describe that night while steps and active energy describe
  /// today, so one screen shows two different days. The old UI withheld the
  /// score outright (`TodayData.settledReadinessScore`, still pinned by
  /// `test/readiness_flash_test.dart`); ui2 never consulted the gate.
  ///
  /// Withholding is the wrong answer here — the number is real and it is the
  /// most recent one there is. Naming its night is the right one.
  final String? heldOverNight;

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
    this.heldOverNight,
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

    final heldOver = heldOverNightOf(today);

    return HomeData(
      name: profile['name']?.toString(),
      dayId: (today['status'] as Map?)?['today_day']?.toString(),
      heldOverNight: heldOver,
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

  /// The load THREW. Distinct from "there is nothing yet": a decode or a locked
  /// database is a read problem, and telling a user with three months of
  /// history that their band has never produced data is the wrong answer to it.
  bool _failed = false;

  /// The revision this screen's data was loaded at, and the notifier it came
  /// from — the same pattern `WorkoutScreen` already uses. Home used to load
  /// once post-frame and never listen, so the "Sync the band" button it renders
  /// could not change what the screen showed: the offload landed, the derive
  /// ran, and Home kept saying "Nothing derived yet" until the app was
  /// relaunched.
  int _loadedAt = -1;
  ValueNotifier<int>? _rev;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.data != null) return;
    // No AppState above us in a golden — the screen just renders what it has.
    final AppState app;
    try {
      app = context.read<AppState>();
    } catch (_) {
      return;
    }
    if (!identical(_rev, app.insightsRevision)) {
      _rev?.removeListener(_onRevision);
      _rev = app.insightsRevision..addListener(_onRevision);
      _loadedAt = app.insightsRevision.value;
    }
  }

  void _onRevision() {
    final r = _rev;
    if (!mounted || r == null || r.value == _loadedAt) return;
    _loadedAt = r.value;
    _load();
  }

  @override
  void dispose() {
    _rev?.removeListener(_onRevision);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final d = await HomeData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false, _failed = false));
    } catch (_) {
      if (mounted) setState(() => (_loading = false, _failed = true));
    }
  }

  /// Morning / afternoon / evening / night. One split at 18:00 greeted 00:30
  /// and 15:40 alike with "Good morning" beside a sun.
  ({String word, IconData icon, Color color}) _greeting(int h) {
    if (h < 5) return (word: 'Still up', icon: LucideIcons.moon, color: C.indigo);
    if (h < 12) {
      return (word: 'Good morning', icon: LucideIcons.sun, color: C.yellow);
    }
    if (h < 18) {
      return (word: 'Good afternoon', icon: LucideIcons.sun, color: C.orange);
    }
    return (word: 'Good evening', icon: LucideIcons.moon, color: C.indigo);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d;
    final g = _greeting(widget.hour ?? DateTime.now().hour);

    if (d == null) {
      return _refreshable(ListView(padding: pad, children: [
        const SizedBox(height: S.x8),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_failed)
          StatusCard(
            'Today could not be read',
            'The stored day failed to load. Nothing was deleted — this is a '
                'read that went wrong, not missing data.',
            fix: 'Try again',
            icon: LucideIcons.databaseZap,
            onFix: () {
              setState(() => (_loading = true, _failed = false));
              _load();
            },
          )
        else
          StatusCard(
            'Nothing derived yet',
            'No band recordings processed yet.',
            fix: syncOf(c) == null ? '' : 'Sync the band',
            icon: LucideIcons.watch,
            onFix: syncOf(c),
          ),
      ]));
    }

    // Nothing measured at all. This is the genuine first run, and it used to be
    // reachable ONLY by a load throwing — a real first-run user got four
    // stacked absence cards instead of the one card written for this state.
    final bare = d.readiness.isEmpty &&
        d.sleepMin.isEmpty &&
        d.rhr.isEmpty &&
        d.steps.value == null &&
        d.calories.isEmpty;

    final rv = d.readiness.value;
    final stale = staleInsightsCard(d.insightsStale, syncOf(c));
    // Above the greeting, not below it: if the app had to rebuild the database
    // to start, that outranks anything else this screen has to say today.
    final rebuilt = dbRebuiltCard(dbRebuildOf(c));

    return _refreshable(ListView(padding: pad, children: [
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
                        ? g.word
                        : '${g.word}, ${d.name}',
                    style: F.t2.copyWith(color: p.ink),
                  ),
                ),
                const SizedBox(width: S.x2),
                Icon(g.icon, size: 17, color: p.on(g.color)),
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

      if (bare)
        StatusCard(
          'Nothing derived yet',
          'No band recordings processed yet.',
          fix: syncOf(c) == null ? '' : 'Sync the band',
          icon: LucideIcons.watch,
          onFix: syncOf(c),
        )
      else ...[
        // ── the one number ──
        //
        // The empty state is a DOOR, not a dead end. The pipeline records why
        // readiness came back absent on every day it does — which input was
        // missing, how many of your own nights are behind each one — and that
        // diagnostic used to go nowhere but a Firebase breadcrumb. It belongs
        // one tap away, on the Readiness screen: a wall of per-input
        // diagnostics on Home makes the app read as broken.
        if (rv == null)
          Builder(builder: (c) {
            final need = needMessageFromNote(d.readiness.note);
            return StatusCard(
              'Readiness is not scored today',
              need != null
                  ? '$need to know what normal looks like for you.'
                  // Was "Needs a night of beat-to-beat data, plus your own
                  // history to compare it to" — a cause, stated for every
                  // absence the note convention did not cover. The door below
                  // is what actually answers it.
                  : whyFromNote(d.readiness.note) ??
                      'Nothing recorded says why.',
              fix: 'See what was missing',
              icon: LucideIcons.batteryCharging,
              onFix: () => go(c, const ReadinessDetail()),
            );
          })
        else
          ReadinessHero(
            readiness: d.readiness,
            drivers: d.drivers,
            heldOverNight: d.heldOverNight,
            onTap: () => go(c, const ReadinessDetail()),
          ),

        // ── the rollup was withheld, not absent ──
        if (stale != null) ...[const SizedBox(height: S.x3), stale],

        // ── at a glance ──
        Section('At a glance', _glance(c, d)),

        // ── today's plan: only what the app can actually stand behind ──
        Section("Today's plan", _plan(c, p, d)),
      ],
    ]));
  }

  /// Pull to reload. The screen also reloads itself on `insightsRevision`, but
  /// a derive that fails silently, an import, or anything that lands without
  /// bumping it still leaves the user a way to ask.
  Widget _refreshable(Widget list) =>
      RefreshIndicator(onRefresh: _load, child: list);

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

    // Sleep and resting heart rate come off the SAME overnight block readiness
    // does, so when that block is held over they describe the same older night
    // — and they sat beside steps and active energy, which are today's, with no
    // date at all. Naming the night is what the hero already does.
    final night = d.heldOverNight;
    String ofNight(String s) =>
        night == null ? s : '$s · ${prettyDay(night)}';

    add(
      d.sleepMin,
      () => SignalCard(LucideIcons.moon, C.blue, 'Sleep',
          hm(d.sleepMin.value),
          sub: ofNight(_sleepWord(d.sleepEff.value)),
          onTap: () => go(c, const SleepDetail())),
      // Kept: sleep duration absent IS "no night was scored" — the fallback
      // restates the headline rather than naming a second cause, and a real
      // note from the stager now outranks it anyway.
      () => StatusCard.forMetric('No sleep last night', d.sleepMin,
          why: 'No night long enough to score was recorded.'),
    );
    add(
      d.rhr,
      () => SignalCard(LucideIcons.heart, C.red, 'Heart rate',
          '${d.rhr.value!.round()}',
          unit: 'bpm',
          sub: ofNight('Resting'),
          onTap: () => go(c, const MetricDetail('resting_hr'))),
      // "no sleep was recorded" was stated as fact, unconditionally — and it
      // was rendered directly beside a Sleep card showing that night's
      // duration. Sleep duration and nocturnal RHR are gated separately: a
      // night staged from the accelerometer with no clean resting window
      // produces exactly that pair.
      // The else-branch used to name the gate — "no stretch of beats clean
      // enough" — which is one of several reasons a scored night yields no
      // resting rate, picked by a human writing copy. Only the branch the
      // screen can actually see is stated; the other defers to the note, or to
      // saying it does not know.
      () => StatusCard.forMetric('No resting heart rate', d.rhr,
          why: d.sleepMin.isEmpty
              ? 'Resting heart rate is read from sleep, and no sleep was '
                  'recorded.'
              : ''),
    );
    // Steps keeps its tile whether or not a counter reported. Zero steps is a
    // real reading — an unmoved counter — and it renders as 0, not as absence.
    // When nothing counted at all the tile stays and says so in two words,
    // rather than the whole card being replaced by a paragraph about wrist
    // motion: the answer to "how many steps" is short either way.
    cards.add(SignalCard(
      LucideIcons.footprints,
      C.green,
      'Steps',
      d.steps.value == null ? 'None' : thousands(d.steps.value),
      // The sensor rides the line that is already there rather than adding a
      // row: the day is resolved per window now, so "8,412" can be the strap's
      // count, the phone's, or both, and the card has to say which. The split
      // behind a mixed day is on Nerd stats, one tap down.
      sub: d.steps.value == null
          ? 'NOT RECORDED'
          : [
              if (d.stepGoal > 0)
                '${((d.steps.value! / d.stepGoal) * 100).clamp(0, 999).round()}% of goal',
              ?stepSensorLabel(d.steps),
            ].join(' · '),
      onTap: () => go(c, const MetricDetail('steps')),
    ));
    add(
      d.calories,
      () => SignalCard(LucideIcons.flame, C.orange, 'Active energy',
          thousands(d.calories.value),
          unit: 'kcal',
          sub: d.caloriesTotal.value == null
              ? 'Estimated'
              : '${thousands(d.caloriesTotal.value)} total',
          onTap: () => go(c, const MetricDetail('calories'))),
      // No `why:`. It said "Needs your weight and age" — and the measured run
      // printed that to a profile carrying both, because energy had gone absent
      // for an entirely different reason that the card never asked for.
      () => StatusCard.forMetric('No energy estimate', d.calories),
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
                  : 'None are established yet.') ??
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
