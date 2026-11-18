// Real state callback and SQLite sample;only native preference reads refuse.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'coverage_settings_controls_test.dart' show Store;
import 'coverage_ble_durable_boundary_test.dart' show until;
import 'support/coverage_store.dart';

class _Reads extends Store {
  Object? failure;
  int reads = 0;
  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    if (failure case final error?) throw error;
    return super.getAll();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oldStore = SharedPreferencesStorePlatform.instance;
  final center = NotificationCenter.instance;
  final oldSink = center.presentSink;
  setUpAll(() => coverageStore('battery-forecast-native-read', fresh: true));
  setUp(resetCoverageStore);
  tearDown(() async {
    center.presentSink = oldSink;
    SharedPreferencesStorePlatform.instance = oldStore;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  tearDownAll(LocalDb.close);
  for (final kind in ['missing', 'platform']) {
    test(
      'live battery survives $kind preference read failure and a healthy later owner',
      () async {
        final store = _Reads()..values['flutter.authored-unrelated'] = 'keep';
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();
        await Prefs.ensureLoaded();
        final original = Map<String, Object>.of(store.values);
        store.failure = kind == 'missing'
            ? MissingPluginException('authored preference reader unavailable')
            : PlatformException(code: 'authored_preference_reader_refused');
        SharedPreferences.resetStatic();
        var presented = 0;
        center.presentSink =
            (event, {bool allowPermissionPrompt = true}) async {
              presented++;
              return false;
            };
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        app.device
          ..batteryPct = 73
          ..charging = false
          ..wristOn = true;
        app.engine.onState(app.device);
        await until(
          () => app.logLines.any(
            (s) => s.contains('[battery-forecast] skipped:'),
          ),
        );
        await until(() => app.batteryRevision.value == 1);
        expect(app.device.batteryPct, 73);
        expect(app.liveHr, isNull);
        expect(presented, 0);
        expect(store.reads, greaterThan(0));
        expect(store.values, original);
        final db = await LocalDb.instance;
        final rows = await db.query('band_battery');
        expect(rows, hasLength(1));
        expect(rows.single['battery_pct'], 73.0);
        expect(rows.single['source'], 'device_state');
        expect(await db.query('day_result'), isEmpty);
        await LocalDb.setCursor('authored-evidence', 'keep');
        store.failure = null;
        SharedPreferences.resetStatic();
        await Prefs.ensureLoaded();
        // Same (second,source) is deliberately deduplicated by the real store.
        // Wait for the next actual second instead of inventing a device clock.
        await until(
          () =>
              DateTime.now().millisecondsSinceEpoch ~/ 1000 >
              (rows.single['ts'] as num).toInt(),
          attempts: 2000,
        );
        final next = AppState.forTesting();
        addTearDown(next.dispose);
        next.device
          ..batteryPct = 72
          ..charging = false
          ..wristOn = true;
        next.engine.onState(next.device);
        await until(() => next.batteryRevision.value == 1);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          next.logLines.where((s) => s.contains('[battery-forecast] skipped:')),
          isEmpty,
        );
        final after = await db.query('band_battery', orderBy: 'ts ASC');
        expect(after, hasLength(2));
        expect(after.first, rows.single);
        expect(after.last['battery_pct'], 72.0);
        expect(store.values['flutter.authored-unrelated'], 'keep');
        expect(await LocalDb.getCursor('authored-evidence'), 'keep');
        expect(
          presented,
          0,
          reason: 'No invented overnight forecast or OS presentation',
        );
      },
    );
  }
}
