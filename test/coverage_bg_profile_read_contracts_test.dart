// Actual background dispatcher with an empty authored database. No heavy
// substrate, native wake, peripheral or personal profile participates.
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/sync/headless_gate.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('bg-profile-read-contracts'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final valid in [false, true]) {
    test(
      'Background ${valid ? 'valid' : 'malformed'} stored profile releases the gate and preserves unrelated data',
      () async {
        final oldActive = IosBleRestore.foregroundActive;
        final oldPull = IosBgTask.foregroundPull;
        final oldGoal = autoCountKcalGoal;
        IosBleRestore.foregroundActive = true;
        var pulls = 0;
        IosBgTask.foregroundPull = () async => pulls++;
        autoCountKcalGoal = null;
        final raw = valid
            ? jsonEncode({
                'kcal_target': 1800,
                'age': 30,
                'sex': 'f',
                'weight_kg': 70,
                'height_cm': 170,
              })
            : 'authored not JSON';
        SharedPreferences.setMockInitialValues({
          'local_profile_json': raw,
          'authored-unrelated': 'keep',
        });
        await LocalDb.setCursor('authored-recovery', 'keep');
        final db = await LocalDb.instance;
        final before = await db.query('sync_cursor');
        try {
          expect(
            await IosBgTask.handleCall(
              const MethodCall('run', {'mode': 'sync'}),
            ),
            true,
          );
          expect(pulls, 1);
          expect(autoCountKcalGoal, valid ? 1800 : null);
          expect(HeadlessSyncGate.busy, false);
          expect(await db.query('sync_cursor'), before);
          expect(await db.query('day_result'), isEmpty);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('local_profile_json'), raw);
          expect(prefs.getString('authored-unrelated'), 'keep');
        } finally {
          IosBleRestore.foregroundActive = oldActive;
          IosBgTask.foregroundPull = oldPull;
          autoCountKcalGoal = oldGoal;
        }
      },
    );
  }
}
