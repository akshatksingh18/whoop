// HOME — decision-oriented. "What matters today?"
//
// Three rings that decide the day — what the night gave back, what the day has
// cost, what the night was made of — three signals worth a glance under them,
// and the small set of things the app can honestly say are worth doing. The
// hard part is not the circles: readiness exists on 71 % of days and needs
// four prior nights before it exists at all, so what a ring does with nothing
// in it is the design. See [RingTrio]. No insight feed and no general
// health-observation card: those are OBSERVATION, and observation lives on
// Health. A home screen that also observes is a dashboard, and a dashboard is
// what this rebuild is replacing.
//
// ONE NAMED EXCEPTION, and it is deliberately not a crack in that rule: the
// illness watch ([_bodyWatch]). It is not a feed and it cannot grow into one —
// exactly one detector may render here, it renders only when its own state is
// amber or red, and it is silent on every ordinary day. The reason it earns
// Home is timing rather than importance: the watch is at its most useful when
// it first goes amber, and amber has no notification, so before this the
// earliest signal the app produces could only be found by opening Health and
// scrolling. A signal that arrives too late to act on is not worth computing.
// If a second observation ever wants this slot, the answer is no — build the
// feed on Health where the others already live.
//
// This file also carries the plumbing every screen in this folder shares —
// navigation, the repo handle, and the three ways a value arrives from the
// data layer. They live here rather than in a fourth file because there are
// only three of them and they are read together.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../compute/profile.dart' show Profile, stepCalories;
import '../../data/day_label.dart' show todayLabel;
import '../../data/db.dart' show DbRebuild;
import '../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../../theme/theme_switcher.dart' show themedRoute;
import '../activity/day_strain.dart' show DayStrainDetail;
import '../ui2.dart';
import '../profile/settings.dart' show MoreSettings;
import 'day_timeline.dart' show DayGraph, DayTimelineScreen, dayGraph;
import 'metric_detail.dart';
import 'nutrition_screen.dart' show DayUpkeep, showMaintenance;
import 'week_card.dart' show WeekCard;
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
void go(BuildContext c, Widget w) =>
    Navigator.of(c).push(themedRoute((_) => w, name: w.runtimeType.toString()));

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

/// The pull-down gesture on every tab: sync the band and the phone, wait for
/// the derive, then [reload] the screen. A one-line note if the band was not
/// connected. Without an [AppState] (a golden) it only reloads.
Future<void> pullToRefresh(
  BuildContext c,
  Future<void> Function() reload,
) async {
  AppState? app;
  try {
    app = c.read<AppState>();
  } catch (_) {
    app = null;
  }
  final note = await app?.pullRefresh();
  await reload();
  if (note != null && c.mounted) {
    ScaffoldMessenger.maybeOf(c)?.showSnackBar(SnackBar(content: Text(note)));
  }
}

/// The user's profile (age, height, weight, sex), or null in a golden.
Profile? profileOf(BuildContext c) {
  try {
    return Profile.fromMap(c.watch<AppState>().user);
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

/// Whether a live workout is open, or false in a golden. `select`, not
/// `watch`: AppState ticks at ~1 Hz while a session is live, and this screen
/// only cares about the bool flipping. The bare-day card branches on it — see
/// [workoutHoldCard].
/// The band's last reported battery and charging state, or null with no
/// reading (or no [AppState] above, as in goldens).
(double, bool)? bandBatteryOf(BuildContext c) {
  try {
    final b = c.select<AppState, (double?, bool?)>(
      (a) => (a.device.batteryPct, a.device.charging),
    );
    return b.$1 == null ? null : (b.$1!, b.$2 ?? false);
  } catch (_) {
    return null;
  }
}

bool workoutLiveOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.activeWorkout != null);
  } catch (_) {
    return false;
  }
}

/// Whether the band is actively sending data right now, or false in a
/// golden. Same shape and same reasoning as [workoutLiveOf] — `select`
/// because this only cares about the bool flipping, not AppState's ~1 Hz
/// heartbeat.
bool syncingNowOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.syncingNow);
  } catch (_) {
    return false;
  }
}

