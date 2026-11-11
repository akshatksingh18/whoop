// An actual SQLite open failure during an OS wake leaves the original store
// untouched. Restoring storage access permits the next real wake to run.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/headless_gate.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oldForeground = IosBleRestore.foregroundActive;
  final oldPull = IosBgTask.foregroundPull;
  setUpAll(() => coverageStore('bg-open-retry', fresh: true));
  setUp(resetCoverageStore);
  tearDown(() async {
    IosBleRestore.foregroundActive = oldForeground;
    IosBgTask.foregroundPull = oldPull;
    BandOwnership.resetForTest();
    await FileLog.write('Authored BG open-retry cleanup');
  });
  tearDownAll(LocalDb.close);
  for (final light in [true, false]) {
    for (final profile in [false, true]) {
      test(
        '${light ? 'Refresh' : 'Processing'} with ${profile ? 'saved' : 'absent'} profile releases a refused SQLite open and retries',
        () async {
          await LocalDb.putDayResult(
            dayId: '2021-04-06',
            algoVersion: 102,
            payloadJson: '{"scalars":{"rmssd":44}}',
            windowJson: '{}',
            finalized: true,
            rmssd: 44,
            series: {'rmssd': 44},
          );
          final db = await LocalDb.instance;
          final rows = await db.query('day_result');
          final series = await db.query('metric_series');
          final prefs = await SharedPreferences.getInstance();
          final raw = jsonEncode({
            'age': 30,
            'sex': 'f',
            'weight_kg': 70,
            'height_cm': 170,
            'kcal_target': 1800,
          });
          if (profile) await prefs.setString('local_profile_json', raw);
          await prefs.setString('authored-unrelated', 'retain');
          final originalPath = LocalDb.dbName;
          final refusedParent = await Directory(
            '${File(originalPath).parent.path}/authored-directory-not-a-database',
          ).create(recursive: true);
          final refusedPath = await refusedParent.createTemp('blocked-');
          await LocalDb.close();
          final lease = await BandOwnership.acquireForeground();
          IosBleRestore.foregroundActive = true;
          var pulls = 0;
          IosBgTask.foregroundPull = () async => pulls++;
          final marker = 'AUTHORED_BG_OPEN_${light}_$profile';
          await FileLog.write(marker);
          final call = MethodCall('run', light ? const {'mode': 'sync'} : null);
          try {
            LocalDb.dbName = refusedPath.path;
            expect(await IosBgTask.handleCall(call), true);
            expect(pulls, 1);
            expect(HeadlessSyncGate.busy, false);
            expect(BandOwnership.owner, BandOwnerKind.foreground);
            await FileLog.write('barrier');
            final log = (await File(
              (await FileLog.path())!,
            ).readAsString()).split(marker).last;
            // The shared engine owns this storage failure and retains its
            // diagnostics; the dispatcher's outer exception guard is not used.
            expect(log, contains('[ios-bgtask-derive] [derive] derive ERROR:'));
            expect(log, contains('open_failed'));
            if (!light) {
              expect(
                log,
                contains('[ios-bgtask-derive] [derive] rescan ERROR:'),
              );
            }
            expect(log, contains('stage=calculation_end'));
            expect(prefs.getString('local_profile_json'), profile ? raw : null);
            expect(prefs.getString('authored-unrelated'), 'retain');
          } finally {
            await LocalDb.close();
            LocalDb.dbName = originalPath;
          }
          final restored = await LocalDb.instance;
          expect(await restored.query('day_result'), rows);
          expect(await restored.query('metric_series'), series);
          expect(await IosBgTask.handleCall(call), true);
          expect(pulls, 2);
          expect(HeadlessSyncGate.busy, false);
          expect(BandOwnership.owner, BandOwnerKind.foreground);
          expect(await restored.query('day_result'), rows);
          expect(await restored.query('metric_series'), series);
          BandOwnership.release(lease);
        },
      );
    }
  }
}
