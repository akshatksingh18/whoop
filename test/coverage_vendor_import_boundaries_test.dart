// Authored vendor CSVs: imported values retain units, dates and provenance.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/import/import_container.dart';
import 'package:whoop_companion/import/whoop_import.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('vendor-import-boundaries'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<String> file(String name, String csv) async => (await File(
    '${Directory('build/coverage-remainder/cov44-vendor-import-boundaries').absolute.path}/$name.csv',
  ).writeAsString(csv)).path;
  test(
    'COV-47 workout import preserves declared energy unit and leaves missing end/HR absent',
    () async {
      final path = await file(
        'workouts',
        'Workout start time,Workout end time,Activity name,Energy burned (kJ),Activity strain,Max HR (bpm)\n'
            '2021-04-06T12:00:00+0000,2021-04-06T12:30:00+0000,Synthetic RUN,418.4,3.5,150\n'
            'bad,,,418.4,3.5,150\n'
            '2021-04-07T12:00:00+0000,,,,,\n',
      );
      final result = await WhoopImporter.importFiles([path]);
      expect(result.workouts, 2);
      expect(result.days, 0);
      final start =
          DateTime.parse('2021-04-06T12:00:00Z').millisecondsSinceEpoch ~/ 1000;
      final saved = (await LocalDb.session('whoop_$start'))!;
      expect(saved['type'], 'synthetic run');
      expect(saved['source'], 'whoop');
      expect(saved['calories'], closeTo(100, .01));
      expect(saved['duration_min'], 30);
      expect(saved['max_hr'], 150);
      expect(saved['strain'], 3.5);
      final next = start + 86400;
      final missing = (await LocalDb.session('whoop_$next'))!;
      expect(missing['type'], 'other');
      expect(missing['end_ts'], isNull);
      expect(missing['max_hr'], isNull);
      expect(missing['calories'], isNull);
    },
  );
  test(
    'COV-47 imported stages and clock fallback retain their vendor origin',
    () async {
      final path = await file(
        'sleep',
        'Sleep onset,Wake onset,Asleep duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),In bed duration (min)\n'
            'at 2021-04-05 before sleep,at 2021-04-06 after sleep,420,240,80,100,30,450\n'
            'not a date,also invalid,420,240,80,100,30,450\n',
      );
      final result = await WhoopImporter.importFiles([path]);
      expect(result.days, 1);
      final row = (await LocalDb.dayResult('2021-04-06'))!;
      final payload = jsonDecode(row['payload_json'] as String);
      final accounting = payload['sleep']['accounting']['value'] as Map;
      expect(accounting['tst_sec'], 420 * 60);
      expect(accounting['light_sec'], 240 * 60);
      expect(accounting['deep_sec'], 80 * 60);
      expect(accounting['rem_sec'], 100 * 60);
      expect(accounting['nrem_sec'], 320 * 60);
      expect(accounting['wake_sec'], 30 * 60);
      expect(accounting['imported'], true);
      expect(payload['imported'], true);
      final window = jsonDecode(row['window_json'] as String);
      expect(window['onset_ms'], localDayStartSec('2021-04-05')! * 1000);
      expect(window['offset_ms'], localDayStartSec('2021-04-06')! * 1000);
    },
  );
  test(
    'COV-47 unknown columns report the actual header without writing a day',
    () async {
      final path = await file(
        'unknown',
        'Synthetic unknown column,Another column\n1,2\n',
      );
      await expectLater(
        WhoopImporter.importFiles([path]),
        throwsA(isA<ImportFormatException>()),
      );
      expect(await LocalDb.dayResultDayIdsDesc(), isEmpty);
    },
  );
}
