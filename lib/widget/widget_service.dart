// Widget bridge — writes a small snapshot of today's metrics into the shared App
// Group so the iOS WidgetKit extension (and Android widget) can render them with
// no network. Called whenever the app loads /today or finishes a sync. The widget
// process reads these keys; it never runs Dart.
//
// The App Group id MUST match the one set in Xcode (Runner + widget targets) and
// in the Swift suite name. See guides/IOS_INSTALLATION.md.

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/services.dart';

import '../data/local_repository.dart';
import '../models/payloads.dart';
import '../ui2/screens/home_screen.dart' show readinessBand;

class WidgetService {
  static const _platform = MethodChannel('openstrap/ios_config');

  /// Fallback App Group id. iOS builds read the configured value from Info.plist.
  static const String fallbackAppGroupId = String.fromEnvironment(
    'APP_GROUP_IDENTIFIER',
    defaultValue: 'group.com.example.openstrap',
  );
  static String appGroupId = fallbackAppGroupId;

  /// WidgetKit "kind" (Swift) / Android provider class name.
  static const String _iOSName = 'OpenStrapWidget';

  /// WidgetKit "kind" for the lock-screen Band Battery widget (Swift).
  static const String _batteryIOSName = 'OpenStrapBatteryWidget';
  static const String _androidName = 'OpenStrapWidgetProvider';

  /// Android provider class for the Band Battery widget.
  static const String _batteryAndroidName = 'OpenStrapBatteryWidgetProvider';

  static bool _inited = false;
  static Future<void> init() async {
    if (_inited) return;
    try {
      final configured = await _platform.invokeMethod<String>(
        'appGroupIdentifier',
      );
      if (configured != null && configured.isNotEmpty) {
        appGroupId = configured;
      }
      await HomeWidget.setAppGroupId(appGroupId);
      _inited = true;
    } catch (_) {
      /* platform without widgets — ignore */
    }
  }

  /// Rebuild the snapshot from the derived store and publish it.
  ///
  /// THE entry point — [push] is the writer underneath. Call it on the one
  /// signal that changes what the widget should say: a completed derivation.
  /// It had exactly one caller left (the iOS BGTask); the foreground caller was
  /// `today_screen.dart`'s fetch, which was deleted with the old UI, so on
  /// Android nothing refreshed the home widget, the Watch mirror or the Siri
  /// intents at all — they answered with whatever the last BGTask wake wrote.
  ///
  /// Best-effort; never throws into the caller.
  static Future<void> refresh(LocalRepository? repo) async {
    if (repo == null) return;
    try {
      await push(TodayData.fromJson(await repo.getToday()));
    } catch (_) {/* the widget is a mirror; it must never break its source */}
  }

  /// True when [t] is describing a day that is more than one calendar day
  /// behind [now] — i.e. the app has not derived anything for over 24 h and the
  /// numbers are not "today's" by any reading.
  ///
  /// LAST NIGHT'S sleep shown during today is NOT stale: that is the normal
  /// state of every metric here until the next night lands, which is why this
  /// allows a one-day lag rather than demanding an exact match. Returns false
  /// when the payload carries no status block — an unknown age is not a claim
  /// of staleness.
  @visibleForTesting
  static bool isStale(TodayData t, {DateTime? now}) {
    final s = t.status;
    if (s == null) return false;
    final day = _parseDay(s.overnightDay ?? s.activityDay ?? s.todayDay);
    if (day == null) return false;
    final today = now ?? DateTime.now();
    return DateTime(today.year, today.month, today.day)
            .difference(day)
            .inDays >
        1;
  }

