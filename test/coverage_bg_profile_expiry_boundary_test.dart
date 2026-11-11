// The actual native expiry callback runs while profile storage is awaited.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/headless_gate.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'coverage_step_tail_recovery_test.dart' show CheckpointStore;
import 'support/coverage_store.dart';

class _ExpiringProfileStore extends CheckpointStore {
  bool expire = true;
  int reads = 0;
  @override
  Future<Map<String, Object>> getAll() async {
    final result = await super.getAll();
    reads++;
    if (expire) {
      expire = false;
      await IosBgTask.handleCall(const MethodCall('expire'));
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalStore = SharedPreferencesStorePlatform.instance;
  final oldForeground = IosBleRestore.foregroundActive;
  final oldPull = IosBgTask.foregroundPull;
  final oldGoal = autoCountKcalGoal;
  setUpAll(() => coverageStore('bg-profile-expiry', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    HeadlessSyncGate.resetForTest();
    BandOwnership.resetForTest();
    autoCountKcalGoal = null;
  });
  tearDown(() async {
    await FileLog.write('Authored profile expiry cleanup');
    IosBleRestore.foregroundActive = oldForeground;
    IosBgTask.foregroundPull = oldPull;
    autoCountKcalGoal = oldGoal;
    SharedPreferencesStorePlatform.instance = originalStore;
    BandOwnership.resetForTest();
  });
  tearDownAll(LocalDb.close);
  for (final light in [false, true]) {
    for (final profile in [false, true]) {
      test(
        '${light ? 'refresh' : 'processing'} expiry while reading ${profile ? 'saved' : 'absent'} profile stops calculation and retries',
        () async {
          await LocalDb.setCursor('authored-history', 'retain');
          final db = await LocalDb.instance;
          final originalCursors = await db.query('sync_cursor');
          final lease = await BandOwnership.acquireForeground();
          IosBleRestore.foregroundActive = true;
          var pulls = 0;
          IosBgTask.foregroundPull = () async => pulls++;
          final store = _ExpiringProfileStore();
          final raw = jsonEncode({
            'age': 30,
            'sex': 'f',
            'weight_kg': 70,
            'height_cm': 170,
            'kcal_target': 1800,
          });
          store.values.addAll({
            if (profile) 'flutter.local_profile_json': raw,
            'flutter.authored-unrelated': 'retain',
          });
          final originals = Map.of(store.values);
          SharedPreferences.setMockInitialValues({});
          SharedPreferencesStorePlatform.instance = store;
          final marker = 'AUTHORED_PROFILE_EXPIRY_${light}_$profile';
          await FileLog.write(marker);
          final generation = DeriveStop.generation;
          final call = MethodCall('run', light ? const {'mode': 'sync'} : null);
          expect(await IosBgTask.handleCall(call), true);
          expect(store.reads, 1);
          expect(DeriveStop.generation, greaterThan(generation));
          expect(pulls, 1);
          expect(HeadlessSyncGate.busy, false);
          expect(BandOwnership.owner, BandOwnerKind.foreground);
          expect(await db.query('day_result'), isEmpty);
          expect(await db.query('metric_series'), isEmpty);
          expect(await db.query('sync_cursor'), originalCursors);
          expect(store.values, originals);
          await FileLog.write('barrier');
          final failedLog = (await File(
            (await FileLog.path())!,
          ).readAsString()).split(marker).last;
          expect(failedLog, contains('stage=calculation_start'));
          expect(failedLog, contains('[ios-bgtask] calculation stopped:'));
          expect(failedLog, contains('stage=calculation_end'));
          expect(failedLog, isNot(contains('[ios-bgtask] error (ignored)')));

          // A new actual wake may run under the new generation. Empty authored
          // history never turns expiry into fabricated overnight measurements.
          expect(await IosBgTask.handleCall(call), true);
          expect(pulls, 2);
          expect(HeadlessSyncGate.busy, false);
          expect(BandOwnership.owner, BandOwnerKind.foreground);
          expect(await db.query('day_result'), isEmpty);
          expect(await db.query('metric_series'), isEmpty);
          expect(await db.query('sync_cursor'), originalCursors);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('authored-unrelated'), 'retain');
          expect(prefs.getString('local_profile_json'), profile ? raw : null);
          expect(autoCountKcalGoal, profile ? 1800 : null);
          BandOwnership.release(lease);
        },
      );
    }
  }
}