/// Whether a derive job is running or about to (the backlog just landed and
/// today's numbers are being worked out), or false in a golden.
bool derivingOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.deriving || a.derivePending);
  } catch (_) {
    return false;
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
String? stepSensorLabel(Metric m, [AppLocalizations? l]) {
  final used = m.inputsUsed;
  final strap =
      used.contains('band_pedometer_100hz') ||
      used.contains('band_step_counter');
  final phone = used.contains('phone_pedometer');
  if (strap && phone) return l?.homeStepSensorStrapPhone ?? 'Strap + phone';
  if (strap) return l?.homeStepSensorStrap ?? 'Strap';
  if (phone) return l?.homeStepSensorPhone ?? 'Phone';
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
/// that night while steps and active energy describe today.
///
/// WHAT THIS IS STILL FOR, now that no screen prints its numbers as today's
/// (see [overnightMetric]): naming WHICH NIGHT, and opening it. A screen that
/// is explicitly about a dated night — Sleep, with a day stepper over it —
/// wants this, because the night it should open is the last one that scored,
/// not a calendar day with no sleep in it. Every screen resolves that night
/// HERE so Home, Readiness, Sleep and Health cannot each answer "which night?"
/// differently.
String? heldOverNightOf(Map<String, dynamic> today) {
  final st = today['status'];
  if (st is! Map) return null;
  return st['showing_prior_overnight'] == true
      ? st['overnight_day']?.toString()
      : null;
}

/// Why today has no overnight figures, or null when it has its own.
///
/// Two absences that are not interchangeable, both read straight off
/// `status.overnight_state`:
///
///   * `building` — today's records HAVE reached the app and the night has not
///     finished being worked out. It resolves on its own and there is nothing
///     to ask anyone to do.
///   * anything else — nothing from last night has arrived. Syncing is the
///     thing that changes it.
///
/// Prose, not a `key:arg` token, so `whyFromNote` passes it through as the
/// sentence it already is.
String? staleOvernightNote(Map<String, dynamic> today, [AppLocalizations? l]) {
  if (heldOverNightOf(today) == null) return null;
  final st = today['status'];
  return (st is Map ? st['overnight_state']?.toString() : null) == 'building'
      ? l?.homeOvernightBuilding ?? 'Last night is still being worked out.'
      : l?.homeOvernightNothingYet ??
            'Nothing from last night has reached the app yet.';
}

/// An overnight envelope, REFUSED when the night behind it is not today's.
///
/// This reverses a decision that was made deliberately and was wrong on a
/// phone. `getToday` serves the last scored night whenever today's has not
/// settled, and the old argument for printing it was that the number is real
/// and the most recent one there is, so naming its night is enough. It is not:
/// a figure in the today slot is read as today's before anything under it is,
/// so a morning the strap was never worn showed last week's sleep as this
/// morning's, and the caption saying otherwise sat below three rings nobody
/// reads past. A stale number is a worse answer than an honest gap.
///
/// So the numbers stop here and the reason travels in their place. The night
/// itself is not lost — [heldOverNightOf] still names it, and the screens that
/// are ABOUT a dated night still open it.
Metric overnightMetric(
  Map<String, dynamic> today,
  Object? raw, [
  AppLocalizations? l,
]) {
  final why = staleOvernightNote(today, l);
  return why == null ? metricOf(raw) : Metric(note: why);
}

/// A scalar lifted out of an object-valued envelope, wearing that envelope's
/// honesty (tier, confidence, note) so `StatusCard.forMetric` still works on
/// it.
Metric envMetric(Object? raw, num? scalar, {String? unit}) {
  final m = raw is Map
      ? raw.cast<String, dynamic>()
      : const <String, dynamic>{};
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
String axisDay(
  int? epochSec, {
  String todayWord = 'Today',
  String unitWord = 'days',
}) {
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
    DateTime.fromMillisecondsSinceEpoch(epochSec * 1000),
    DateTime.now(),
  );
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
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

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
StatusCard? dbRebuiltCard(DbRebuild? r, [AppLocalizations? l]) {
  if (r == null) return null;
  final saved = r.salvaged.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final lost = r.salvaged.entries.where((e) => e.value == 0).toList();
  final savedList = saved
      .map((e) => '${e.key} ${thousands(e.value)}')
      .join(' · ');
  final lostList = lost.map((e) => e.key).join(' · ');
  return StatusCard(
    l?.homeDbRebuiltTitle ?? 'Your database was rebuilt to start the app',
    '${r.cause}\n\n'
    '${saved.isEmpty ? (l?.homeDbRebuiltNothingRecovered ?? 'Nothing could be read back.') : (l?.homeDbRebuiltRecovered(savedList) ?? 'Recovered: $savedList.')}'
    '${lost.isEmpty ? '' : ' ${l?.homeDbRebuiltEmpty(lostList) ?? 'Empty: $lostList.'}'}'
    '\n\n${l?.homeDbRebuiltKept(r.quarantinePath) ?? 'The original file is kept at ${r.quarantinePath} — nothing was deleted.'}',
    icon: LucideIcons.databaseBackup,
  );
}

/// The bare day during a live workout — missing COMPUTE, not data. A live
/// session holds derivation (`DeriveScheduler.setWorkoutActive`), so nothing
/// lands in `day_result` until it ends: the band keeps recording, the sync
/// keeps landing records, and "Sync the band" is a false answer — the sync
/// completes and changes nothing on this screen. The true remedy is finishing
/// the session, and its bar is pinned right below this card, so the card
/// points there rather than duplicating the door.
StatusCard workoutHoldCard([AppLocalizations? l]) => StatusCard(
  l?.homeWorkoutHoldTitle ?? 'A workout is still running',
  l?.homeWorkoutHoldBody ??
      'Today is on hold while a workout is live: the band keeps recording, '
          'but the numbers are computed once the session ends. Finish the workout '
          'from the bar below and today fills in — syncing will not.',
  icon: LucideIcons.timer,
);

StatusCard? staleInsightsCard(
  Map<String, dynamic>? reason,
  VoidCallback? onSync, [
  AppLocalizations? l,
]) {
  final s = reason;
  if (s == null) return null;
  final built = s['built_for_day']?.toString();
  return StatusCard(
    'Cross-day insights need an update',
    switch (s['kind']) {
      'algo_version' =>
        l?.homeInsightsRebuildingAlgoVersion ??
            'How these are computed changed with the last update.',
      'stale' =>
        built == null || built.isEmpty
            ? (l?.homeInsightsStaleOverWeek ??
                  'The last rollup was built over a week ago, which is too old to stand behind.')
            : (l?.homeInsightsStaleOnDay(prettyDay(built, l)) ??
                  'The last rollup was built on ${prettyDay(built, l)}, which is too old to stand behind.'),
      'needs_history' =>
        'At least 3 usable days are needed. Individual insights have their own history requirements.',
      'failed' =>
        'The last local calculation failed. Retry from your saved measurements.',
      'missing' =>
        'No local rollup is available yet. Rebuild from your saved measurements.',
      _ =>
        l?.homeInsightsNoVersionStamp ??
            'The stored rollup carries no version stamp.',
    },
    fix: onSync == null ? '' : 'Rebuild insights',
    icon: LucideIcons.refreshCw,
    onFix: onSync,
  );
}

// ── formatting ──

String hm(num? minutes) {
  if (minutes == null) return '';
  final m = minutes.round();
  return m < 60
      ? '${m}m'
      : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
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
];
const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String monthName(int month, AppLocalizations? l) {
  if (l == null) return _months[month - 1];
  return [
    l.homeMonthJanuary,
    l.homeMonthFebruary,
    l.homeMonthMarch,
    l.homeMonthApril,
    l.homeMonthMay,
    l.homeMonthJune,
    l.homeMonthJuly,
    l.homeMonthAugust,
    l.homeMonthSeptember,
    l.homeMonthOctober,
    l.homeMonthNovember,
    l.homeMonthDecember,
  ][month - 1];
}

const _monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Abbreviated month for "Thu 4 Sep" date chips.
String monthShortName(int month, AppLocalizations? l) {
  if (l == null) return _monthsShort[month - 1];
  return [
    l.homeMonthJanuaryShort,
    l.homeMonthFebruaryShort,
    l.homeMonthMarchShort,
    l.homeMonthAprilShort,
    l.homeMonthMayShort,
    l.homeMonthJuneShort,
    l.homeMonthJulyShort,
    l.homeMonthAugustShort,
    l.homeMonthSeptemberShort,
    l.homeMonthOctoberShort,
    l.homeMonthNovemberShort,
    l.homeMonthDecemberShort,
  ][month - 1];
}

String _weekdayName(int weekday, AppLocalizations? l) {
  if (l == null) return _weekdays[weekday - 1];
  return [
    l.homeWeekdayMonday,
    l.homeWeekdayTuesday,
    l.homeWeekdayWednesday,
    l.homeWeekdayThursday,
    l.homeWeekdayFriday,
    l.homeWeekdaySaturday,
    l.homeWeekdaySunday,
  ][weekday - 1];
}

const _weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Abbreviated weekday for `DateTime.weekday` (1 = Monday), e.g. "Thu 4 Sep"
/// date chips. Reuses the `wellness*` short-day keys — they're already
/// translated everywhere and mean the same three letters here.
String weekdayShortName(int weekday, AppLocalizations? l) {
  if (l == null) return _weekdaysShort[weekday - 1];
  return [
    l.wellnessMon,
    l.wellnessTue,
    l.wellnessWed,
    l.wellnessThu,
    l.wellnessFri,
    l.wellnessSat,
    l.wellnessSun,
  ][weekday - 1];
}

/// 'YYYY-MM-DD' → "Saturday, 20 May".
String prettyDay(String? dayId, [AppLocalizations? l]) {
  final d = dayId == null ? null : DateTime.tryParse(dayId);
  if (d == null) return '';
  return '${_weekdayName(d.weekday, l)}, ${d.day} ${monthName(d.month, l)}';
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
///
/// THE CUT-OFFS ARE THE SCORE'S OWN QUANTILES, NOT ROUND NUMBERS (issue #250).
/// `readinessComposite` is `100 / (1 + exp(-z̄))` with no scale parameter, and
/// z̄ is a weight-renormalised mean of per-input robust z's — each ~N(0,1)
/// against that person's OWN baseline. So the score is a percentile of self
/// whose CENTRE IS 50 BY CONSTRUCTION: a night exactly at personal median
/// scores 50, and the old 40/60/80 bands filed that median night under "Take it
/// easy". Roughly a quarter of all nights fell under "Rest today" and 1.7 %
/// could ever reach "Good to go" — it needed every input ~1.4 SD above median
/// at once. A warning that fires on the typical night is not a warning.
///
/// z̄'s own SD is NOT 1: averaging the disclosed weights (.40/.30/.20/.10,
/// renormalised over present inputs) gives σ ≈ 0.55-0.60 if the inputs were
/// independent, ~0.70 at the positive correlation HRV/RHR/RR actually have.
/// σ ≈ 0.65 is the middle of that, and the cut-offs below are its quantiles:
///
///   score = 100 / (1 + exp(-0.65 · Φ⁻¹(p)))
///     p=.05 → 26   p=.20 → 37   p=.75 → 61
///
/// which lands 5 % of nights on "Rest today", 15 % on "Take it easy", 55 % on
/// "Steady" and 25 % on "Good to go". The median night is now the neutral band,
/// which is the whole point. Under the old cut-offs the same distribution read
/// 27 / 47 / 25 / 2.
///
/// σ is the one soft number here — it is a property of how correlated a given
/// person's four inputs are, and it moves with how many of them are present.
/// Re-derive it from a real `metric_series` readiness distribution when there
/// is one long enough to measure; do not nudge the cut-offs by feel.
({String label, Color color, int tier}) readinessBand(
  num? v, [
  AppLocalizations? l,
]) {
  if (v == null) {
    return (
      label: l?.homeReadinessNotScored ?? 'Not scored',
      color: C.n400,
      tier: -1,
    );
  }
  if (v >= 61) {
    return (
      label: l?.homeReadinessGoodToGo ?? 'Good to go',
      color: C.green,
      tier: 3,
    );
  }
  if (v >= 37) {
    return (label: l?.homeReadinessSteady ?? 'Steady', color: C.green, tier: 2);
  }
  if (v >= 26) {
    return (
      label: l?.homeReadinessTakeItEasy ?? 'Take it easy',
      color: C.yellow,
      tier: 1,
    );
  }
  return (
    label: l?.homeReadinessRestToday ?? 'Rest today',
    color: C.red,
    tier: 0,
  );
}

/// Glass-box driver keys are the pipeline's own short names.
const driverLabels = {
  'hrv': 'HRV',
  'rhr': 'Resting heart rate',
  'resp': 'Breathing rate',
  'temp': 'Skin temperature',
  'sleep': 'Sleep',
};

/// A pipeline key the map does not cover is HUMANISED, never printed raw. The
/// glass-box emits whatever inputs the composite used, so a new one used to
/// surface on Home as `resp_rate_slope`.
String driverLabel(Object? key, [AppLocalizations? l]) {
  final k = key?.toString() ?? '';
  final known = switch (k) {
    'hrv' => l?.homeDriverHrv ?? driverLabels['hrv'],
    'rhr' => l?.homeDriverRhr ?? driverLabels['rhr'],
    'resp' => l?.homeDriverResp ?? driverLabels['resp'],
    'temp' => l?.homeDriverTemp ?? driverLabels['temp'],
    'sleep' => driverLabels['sleep'],
    _ => null,
  };
  if (known != null) return known;
  if (k.isEmpty) return '';
  final words = k.replaceAll('_', ' ').trim();
  return words.isEmpty ? '' : '${words[0].toUpperCase()}${words.substring(1)}';
}

/// The three rings, and what each one does when its metric is not there.
///
/// A ring is a shape that always renders, and this data frequently is not
/// there: readiness exists on 71 % of days and needs four prior nights before
/// it exists at all. So the absent states ARE the design here rather than an
/// error branch bolted onto three pretty circles. Each ring has four:
///
///   * MEASURED — an arc, the number, and what the number is out of.
///   * CALIBRATING — a muted arc at nights-banked over nights-needed, with the
///     count under it. Visibly progress towards a real ring; an arc at zero
///     would read as a bad score, which is the lie this exists to avoid. It is
///     drawn only for a `need_baseline` note, the one absence that IS progress.
///   * MEASURED, UNSCALED — sleep with no computed need behind it. The number
///     is real and the fraction is not known, so the track draws empty and the
///     line under it says there is no target yet. Filling it against the
///     hardcoded 480 would be inventing the user's sleep need.
///   * ABSENT — the track alone, the absence in words where the number goes,
///     and the PIPELINE'S OWN reason on a row under the trio which is also the
///     door into the screen that can say more. Three [StatusCard]s is not a
///     home screen; a ring with nothing in it and no reason is worse than one.
///
/// Every ring opens something: recovery → [ReadinessDetail], strain →
/// [DayStrainDetail], sleep → [SleepDetail].
class RingTrio extends StatelessWidget {
  final HomeData d;

  /// Push the ring's own screen. Null in a gallery, where there is no navigator
  /// worth pushing onto.
  final void Function(HomeRingKind)? onOpen;

  const RingTrio({super.key, required this.d, this.onOpen});

  /// Whether ANY of the three has something to draw. When none do, the screen
  /// owes the user one written absence, not three empty circles.
  static bool has(HomeData d) =>
      HomeRingKind.values.any((k) => _ringOf(k, d, null).why == null);

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final rec = _ringOf(HomeRingKind.recovery, d, l);
    final strain = _ringOf(HomeRingKind.strain, d, l);
    final sleep = _ringOf(HomeRingKind.sleep, d, l);
    final aim = d.strainTarget?['value'];
    return Column(
      children: [
        _RecoveryCard(
          rec,
          hrv: d.hrv.value,
          rhr: d.rhr.value,
          onTap: _open(HomeRingKind.recovery),
        ),
        const SizedBox(height: S.x3),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MiniCard(sleep, onTap: _open(HomeRingKind.sleep)),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: _MiniCard(
                  strain,
                  sub: strain.measured && aim is num
                      ? ((d.strain.value ?? 0) >= aim
                            ? 'Target ${aim.toStringAsFixed(1)} · reached'
                            : 'Aim for about ${aim.round()} today')
                      : null,
                  onTap: _open(HomeRingKind.strain),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  VoidCallback? _open(HomeRingKind k) {
    final f = onOpen;
    return f == null ? null : () => f(k);
  }
}

/// Which ring. The three the app can stand behind on a home screen: what the
/// night gave back, what the day has cost, and what the night was made of.
enum HomeRingKind { recovery, strain, sleep }

/// One ring's resolved state — the only place a metric becomes a shape.
class _RingState {
  final HomeRingKind kind;
  final String label, value, sub;
  final IconData icon;
  final Color color;

  /// What to sweep, 0…1 — null when there is nothing honest to sweep.
  final double? frac;

  /// The arc is calibration progress, not the metric, and is drawn muted.
  final bool calibrating;

  /// Nights banked / nights needed, set only while [calibrating] — the
  /// dashed ring divides itself into exactly [need] beads and fills [have]
  /// of them, rather than approximating that count from [frac].
  final int? have, need;

  /// The absence's reason, as the pipeline gave it. Non-null only when the
  /// ring is [absent].
  final String? why;

  const _RingState(
    this.kind,
    this.label,
    this.icon,
    this.color, {
    required this.value,
    this.sub = '',
    this.frac,
    this.calibrating = false,
    this.have,
    this.need,
    this.why,
  });

  /// A number the ring is actually reporting. Calibration is progress, not a
  /// reading, so it is not one.
  bool get measured => why == null && !calibrating;

  Color arc(P p) => calibrating ? p.ink3 : p.on(color);
  Color ink(P p) => measured ? p.on(color) : p.ink3;

  String get spoken => [
    label,
    measured ? value : value.toLowerCase(),
    if (sub.isNotEmpty) sub,
    ?why,
  ].join('. ');
}

_RingState _ringOf(HomeRingKind k, HomeData d, AppLocalizations? l) {
  switch (k) {
    case HomeRingKind.recovery:
      final v = d.readiness.value;
      final band = readinessBand(v, l);
      return v == null
          ? _gap(
              k,
              l?.homeRingRecovery ?? 'Recovery',
              LucideIcons.batteryCharging,
              C.green,
              d.readiness,
              l?.homeReadinessNotScored ?? 'Not scored',
              l,
            )
          : _RingState(
              k,
              l?.homeRingRecovery ?? 'Recovery',
              LucideIcons.batteryCharging,
              band.color,
              value: '${v.round()}',
              sub: band.label,
              frac: v / 100,
            );
    case HomeRingKind.strain:
      final v = d.strain.value;
      // 0–21 is the scale's own ceiling, not a target invented here.
      return v == null
          ? _gap(
              k,
              l?.homeRingStrain ?? 'Strain',
              LucideIcons.zap,
              C.strain,
              d.strain,
              l?.homeRingNoStrain ?? 'No strain',
              l,
              unit: 'days',
            )
          : _RingState(
              k,
              l?.homeRingStrain ?? 'Strain',
              LucideIcons.zap,
              C.strain,
              value: v.toStringAsFixed(1),
              sub: l?.homeStrainOf21 ?? 'of 21',
              frac: v / 21,
            );
    case HomeRingKind.sleep:
      final v = d.sleepMin.value;
      final need = d.sleepNeedMin.value;
      return v == null
          ? _gap(
              k,
              l?.homeRingSleep ?? 'Sleep',
              LucideIcons.moon,
              C.sleep,
              d.sleepMin,
              l?.homeRingNoSleep ?? 'No sleep',
              l,
              fallbackWhy:
                  l?.homeSleepGapFallback ??
                  'No night long enough to score was recorded.',
            )
          : _RingState(
              k,
              l?.homeRingSleep ?? 'Sleep',
              LucideIcons.moon,
              C.sleep,
              value: hm(v),
              // No computed need means no denominator. The hardcoded 480 in
              // the sleep bundle is not this user's need and must never be
              // shown as one, so the ring stays open and says so.
              sub: need == null
                  ? (l?.homeSleepNoTarget ?? 'No target yet')
                  : (l?.homeOfSpan(hm(need)) ?? 'of ${hm(need)}'),
              frac: need == null || need <= 0 ? null : v / need,
            );
  }
}

/// The absent half: calibrating when the note says the gate is a baseline
/// still filling, otherwise the absence and its reason.
_RingState _gap(
  HomeRingKind k,
  String label,
  IconData icon,
  Color color,
  Metric m,
  String word,
  AppLocalizations? l, {
  String unit = 'nights',
  String fallbackWhy = '',
}) {
  final counts = baselineCountsFromNote(m.note);
  if (counts != null) {
    return _RingState(
      k,
      label,
      icon,
      color,
      value: l?.homeCalibrating ?? 'Calibrating',
      sub: unit == 'days'
          ? (l?.homeCalibratingDays(counts.have, counts.need) ??
                '${counts.have} of ${counts.need} days')
          : (l?.homeCalibratingNights(counts.have, counts.need) ??
                '${counts.have} of ${counts.need} nights'),
      frac: (counts.have / counts.need).clamp(0.0, 1.0),
      calibrating: true,
      have: counts.have,
      need: counts.need,
    );
  }
  return _RingState(
    k,
    label,
    icon,
    color,
    value: word,
    // THE PIPELINE'S REASON FIRST. A sentence written here by someone who
    // never saw the day is the fallback, and where there is neither the ring
    // says it does not know rather than guessing a cause.
    why:
        whyFromNote(m.note, unit: unit) ??
        (fallbackWhy.isNotEmpty
            ? fallbackWhy
            : (l?.homeGapNoReason ??
                  'Nothing recorded says why this is missing.')),
  );
}

/// The hero: recovery as a ring with the score inside it, the verdict beside
/// it, and the two readings it is mostly made of under the verdict. When
/// recovery is absent the ring is an empty track and the reason takes the
/// place of the verdict.
class _RecoveryCard extends StatelessWidget {
  final _RingState r;
  final num? hrv, rhr;
  final VoidCallback? onTap;

  const _RecoveryCard(this.r, {this.hrv, this.rhr, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      onTap: onTap,
      semanticLabel: r.spoken,
      pad: const EdgeInsets.all(S.x5),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: r.calibrating
                      ? DashedRing(
                          r.frac ?? 0,
                          r.arc(p),
                          p.track,
                          stroke: 11,
                          segments: r.need ?? 24,
                        )
                      : Ring(
                          r.frac ?? 0,
                          r.arc(p),
                          p.track,
                          stroke: 11,
                          t: animate(c, 1),
                          solid: r.measured,
                        ),
                ),
                if (r.measured)
                  Padding(
                    padding: const EdgeInsets.all(S.x5),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(r.value, style: F.n34.copyWith(color: p.ink)),
                    ),
                  )
                else
                  Icon(r.icon, size: 26, color: p.ink3),
              ],
            ),
          ),
          const SizedBox(width: S.x5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label, style: F.cap.copyWith(color: p.ink3)),
                const SizedBox(height: 2),
                Text(
                  r.measured ? r.sub : r.value,
                  style: F.t2.copyWith(color: r.measured ? r.ink(p) : p.ink2),
                ),
                if (!r.measured && r.sub.isNotEmpty)
                  Text(r.sub, style: F.cap.copyWith(color: p.ink3)),
                if (r.why != null)
                  Text(
                    r.why!,
                    style: F.cap.copyWith(color: p.ink3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (hrv != null || rhr != null) ...[
                  const SizedBox(height: S.x2),
                  if (hrv != null)
                    Text(
                      'HRV ${hrv!.round()} ms',
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                  if (rhr != null)
                    Text(
                      'Resting ${rhr!.round()} bpm',
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sleep and strain: one number, a bar for how far along it is, and one short
/// line under it. An absent metric keeps its card and says why in that line.
class _MiniCard extends StatelessWidget {
  final _RingState r;

  /// Replaces the ring state's own caption when the screen has a better one.
  final String? sub;
  final VoidCallback? onTap;

  const _MiniCard(this.r, {this.sub, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final caption = r.why ?? sub ?? r.sub;
    return Surface(
      onTap: onTap,
      semanticLabel: r.spoken,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(r.icon, size: 16, color: r.ink(p)),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  r.label,
                  style: F.cap.copyWith(color: p.ink2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Text(
            r.value,
            style: r.measured
                ? F.n24.copyWith(color: p.ink)
                : F.body.copyWith(color: p.ink2),
          ),
          const SizedBox(height: S.x3),
          ClipRRect(
            borderRadius: R.rPill,
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: p.track)),
                  FractionallySizedBox(
                    widthFactor: (r.frac ?? 0).clamp(0.0, 1.0),
                    child: ColoredBox(
                      color: r.arc(p),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: S.x2),
            Text(
              caption,
              style: F.over.copyWith(color: p.ink3),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════ the screen ═══════════════════

class HomeData {
  final String? name;
  final String? dayId;
  final Metric readiness;
  final List<Map<String, dynamic>> drivers;
  final Metric sleepMin, rhr, hrv, steps, calories, caloriesTotal;

  /// Today's heart rate, one slot per minute, for the card on this screen.
  final DayGraph graph;

  /// Estimated kcal spent walking today, from steps, height and weight. Shown
  /// beside the steps and NEVER added to the calorie totals. Null when the
  /// profile has no height/weight or no steps were counted.
  final double? walkingKcal;

  /// Today's maintenance so far, as a floor: BMR + step calories + 10% of the
  /// food logged today. Null without age, height and weight.
  /// Today's maintenance inputs; null before the profile is read.
  final DayUpkeep? upkeep;

  /// The day's 0–21 strain, read from the same `getToday` bundle the Workout
  /// tab reads. Nothing on this screen computes it.
  final Metric strain;

  final int stepGoal;
  final Metric sleepNeedMin;
  final Metric bedtime;
  final Map<String, dynamic>? strainTarget;

  /// Non-null when the cross-day rollup was withheld rather than absent — see
  /// [staleInsightsCard]. Drivers, sleep need and bedtime are all empty in that
  /// case, and the screen owes the user the reason.
  final Map<String, dynamic>? insightsStale;

  /// The last night that scored, when that is NOT today's — so the screen can
  /// say WHERE THE DATA STOPS on a day it has nothing of its own.
  ///
  /// It is no longer where readiness, sleep or resting heart rate come from:
  /// [overnightMetric] refuses those at the loader, and this is what is left
  /// of the held-over night once its numbers are gone. Its one job on this
  /// screen is the sentence in the nothing-today card — "the last night this
  /// app scored was Saturday" is a fact about coverage, not a reading dressed
  /// as one.
  final String? heldOverNight;

  /// The illness watch's own state — 'green' / 'amber' / 'red', or null before
  /// it has the 7 nights of baseline it needs. Home renders it only when it is
  /// amber or red; see the exception noted at the top of this file.
  final String? illnessState;

  /// The night the watch is ABOUT, and how far that night sat from this user's
  /// own baseline. `z` belongs to the latest night alone and can be negative
  /// while the run is still up, so the copy says which direction rather than
  /// implying the run reversed.
  final String? illnessDay;
  final double? illnessZ;

  const HomeData({
    this.name,
    this.dayId,
    this.readiness = Metric.empty,
    this.drivers = const [],
    this.sleepMin = Metric.empty,
    this.rhr = Metric.empty,
    this.hrv = Metric.empty,
    this.graph = const DayGraph(),
    this.steps = Metric.empty,
    this.calories = Metric.empty,
    this.caloriesTotal = Metric.empty,
    this.walkingKcal,
    this.upkeep,
    this.strain = Metric.empty,
    this.stepGoal = kDefaultStepGoal,
    this.sleepNeedMin = Metric.empty,
    this.bedtime = Metric.empty,
    this.strainTarget,
    this.heldOverNight,
    this.illnessState,
    this.illnessDay,
    this.illnessZ,
    this.insightsStale,
  });

  /// The three illness fields, replaced together. Test-facing sugar, and they
  /// travel as a set on purpose — they are read as one envelope, and setting
  /// one without the others describes a state the pipeline cannot produce.
  HomeData copyOrIllness(String? state, String? day, double? z) => HomeData(
    name: name,
    dayId: dayId,
    readiness: readiness,
    drivers: drivers,
    sleepMin: sleepMin,
    rhr: rhr,
    hrv: hrv,
    graph: graph,
    steps: steps,
    calories: calories,
    caloriesTotal: caloriesTotal,
    walkingKcal: walkingKcal,
    upkeep: upkeep,
    strain: strain,
    stepGoal: stepGoal,
    sleepNeedMin: sleepNeedMin,
    bedtime: bedtime,
    strainTarget: strainTarget,
    heldOverNight: heldOverNight,
    illnessState: state,
    illnessDay: day,
    illnessZ: z,
    insightsStale: insightsStale,
  );

  static Future<HomeData> load(
    LocalRepository repo, [
    AppLocalizations? l,
  ]) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final profile = await repo.getProfile();
    final upkeep = await DayUpkeep.read(
      repo,
      todayLabel(),
      Profile.fromMap(profile),
    );

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

    // Same envelope Health reads. The watch runs on NOCTURNAL RESTING HEART
    // RATE ALONE — it has never been given a temperature series — so nothing
    // here may imply a second signal.
    final illness = today['illness'];

    final hrvBlock = today['hrv'];
    final dayId = (today['status'] as Map?)?['today_day']?.toString();
    var graph = const DayGraph();
    if (dayId != null) {
      try {
        graph = dayGraph(await repo.getDayTimeline(dayId));
      } catch (_) {
        // The card is optional; the rest of the screen is not.
      }
    }

    return HomeData(
      graph: graph,
      hrv: overnightMetric(
        today,
        hrvBlock is Map
            ? {...hrvBlock.cast<String, dynamic>(), 'value': hrvBlock['rmssd']}
            : null,
        l,
      ),
      name: profile['name']?.toString(),
      dayId: dayId,
      heldOverNight: heldOver,
      illnessState: illness is Map ? illness['state']?.toString() : null,
      illnessDay: illness is Map ? illness['date']?.toString() : null,
      illnessZ: illness is Map ? (illness['z'] as num?)?.toDouble() : null,
      // The three that come off the OVERNIGHT block. Gated, so a night that
      // is not today's cannot arrive wearing today's clothes — see
      // [overnightMetric]. Steps, active energy and strain are today's own and
      // are read straight.
      readiness: overnightMetric(today, d('readiness'), l),
      drivers: [
        for (final e in (gbDrivers is List ? gbDrivers : const []))
          if (e is Map) e.cast<String, dynamic>(),
      ],
      strain: metricOf(d('strain')),
      sleepMin: overnightMetric(today, s('duration_min'), l),
      rhr: overnightMetric(today, d('resting_hr'), l),
      steps: metricOf(d('steps')),
      calories: metricOf(d('calories')),
      caloriesTotal: metricOf(d('calories_total')),
      walkingKcal: upkeep.parts?.steps ?? stepCalories(upkeep.walkedSteps, upkeep.profile.weightKg),
      upkeep: upkeep,
      stepGoal: (today['step_goal'] as num?)?.toInt() ?? kDefaultStepGoal,
      // sleep_coach.need is the COMPUTED need. `sleep.need_min` is a hardcoded
      // 480 and must never be shown as "your sleep need".
      sleepNeedMin: envMetric(
        needEnv,
        needSec == null ? null : needSec / 60,
        unit: 'min',
      ),
      bedtime: envMetric(
        bedEnv,
        envValue(bedEnv)?['bedtime_min_of_day'] as num?,
      ),
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

  /// Whether a workout is live, injected only by tests/goldens — production
  /// reads it off AppState via [workoutLiveOf].
  final bool? workoutLive;

  const HomeScreen({super.key, this.data, this.hour, this.workoutLive});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RevisionReload {
  HomeData? _d;
  bool _loading = true;

  /// The load THREW. Distinct from "there is nothing yet": a decode or a locked
  /// database is a read problem, and telling a user with three months of
  /// history that their band has never produced data is the wrong answer to it.
  bool _failed = false;

  /// Set the moment "Sync the band" is tapped, cleared once real progress has
  /// a signal of its own (`syncingNow`) or after [_tapGrace] with nothing —
  /// the bridge over the gap between the tap and the first record landing,
  /// where neither `busy` (skipped entirely on the common fast-reclaim path)
  /// nor `syncingNow` has moved yet and the button would otherwise look inert.
  bool _syncTapped = false;
  Timer? _syncTapTimer;
  static const _tapGrace = Duration(seconds: 20);

  void _tapSync(VoidCallback sync) {
    sync();
    setState(() => _syncTapped = true);
    _syncTapTimer?.cancel();
    _syncTapTimer = Timer(_tapGrace, () {
      if (mounted) setState(() => _syncTapped = false);
    });
  }

  @override
  void dispose() {
    _syncTapTimer?.cancel();
    super.dispose();
  }

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

  /// Handed its data (golden, gallery) — the screen just renders what it has.
  @override
  bool get revisionReloads => widget.data == null;

  /// Home used to load once post-frame and never listen, so the "Sync the
  /// band" button it renders could not change what the screen showed: the
  /// offload landed, the derive ran, and Home kept saying "Nothing derived
  /// yet" until the app was relaunched.
  @override
  void reload() => _load();

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final t = beginRead(#home);
    try {
      final d = await HomeData.load(repo, AppLocalizations.of(context));
      if (stillNewest(#home, t)) {
        setState(() => (_d = d, _loading = false, _failed = false));
      }
    } catch (_) {
      if (stillNewest(#home, t)) {
        setState(() => (_loading = false, _failed = true));
      }
    }
  }

  /// The "nothing derived yet" card, upgraded with the one thing it used to
  /// withhold: whether anything is actually happening right now. Tapping Sync
  /// used to leave this card looking identical whether the band was mid-drain
  /// or the tap had silently gone nowhere — "I am not sure if it is actually
  /// syncing or not, no progress, no cue" was exactly that gap. `syncingNow` is
  /// the one signal that is honest across BOTH session paths (a fresh connect
  /// sets `busy`; the common fast-reclaim-from-background path never does), so
  /// it is what ends "connecting", not `busy`. `deriving`/`derivePending` catch
  /// the LAST mile — the backlog landed, `syncingNow` has gone quiet again, but
  /// this screen is still bare because the heavy derive it depends on hasn't
  /// finished. Without that phase the card would flash back to a bare "Nothing
  /// derived yet" for the minute or so a full sleep-stage + spectra pass takes.
  /// The syncing / analyzing / connecting phase card — valid whether or not
  /// [HomeData] itself has loaded yet, which is why it does not take one.
  /// Shared by the fully-bare first-run path (`d == null`) and the
  /// derived-but-empty bare-day path, so a first-run tap of "Sync the band"
  /// gets the same connecting/syncing feedback as every other one. Returns
  /// null when none of the three phases apply, so the caller falls through
  /// to its own "nothing yet" copy.
  Widget? _phaseStatusCard(BuildContext c, AppLocalizations? l) {
    final syncing = syncingNowOf(c);
    final deriving = derivingOf(c);
    // The tap latch is otherwise cleared only by its 20s grace timer — if
    // real progress lands before that timer fires, clear it here too so the
    // UI does not bounce back to "Connecting" once syncing/deriving goes
    // quiet again.
    if ((syncing || deriving) && _syncTapped) {
      _syncTapped = false;
      _syncTapTimer?.cancel();
    }
    final spinner = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: P.of(c).ink3),
    );

    if (syncing) {
      return StatusCard(
        l?.homeSyncingTitle ?? 'Syncing with your band',
        l?.homeSyncingBody ??
            'Pulling data now — this can take a few minutes '
                'on a full backlog.',
        leading: spinner,
      );
    }
    if (deriving) {
      return StatusCard(
        l?.homeAnalyzingTitle ?? 'Crunching last night\'s numbers',
        l?.homeAnalyzingBody ??
            'The data is in — sleep, recovery and strain '
                'are next.',
        leading: spinner,
      );
    }
    if (_syncTapped) {
      return StatusCard(
        l?.homeConnectingTitle ?? 'Connecting to your band',
        l?.homeConnectingBody ?? 'Hang on — this usually takes a few seconds.',
        leading: spinner,
      );
    }
    return null;
  }

  Widget _bareStatusCard(BuildContext c, HomeData d, AppLocalizations? l) {
    final phase = _phaseStatusCard(c, l);
    if (phase != null) return phase;

    final sync = syncOf(c);
    return StatusCard(
      d.heldOverNight == null
          ? (l?.homeNothingDerivedTitle ?? 'Nothing derived yet')
          : (l?.homeNothingTodayTitle ?? 'Nothing recorded for today'),
      d.heldOverNight == null
          ? (l?.homeNothingDerivedBody ?? 'No band recordings processed yet.')
          : (l?.homeNothingTodayBody(prettyDay(d.heldOverNight, l)) ??
                'The last night this app scored was '
                    '${prettyDay(d.heldOverNight, l)}. Nothing has reached it since.'),
      fix: sync == null ? '' : (l?.homeSyncBand ?? 'Sync the band'),
      icon: LucideIcons.watch,
      onFix: sync == null ? null : () => _tapSync(sync),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = _d;

    if (d == null) {
      return _refreshable(
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pad,
          children: [
            const SizedBox(height: S.x8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_failed)
              StatusCard(
                l?.homeLoadFailedTitle ?? 'Today could not be read',
                l?.homeLoadFailedBody ??
                    'The stored day failed to load. Nothing was deleted — this is a '
                        'read that went wrong, not missing data.',
                fix: l?.homeTryAgain ?? 'Try again',
                icon: LucideIcons.databaseZap,
                onFix: () {
                  setState(() => (_loading = true, _failed = false));
                  _load();
                },
              )
            else
              Builder(
                builder: (c) {
                  final phase = _phaseStatusCard(c, l);
                  if (phase != null) return phase;
                  final sync = syncOf(c);
                  return StatusCard(
                    l?.homeNothingDerivedTitle ?? 'Nothing derived yet',
                    l?.homeNothingDerivedBody ??
                        'No band recordings processed yet.',
                    fix: sync == null
                        ? ''
                        : (l?.homeSyncBand ?? 'Sync the band'),
                    icon: LucideIcons.watch,
                    onFix: sync == null ? null : () => _tapSync(sync),
                  );
                },
              ),
          ],
        ),
      );
    }

    // Nothing measured at all. It used to be reachable ONLY by a load throwing
    // — a real first-run user got four stacked absence cards instead of the one
    // card written for this state.
    //
    // It is now also where a day of NO WEAR lands, because the overnight block
    // no longer borrows an older night to fill the rings with. Those are two
    // different days and the copy below splits them on the one fact that tells
    // them apart: whether this install has ever scored a night. "No band
    // recordings processed yet" said to someone with three months of history is
    // the first-run answer to a gap, and it is wrong.
    final bare =
        d.readiness.isEmpty &&
        d.sleepMin.isEmpty &&
        d.strain.isEmpty &&
        d.rhr.isEmpty &&
        d.steps.value == null &&
        d.calories.isEmpty;

    c.select<AppState?, (bool, String?)>(
      (app) => (app?.insightsRebuilding ?? false, app?.insightsRebuildMessage),
    );
    final app = c.read<AppState?>();
    final stale = app?.insightsRebuilding == true
        ? const StatusCard(
            'Rebuilding cross-day insights',
            'Calculating from saved measurements…',
            icon: LucideIcons.refreshCw,
          )
        : staleInsightsCard(d.insightsStale, app?.rebuildInsights, l);
    // Above the greeting, not below it: if the app had to rebuild the database
    // to start, that outranks anything else this screen has to say today.
    final rebuilt = dbRebuiltCard(dbRebuildOf(c), l);

    return _refreshable(
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: [
          if (rebuilt != null) ...[const SizedBox(height: S.x3), rebuilt],
          if (app?.insightsRebuildMessage != null) ...[
            const SizedBox(height: S.x3),
            StatusCard(
              'Cross-day insights',
              app!.insightsRebuildMessage!,
              icon: LucideIcons.info,
            ),
          ],

          // ── the one observation Home is allowed to make ──
          //
          // OUTSIDE the derived / not-derived split, and above the rings, for two
          // separate reasons. It outranks them: when this fires it is what matters
          // today, which is the question this screen answers, and under them it
          // would read as a footnote to three numbers. And it does not depend on
          // them — the watch comes off the CROSSDAY rollup, so it can carry a real
          // state on a morning whose own bundle has not derived yet, which is
          // exactly the morning you would most want to be told.
          ...?_bodyWatch(c, d),
          // ── header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x1, S.x3, S.x1, S.x4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Today', style: F.t1.copyWith(color: p.ink)),
                      Text(
                        prettyDay(d.dayId, l),
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                ),
                // The band's battery at a glance, so checking it does not mean
                // opening Settings. The last reading the band reported.
                if (bandBatteryOf(c) case (final pct, final charging)) ...[
                  Semantics(
                    label: 'Band battery ${pct.round()} percent'
                        '${charging ? ', charging' : ''}',
                    excludeSemantics: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          charging
                              ? LucideIcons.batteryCharging
                              : pct < 20
                              ? LucideIcons.batteryLow
                              : LucideIcons.battery,
                          size: 18,
                          color: pct < 20 && !charging ? p.on(C.red) : p.ink2,
                        ),
                        const SizedBox(width: S.x1),
                        Text(
                          '${pct.round()}%',
                          style: F.cap.copyWith(color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: S.x3),
                ],
                Pressable(
                  semanticLabel: 'Settings',
                  onTap: () => go(c, const MoreSettings()),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.card,
                    ),
                    child: Icon(LucideIcons.settings, size: 18, color: p.ink2),
                  ),
                ),
              ],
            ),
          ),

          if (bare)
            // A live workout holds derivation, so a bare day with a session open
            // is the hold at work, not a sync problem — see [workoutHoldCard].
            (widget.workoutLive ?? workoutLiveOf(c))
                ? workoutHoldCard(l)
                : _bareStatusCard(c, d, l)
          else ...[
            // ── the three rings ──
            //
            // Recovery, strain and sleep, each a door into its own screen. They
            // render as long as ONE of them has something to draw — a trio of
            // empty circles says less than the one written absence below, and the
            // empty state is a DOOR, not a dead end. The pipeline records why
            // readiness came back absent on every day it does — which input was
            // missing, how many of your own nights are behind each one — and that
            // diagnostic used to go nowhere but a Firebase breadcrumb. It belongs
            // one tap away, on the Readiness screen: a wall of per-input
            // diagnostics on Home makes the app read as broken.
            if (RingTrio.has(d))
              RingTrio(
                d: d,
                onOpen: (k) => go(c, switch (k) {
                  HomeRingKind.recovery => const ReadinessDetail(),
                  HomeRingKind.strain => const DayStrainDetail(),
                  HomeRingKind.sleep => const SleepDetail(),
                }),
              )
            else
              Builder(
                builder: (c) {
                  final need = needMessageFromNote(d.readiness.note);
                  return StatusCard(
                    l?.homeReadinessNotScoredTitle ??
                        'Readiness is not scored today',
                    need != null
                        ? (l?.homeReadinessNeedBody(need) ??
                              '$need to know what normal looks like for you.')
                        // Was "Needs a night of beat-to-beat data, plus your own
                        // history to compare it to" — a cause, stated for every
                        // absence the note convention did not cover. The door below
                        // is what actually answers it.
                        : whyFromNote(d.readiness.note) ??
                              (l?.homeReadinessNoReason ??
                                  'Nothing recorded says why.'),
                    fix: l?.homeSeeWhatWasMissing ?? 'See what was missing',
                    icon: LucideIcons.batteryCharging,
                    onFix: () => go(c, const ReadinessDetail()),
                  );
                },
              ),

            // ── the rollup was withheld, not absent ──
            if (stale != null) ...[const SizedBox(height: S.x3), stale],

            // ── heart rate, all day ──
            const SizedBox(height: S.x3),
            _heartCard(c, p, d.graph),

            const SizedBox(height: S.x3),
            _glance(c, d),
            if (widget.data == null) ...[
              const SizedBox(height: S.x3),
              const WeekCard(),
            ],
            // No "Tonight · Bed by" card: Akshat sleeps on his own schedule, so a
            // bedtime and a sleep need are noise here. Both are still computed.
          ],
        ],
      ),
    );
  }

  /// The illness watch, on Home, at amber as well as red.
  ///
  /// Returns null on every ordinary day — green, or no state at all because the
  /// CUSUM has not got its 7 nights yet. Absence here is silence, not a card
  /// explaining that nothing is wrong: "you are not getting sick" is not an
  /// observation worth a slot, and a watch that renders daily stops being read.
  ///
  /// The tap goes to the resting-heart-rate chart rather than Health's copy of
  /// this card, because the chart is the EVIDENCE — the watch reads that one
  /// series, so the honest answer to "why are you telling me this" is to show
  /// it. Health keeps its own fuller card; this is not a duplicate route to the
  /// same words, it is a shorter road to the number underneath them.
  static List<Widget>? _bodyWatch(BuildContext c, HomeData d) {
    final state = d.illnessState;
    if (state == null || state == 'green') return null;
    final l = AppLocalizations.of(c);

    final sameNight = d.illnessDay == null || d.illnessDay == d.dayId;
    final z = d.illnessZ;
    final zAbs = z == null ? '' : z.abs().toStringAsFixed(1);

    return [
      Observation(
        state == 'red'
            ? (l?.homeIllnessRedTitle ??
                  'Several nights in a row are away from your normal')
            : sameNight
            ? (l?.homeIllnessAmberSameNight ??
                  'Last night sat outside your normal range')
            : (l?.homeIllnessAmberOtherNight(prettyDay(d.illnessDay, l)) ??
                  '${prettyDay(d.illnessDay, l)} sat outside your normal range'),
        z == null
            ? (l?.homeIllnessBodyNoZ ??
                  'Your nocturnal resting heart rate has been running above your own '
                      'baseline. This reads one signal. It names a pattern, and it does '
                      'not name a cause.')
            : (z >= 0
                  ? (l?.homeIllnessBodyAbove(zAbs) ??
                        'Your nocturnal resting heart rate has been running above your own '
                            'baseline; that night sat $zAbs standardised deviations above it. '
                            'This reads one signal. It names a pattern, and it does not name '
                            'a cause.')
                  : (l?.homeIllnessBodyBelow(zAbs) ??
                        'Your nocturnal resting heart rate has been running above your own '
                            'baseline; that night sat $zAbs standardised deviations below it. '
                            'This reads one signal. It names a pattern, and it does not name '
                            'a cause.')),
        advice:
            l?.homeIllnessAdvice ??
            'Worth noting if it continues past a couple of days.',
        onTap: () => go(c, const MetricDetail('resting_hr')),
      ),
      const SizedBox(height: S.x3),
    ];
  }

  /// Pull to refresh: syncs the band and the phone, waits for today's numbers
  /// to be worked out again, then reloads. The spinner turns until all of it
  /// is done.
  Widget _refreshable(Widget list) => RefreshIndicator(
    onRefresh: () => pullToRefresh(context, _load),
    child: list,
  );

  /// The whole day's heart rate as one line. Tap for the minute-by-minute
  /// chart you can drag a finger across.
  Widget _heartCard(BuildContext c, P p, DayGraph g) {
    final vals = [for (final v in g.hr) ?v];
    final range = vals.isEmpty
        ? null
        : '${vals.reduce((a, b) => a < b ? a : b).round()} – '
              '${vals.reduce((a, b) => a > b ? a : b).round()} bpm today';
    return Surface(
      onTap: () => go(c, const DayTimelineScreen()),
      semanticLabel: 'Heart rate${range == null ? '' : ', $range'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.heartPulse, size: 16, color: p.on(C.heart)),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text('Heart rate', style: F.cap.copyWith(color: p.ink2)),
              ),
              if (range != null)
                Text(range, style: F.cap.copyWith(color: p.ink3)),
            ],
          ),
          const SizedBox(height: S.x2),
          // The reading arriving now, repainting on its own.
          const _LiveNow(),
          if (vals.length > 1) ...[
            const SizedBox(height: S.x3),
            SizedBox(
              height: 64,
              child: CustomPaint(
                size: Size.infinite,
                painter: LineChart(g.hr, p.on(C.heart), t: animate(c, 1)),
              ),
            ),
            const SizedBox(height: S.x2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in const ['12 am', 'Noon', '12 am'])
                  Text(t, style: F.over.copyWith(color: p.ink3)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _glance(BuildContext c, HomeData d) {
    final l = AppLocalizations.of(c);
    final cards = <Widget>[];

    // Steps keeps its tile whether or not a counter reported. Zero steps is a
    // real reading — an unmoved counter — and it renders as 0, not as absence.
    // When nothing counted at all the tile stays and says so in two words,
    // rather than the whole card being replaced by a paragraph about wrist
    // motion: the answer to "how many steps" is short either way.
    cards.add(
      SignalCard(
        LucideIcons.footprints,
        C.green,
        l?.homeSteps ?? 'Steps',
        d.steps.value == null
            ? (l?.homeStepsNone ?? 'None')
            : thousands(d.steps.value),
        // The sensor rides the line that is already there rather than adding a
        // row: the day is resolved per window now, so "8,412" can be the strap's
        // count, the phone's, or both, and the card has to say which. The split
        // behind a mixed day is on the Steps breakdown, two taps down.
        sub: d.steps.value == null
            ? (l?.homeStepsNotRecorded ?? 'NOT RECORDED')
            : [
                if (d.stepGoal > 0)
                  l?.homeStepsPercentGoal(
                        ((d.steps.value! / d.stepGoal) * 100)
                            .clamp(0, 999)
                            .round(),
                      ) ??
                      '${((d.steps.value! / d.stepGoal) * 100).clamp(0, 999).round()}% of goal',
                ?stepSensorLabel(d.steps, l),
                // Walking energy, on its own — not part of active or total kcal.
                if (d.walkingKcal != null)
                  'Steps: Budget ${d.walkingKcal!.round()} · ACSM ${d.upkeep?.acsmParts?.steps.round().toString() ?? '—'} kcal',
              ].join(' · '),
        onTap: () => go(c, const MetricDetail('steps')),
        trailing: d.steps.value == null || d.stepGoal <= 0
            ? null
            : SizedBox(
                width: 20,
                height: 20,
                child: CustomPaint(
                  painter: Ring(
                    d.steps.value! / d.stepGoal,
                    C.green,
                    P.of(c).track,
                    stroke: 3,
                    solid: true,
                  ),
                ),
              ),
      ),
    );
    // Maintenance so far: resting + steps outside runs + runs by distance +
    // 10% of food logged. A floor: lifts and other workouts are not added.
    final upkeep = d.upkeep;
    final up = upkeep?.parts;
    if (upkeep != null && up != null) {
      cards.add(
        Surface(
          onTap: () => showMaintenance(c, upkeep, today: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Maintenance', style: F.head.copyWith(color: P.of(c).ink)),
              const SizedBox(height: S.x3),
              CaloriePair(
                budget: up.total,
                acsm: upkeep.acsmParts?.total,
                note:
                    'Whole-day resting energy + movement and food logged so far.',
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: S.x3),
          // IntrinsicHeight, because `stretch` inside a ListView asks for an
          // infinite height. The two cards in a row must match: a short card
          // beside a tall one reads as a layout bug, not as less data.
          // An odd last card takes the whole width rather than half of it with a
          // hole beside it. Three cards is the ordinary count now that sleep is
          // a ring, so the gap would be there every day.
          if (i + 1 >= cards.length)
            cards[i]
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[i]),
                  const SizedBox(width: S.x3),
                  Expanded(child: cards[i + 1]),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// The live heart rate as one line: the number and a LIVE mark, or why there
/// is none. Selects only `liveHr`, so the 1 Hz stream repaints this line alone.
class _LiveNow extends StatelessWidget {
  const _LiveNow();

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    int? hr;
    try {
      hr = c.select<AppState, int?>((a) => a.liveHr);
    } catch (_) {
      hr = null; // no AppState above us, as in a golden
    }
    if (hr == null) {
      return Text(
        'No live reading right now',
        style: F.cap.copyWith(color: p.ink3),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$hr', style: F.n34.copyWith(color: p.ink)),
        const SizedBox(width: S.x1),
        Text('bpm now', style: F.cap.copyWith(color: p.ink3)),
        const SizedBox(width: S.x2),
        const Pill('LIVE', C.heart),
      ],
    );
  }
}