  /// 'yyyy-mm-dd' → local midnight. Null for anything else.
  static DateTime? _parseDay(String? label) {
    if (label == null) return null;
    final p = label.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// Push the latest snapshot and trigger a widget reload. Best-effort; never
  /// throws into the caller. Sentinels: ints use -1 / strings use '' for "no data".
  static Future<void> push(TodayData t) async {
    try {
      await init();
      final hrv = t.hrv;
      final s = t.strain;
      final sleep = t.sleepDuration;
      final need = t.sleepNeed;
      final rhr = t.restingHr;

      Future<void> setI(String k, int v) =>
          HomeWidget.saveWidgetData<int>(k, v);

      // has_data is the ONE flag every native reader gates on (the WidgetKit
      // home + lock-screen widgets, the Watch mirror, the Siri intents), and it
      // is the only way this side can say "don't show a number" to any of them.
      // A snapshot the app KNOWS is over a day old must not sit on a lock
      // screen looking current — the widget's own no-data state is the honest
      // answer, and the alternative is a readiness score from last week with
      // nothing on it to say so.
      await HomeWidget.saveWidgetData<bool>('has_data', !t.isEmpty && !isStale(t));
      // Headline composite Readiness + the three rings (Strain · Sleep · HRV).
      final rv = t.readiness.isEmpty ? null : t.readiness.value;
      await setI('readiness', rv == null ? -1 : rv.round());
      // The banding, published rather than re-derived. The widget, the Watch
      // and Siri each carried their own thresholds, so the same 65 read green
      // here, orange on the widget and yellow on the wrist. They now render
      // `readiness_tier` (colour) and `readiness_band` (label) and decide
      // nothing themselves — see `readinessBand`, the only copy of the cut-offs.
      final band = readinessBand(rv);
      await setI('readiness_tier', band.tier);
      await HomeWidget.saveWidgetData<String>(
        // '' for "no data", like every other string key here. Every native
        // reader gates its label on `readiness >= 0` anyway, so "Not scored"
        // would only ever be text nobody sees.
        'readiness_band',
        band.tier < 0 ? '' : band.label,
      );
      await setI('hrv', hrv == null ? -1 : hrv.rmssd.round());
      await setI(
        'hrv_baseline',
        hrv?.baseline == null ? -1 : hrv!.baseline!.round(),
      );
      await HomeWidget.saveWidgetData<double>(
        'strain',
        s.isEmpty ? -1.0 : s.value!.toDouble(),
      );
      await setI('sleep_min', sleep.isEmpty ? -1 : sleep.value!.round());
      // -1, like every other int key here, whenever the payload carries no
      // learned sleep need. `/today` used to hand this side a hard 480 —
      // `_sleepSummary` wrote `need_min: 480` unconditionally — so this branch
      // could never fire and the home widget, the Watch and the lock screen all
      // drew their sleep ring as a fraction of a fabricated 8h00m denominator.
      // The payload now omits the key until `sleep_coach.need` exists; the
      // native readers gate their ring on `needMin > 0`, so the sentinel leaves
      // it empty.
      await setI('sleep_need_min', need.isEmpty ? -1 : need.value!.round());
      await setI('rhr', rhr.isEmpty ? -1 : rhr.value!.round());
      await HomeWidget.saveWidgetData<String>(
        'coach_line',
        _coachLine(t.coach),
      );
      await setI('updated_at', DateTime.now().millisecondsSinceEpoch ~/ 1000);

      await HomeWidget.updateWidget(
        iOSName: _iOSName,
        androidName: _androidName,
      );
      await _syncWatch();
    } catch (_) {
      /* widgets unavailable / not configured yet — ignore */
    }
  }

  /// Blank the App Group snapshot — home widget, lock-screen battery widget,
  /// Watch mirror and the Siri intents all read it.
  ///
  /// Part of "Delete everything". These surfaces never run Dart, so nothing
  /// else can correct them: without this the home screen kept showing the
  /// readiness, sleep and HRV of a database that no longer existed, and the
  /// Watch kept mirroring it, indefinitely.
  ///
  /// `has_data: false` is the one flag every native reader gates on, so it
  /// alone is sufficient — the rest is cleared so no stale value survives to be
  /// read by some future reader that forgets to check the flag.
  static Future<void> clear() async {
    try {
      await init();
      await HomeWidget.saveWidgetData<bool>('has_data', false);
      for (final k in const [
        'readiness',
        'readiness_tier',
        'hrv',
        'hrv_baseline',
        'sleep_min',
        'sleep_need_min',
        'rhr',
        'batt_pct',
      ]) {
        await HomeWidget.saveWidgetData<int>(k, -1);
      }
      await HomeWidget.saveWidgetData<double>('strain', -1.0);
      for (final k in const [
        'readiness_band',
        'coach_line',
        'batt_name',
      ]) {
        await HomeWidget.saveWidgetData<String>(k, '');
      }
      await HomeWidget.saveWidgetData<bool>('batt_charging', false);
      await HomeWidget.updateWidget(
        iOSName: _iOSName,
        androidName: _androidName,
      );
      await HomeWidget.updateWidget(
        iOSName: _batteryIOSName,
        androidName: _batteryAndroidName,
      );
      await _syncWatch();
    } catch (_) {
      /* widgets unavailable / not configured yet — ignore */
    }
  }

  /// Mirror the just-written App Group snapshot to the paired Apple Watch
  /// (iOS only; no-op elsewhere or without a watch). One source of truth: the
  /// native side reads the same App Group keys and pushes them over WCSession.
  static Future<void> _syncWatch() async {
    try {
      await _platform.invokeMethod('syncWatch');
    } catch (_) {
      /* not iOS / no watch / channel absent — ignore */
    }
  }

  /// Push the band's battery snapshot for the lock-screen Band Battery widget.
  /// Battery is a live BLE value (not in /today), so that widget never refreshes
  /// over the network — it renders whatever we last wrote here. Call from the
  /// device-state hook, but only when pct/charging actually changed (the hook
  /// fires ~1 Hz on live HR; reloading the widget every tick is wasteful).
  /// Sentinel: pct -1 = never seen the band. [name] is the strap's advertising
  /// name (the widget falls back to "Strap" when empty/null).
  static Future<void> pushBattery(int? pct, bool? charging, String? name) async {
    try {
      await init();
      await HomeWidget.saveWidgetData<int>('batt_pct', pct ?? -1);
      await HomeWidget.saveWidgetData<bool>('batt_charging', charging ?? false);
      await HomeWidget.saveWidgetData<String>('batt_name', name ?? '');
      await HomeWidget.saveWidgetData<int>(
          'batt_at', DateTime.now().millisecondsSinceEpoch ~/ 1000);
      await HomeWidget.updateWidget(
          iOSName: _batteryIOSName, androidName: _batteryAndroidName);
      await _syncWatch();
    } catch (_) {/* widgets unavailable / not configured yet — ignore */}
  }

  /// Tell the iOS widget + Live Activity which appearance the app is rendering
  /// (Ember on Paper vs Char) so those native surfaces match — including when the
  /// user overrides the OS in-app. Reloads the home widget immediately; the Live
  /// Activity picks it up on its next (frequent) content-state update.
  static Future<void> setThemeDark(bool dark) async {
    try {
      await init();
      await HomeWidget.saveWidgetData<bool>('theme_dark', dark);
      await HomeWidget.updateWidget(
        iOSName: _iOSName,
        androidName: _androidName,
      );
      // The battery widget shares the Ember/Char surface — retheme it too.
      await HomeWidget.updateWidget(
        iOSName: _batteryIOSName,
        androidName: _batteryAndroidName,
      );
    } catch (_) {
      /* widgets unavailable — ignore */
    }
  }

  /// True once (and clears) if the Live Activity's Finish button was tapped.
  /// The App Intent sets `end_session` in the App Group; we consume it on resume.
  static Future<bool> consumeEndSessionFlag() async {
    try {
      await init();
      final v = await HomeWidget.getWidgetData<bool>(
        'end_session',
        defaultValue: false,
      );
      if (v == true) {
        await HomeWidget.saveWidgetData<bool>('end_session', false);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Non-null once (and clears) if a Siri/Shortcuts App Intent asked to open a
  /// specific in-app screen (e.g. StartBreathingIntent sets `pending_route` =
  /// '/breathing' in the App Group before launching the app). Same
  /// App-Group-flag pattern as [consumeEndSessionFlag]. Feed the result
  /// through the normal tap-route pipeline (AppState._handleTapRoute /
  /// tap_router.dart) — never invent a separate navigation path.
  static Future<String?> consumePendingRoute() async {
    try {
      await init();
      final v = await HomeWidget.getWidgetData<String>(
        'pending_route',
        defaultValue: '',
      );
      if (v != null && v.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>('pending_route', '');
        return v;
      }
    } catch (_) {}
    return null;
  }

  /// True once (and clears) if the BREATHING Live Activity's stop button was
  /// tapped. A separate flag (`end_breathing_session`) from the workout's
  /// `end_session` — EndBreathingIntent in OpenStrapBreathingLiveActivity.swift
  /// sets it; two independent Live Activities must never share one flag.
  static Future<bool> consumeEndBreathingFlag() async {
    try {
      await init();
      final v = await HomeWidget.getWidgetData<bool>(
        'end_breathing_session',
        defaultValue: false,
      );
      if (v == true) {
        await HomeWidget.saveWidgetData<bool>('end_breathing_session', false);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static String _coachLine(CoachData? c) {
    if (c == null) return '';
    if (c.plan.isNotEmpty) return c.plan.first.title;
    final tgt = c.strainTarget;
    if (tgt != null) return 'Aim for strain ${tgt.value.toStringAsFixed(0)}';
    return c.summary;
  }
}
