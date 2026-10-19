import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import 'dart:async';

import 'app.dart';
import 'ble/ios_ble_restore.dart';
import 'notify/notification_service.dart';
import 'platform/error_log.dart';
import 'state/app_state.dart';
import 'state/prefs.dart';
import 'state/locale_controller.dart';
import 'state/units_controller.dart';
import 'sync/ios_bg_task.dart';
import 'theme/theme_controller.dart';

/// Ceiling on every pre-runApp platform-channel await. Each one is guarded
/// against THROWING, but a channel call that simply never completes (seen in
/// the field: flutter_secure_storage wedging on some Samsung Knox keystores)
/// used to park the app on the native launch screen forever — no crash, no
/// ANR, just "the app doesn't load". A timed-out init logs and degrades;
/// first frame always ships.
const _kStartupInitTimeout = Duration(seconds: 6);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Uncaught errors go to the app log before anything else can throw.
  installErrorLog();

  // Cap the decoded-image cache. Flutter's default is 1000 entries / 100 MiB of
  // DECODED bitmaps, sized for a photo feed; progress photos and run-map
  // snapshots fit well inside 40 MiB, and an evicted one simply re-decodes.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 40 << 20
    ..maximumSize = 200;

  // iOS CoreBluetooth State Preservation & Restoration: opt the flutter_blue_plus
  // central (the one that actually subscribes to the band's HR/event characteristics)
  // into a restore identifier. Apple preserves a connection AND its characteristic
  // subscriptions ONLY for a central created with a restore id — without this, a
  // suspended app resumes with the peripheral still flagged "connected" but its GATT
  // notifications dead until a full reconnect+re-subscribe (the "connected, no events"
  // bug). MUST be set before any other FBP call.
  try {
    await FlutterBluePlus.setOptions(restoreState: true)
        .timeout(_kStartupInitTimeout);
  } catch (_) {/* older plugin / unsupported platform — ignore */}
  try {
    await FlutterBluePlus.setLogLevel(LogLevel.none, color: false)
        .timeout(_kStartupInitTimeout);
  } catch (_) {/* older plugin / unsupported platform — ignore */}

  // Optional startup services. A failure in any one of these must NEVER block the
  // first frame — they are awaited before runApp, so an unguarded throw (e.g. the
  // flutter_local_notifications `invalid_icon` crash) leaves the app stuck on the
  // native launch screen (blank/icon). Guard each so the UI always boots.
  // The CoreBluetooth-restoration wake handler.
  await _safeInit('IosBleRestore', IosBleRestore.init);
  // The BGProcessingTask Dart handler (openstrap/bg_task channel).
  await _safeInit('IosBgTask', IosBgTask.init);
  await _safeInit('NotificationService', NotificationService.instance.init);
  // Cache SharedPreferences so UI screens can synchronously RESTORE saved
  // selections (tab, range toggles) in initState with no async flash.
  await _safeInit('Prefs', Prefs.ensureLoaded);

  // Resolve appearance (persisted choice + OS brightness) BEFORE the first frame
  // so login/signup already paint in the right mode (Ember on Paper / Char).
  // Fall back to a system-brightness controller if persistence fails.
  ThemeController theme;
  try {
    theme = await ThemeController.bootstrap().timeout(_kStartupInitTimeout);
  } catch (e, st) {
    debugPrint('[main] ThemeController.bootstrap failed, using default: $e\n$st');
    theme = ThemeController.seed(
      AppThemeChoice.system,
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  // Local display-units preference (metric/imperial). Best-effort; defaults to metric.
  UnitsController units;
  try {
    units = await UnitsController.bootstrap().timeout(_kStartupInitTimeout);
  } catch (e, st) {
    debugPrint('[main] UnitsController.bootstrap failed, using metric: $e\n$st');
    units = UnitsController.seed(UnitSystem.metric);
  }

  // Local language override (null = system default).
  LocaleController locale;
  try {
    locale = await LocaleController.bootstrap().timeout(_kStartupInitTimeout);
  } catch (e, st) {
    debugPrint('[main] LocaleController.bootstrap failed, using system: $e\n$st');
    locale = LocaleController.seed(null);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState(), lazy: false),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<UnitsController>.value(value: units),
        ChangeNotifierProvider<LocaleController>.value(value: locale),
      ],
      child: const OpenStrapApp(),
    ),
  );
}

/// Run an optional startup init, swallowing (but logging) any failure so it can
/// never prevent runApp from being reached. Also bounded by
/// [_kStartupInitTimeout]: a hang is just as fatal to the first frame as a
/// throw, and try/catch alone never covered it.
Future<void> _safeInit(String label, Future<void> Function() init) async {
  try {
    await init().timeout(_kStartupInitTimeout);
  } on TimeoutException {
    debugPrint('[main] $label init TIMED OUT after '
        '${_kStartupInitTimeout.inSeconds}s — continuing without it');
  } catch (e, st) {
    debugPrint('[main] $label init failed (continuing without it): $e\n$st');
  }
}
