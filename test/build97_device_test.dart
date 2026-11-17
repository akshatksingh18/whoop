// Retained-device freshness against synthetic committed battery samples.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/battery_forecast.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/ui2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = Directory('build/build97-device-test').absolute;
    await root.create(recursive: true);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    await LocalDb.instance;
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });
  testWidgets(
    'retained detail refreshes charge state, revisions and foreground without HR queries',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await t.runAsync(() async {
        for (var i = 0; i < 4; i++) {
          await LocalDb.insertBandBatterySample(
            ts: now - (3 - i) * 3600 - 2,
            batteryPct: 80 - i * 5,
            charging: false,
            source: 'synthetic',
          );
        }
      });
      HealthSource source(bool charging) => HealthSource(
        name: 'Synthetic band',
        kind: 'band',
        tier: SourceTier.wristOptical,
        icon: Icons.watch,
        isBand: true,
        family: 'gen4',
        batteryPct: charging ? 70 : 65,
        charging: charging,
      );
      Widget frame(bool charging) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: DeviceDetail(source(charging)),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await t.pump(const Duration(milliseconds: 20));
        }
      }

      DeviceDetailView view() =>
          t.widget<DeviceDetailView>(find.byType(DeviceDetailView));
      await t.pumpWidget(frame(false));
      await settle();
      final initial = view().forecast!;
      expect(initial.isUsable, true);
      // An unrelated live notification must not reread lifetime battery history.
      app.bumpInsights();
      await settle();
      expect(identical(view().forecast, initial), true);
      await t.runAsync(
        () => LocalDb.insertBandBatterySample(
          ts: now,
          batteryPct: 70,
          charging: true,
          source: 'synthetic',
        ),
      );
      await t.pumpWidget(frame(true));
      expect(
        view().forecast,
        isNull,
        reason: 'No discharge estimate while charging',
      );
      app.batteryRevision.value++;
      await settle();
      expect(view().s.charging, true);
      expect(view().forecast, isNull);
      await t.pumpWidget(frame(false));
      await settle();
      expect(
        view().forecast!.note,
        ForecastNote.charging,
        reason: 'Committed charging sample wins over a stale view parameter',
      );
      final before = view().forecast;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle();
      expect(identical(view().forecast, before), false);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
