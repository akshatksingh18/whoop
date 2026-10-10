// ios_bg_task.dart — iOS BGProcessingTask + BGAppRefreshTask Dart handler.
//
// Build 86: active in the personal build too. Both tasks are bounded: the
// refresh task's calculation stops itself after [_refreshBudget], and either
// task's expiration ("expire" from native) stops calculation at once through
// [DeriveStop] — committed days stay, queued work waits for the next chance.
// These are OS-granted extras; iOS promises no schedule, so foreground
// catch-up remains the guaranteed path.
//
// Native (BgSyncScheduler.swift) calls the `openstrap/bg_task` channel method
// `run` when iOS opportunistically wakes the app for a background task.
//   - BGProcessingTask (no arguments): FULL profile — runHeadlessSync()
//     (connect → flash offload → local store → disconnect → light derive)
//     followed by a heavy DerivationEngine pass (full sleep staging + 24h
//     spectra).
//   - BGAppRefreshTask ({'mode': 'sync'}): LIGHT profile — headless sync only,
//     NO heavy derivation (a refresh task's ~30 s budget can't fit it; the
//     light per-drain derive inside runHeadlessSync still runs).
// Returns true to signal completion.
//
// iOS gives BGProcessingTask a longer wall-clock budget than BGAppRefreshTask
// (up to ~2–3 min typically; device-dependent), but we must still be bounded.
// runHeadlessSync already has a timeout inside BleEngine; heavy derive is also
// bounded per-day. If the OS fires the expiration handler, the partial run is
// safe — the non-destructive cursor and the per-day finalisation flag let the
// next wake (or foreground open) catch up.
//
// Guard: if IosBleRestore reports the app already owns the band (foreground
// session active), we skip the headless sync to avoid fighting flutter_blue_plus
// for the peripheral, and go straight to derive. This shouldn't happen in
// practice (BGTasks only fire in the background), but it is defensive.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import '../compute/derivation_engine.dart';
import '../compute/profile.dart';
import '../ble/ios_ble_restore.dart';
import '../data/local_repository_impl.dart';
import '../widget/widget_service.dart';
import 'background_sync.dart';
import 'headless_gate.dart';

class IosBgTask {
  static const _ch = MethodChannel('openstrap/bg_task');
  static const _kProfileKey = 'local_profile_json'; // matches AppState._kProfile

  /// When the FOREGROUND app owns the band, a BG-task wake must not open a
  /// competing headless connection — but it should still pull the flash backlog
  /// over the EXISTING live link. AppState installs its floored catch-up pull
  /// here (see AppState.foregroundCatchUp); null until an AppState exists.
  static Future<void> Function()? foregroundPull;

  /// Register the method call handler. Call once at startup from main().
  /// No-op on Android.
  /// Calculation time a BGAppRefreshTask may use after its transfer. Apple
  /// documents about 30 s for the whole task; the transfer comes first.
  static const _refreshBudget = Duration(seconds: 15);

  /// Ceiling for a processing task's calculation if iOS never expires it.
  static const _processingBudget = Duration(minutes: 4);

  static Future<void> init() async {
    if (!Platform.isIOS) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'expire') {
        // iOS is ending the task: stop now rather than run into a kill.
        DeriveStop.request('ios_bg_task_expired');
        return null;
      }
      if (call.method != 'run') return null;
      // BGAppRefreshTask passes {'mode': 'sync'} → LIGHT profile (sync only).
      final args = call.arguments;
      final mode = args is Map ? args['mode']?.toString() : null;
      return _run(syncOnly: mode == 'sync');
    });
  }

  static Future<bool> _run({required bool syncOnly}) async {
    // ONE shared gate across every headless entry point (BGProcessingTask,
    // BGAppRefreshTask, the BLE-restore wake) — see HeadlessSyncGate. A busy
    // gate means another wake is already syncing: skip, report success.
    final ran = await HeadlessSyncGate.tryRun<bool>(
        syncOnly ? 'bg_refresh' : 'bg_task', () async {
      try {
        // Skip headless BLE if the foreground session already owns the band.
        if (!IosBleRestore.foregroundActive) {
          debugPrint('[ios-bgtask] running headless sync (syncOnly=$syncOnly)');
          await runHeadlessSync();
        } else {
          // The foreground app owns the band: no headless BLE (it would fight
          // flutter_blue_plus for the peripheral) — but still use this OS-granted
          // budget to pull the flash backlog over the app's own live connection.
          debugPrint(
              '[ios-bgtask] foreground owns the band — catch-up over live link');
          try {
            await foregroundPull?.call();
          } catch (e) {
            debugPrint('[ios-bgtask] foreground pull failed (ignored): $e');
          }
        }
        // Calculation inside a budget: the light pass (today first) on a
        // refresh, the heavy pass plus baseline rescan on a processing task.
        // A stop (budget or expiration) keeps committed days and leaves the
        // rest queued; it is not reported as a failure.
        final budget = Timer(
          syncOnly ? _refreshBudget : _processingBudget,
          () => DeriveStop.request(syncOnly ? 'bg_refresh_budget' : 'bg_task_budget'),
        );
        try {
          final profile = await _loadProfile();
          final engine = DerivationEngine(
            log: (l) => debugPrint('[ios-bgtask-derive] $l'),
            background: true,
          );
          await engine.run(profile, heavy: !syncOnly);
          if (!syncOnly) await engine.rescanRecent(profile);
          await _refreshWidgetSnapshot(profile);
        } on DeriveCancelled catch (e) {
          debugPrint('[ios-bgtask] calculation stopped: $e');
        } catch (e) {
          debugPrint('[ios-bgtask] calculation skipped: $e');
        } finally {
          budget.cancel();
        }
        debugPrint('[ios-bgtask] done (syncOnly=$syncOnly)');
        return true;
      } catch (e) {
        debugPrint('[ios-bgtask] error (ignored): $e');
        // Return true even on error — the non-destructive cursor means a retry
        // is not harmful, but we don't want to spam the OS with failure signals
        // that could cause iOS to throttle our background budget.
        return true;
      }
    });
    return ran ?? true; // gate busy → another wake is already doing the work
  }

  static Future<Profile> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kProfileKey);
      if (raw == null) return const Profile();
      return Profile.fromMap((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return const Profile();
    }
  }

  /// Push a fresh Today snapshot to the App Group after a headless derive so
  /// the home/lock-screen widget AND the Siri/Shortcuts query intents
  /// (RecoveryIntent/StrainIntent/SleepIntent — see OpenStrapIntents.swift,
  /// which read this same App Group) don't go stale just because the user
  /// hasn't opened the Today screen. Previously WidgetService.push() was only
  /// ever called from today_screen.dart's fetch() — a real gap: "ask Siri
  /// without opening the app" is the whole point of a Siri Shortcut, so any
  /// answer would silently reflect however-stale the last Today-screen visit
  /// was (or "I don't have today's numbers yet" if that never happened at
  /// all). Best-effort — never throws into the caller.
  static Future<void> _refreshWidgetSnapshot(Profile profile) async {
    await WidgetService.refresh(
      LocalRepositoryImpl(getProfileMap: () => profile.toMap()),
    );
  }
}
