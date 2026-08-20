// A baseline is a picture of THIS person as measured by THIS device. Another
// vendor's export is a different algorithm's output over a different (or no)
// substrate, so a day that came from one must never set the median a personal
// z-score is taken against.
//
// The law was enforced on the WRITE path only (`LocalDb.isMeasuredDay` stops an
// import overwriting a measured day) and not on the READ path, so imported days
// were feeding the readiness/illness baselines in shipped code.
//
// The trap this test pins down is the OTHER direction. `metric_series_version.
// source` only exists from schema v43 and is never retro-filled, so every day
// written before it reads NULL — a naive `source = 'band'` filter would delete
// the user's whole genuine early history from their own baselines. NULL means
// "the column did not exist yet", and the day bundle behind it still says who
// wrote it, so it is decidable rather than ambiguous.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A day this device derived from 1 Hz records.
Future<void> _measured(String date, double rhr, {String? source = 'band'}) =>
    LocalDb.putDayResult(
      dayId: date,
      algoVersion: 1,
      payloadJson: '{"date":"$date"}',
      windowJson: '{}',
      finalized: true,
      source: source,
      rhr: rhr,
      series: {'rhr': rhr},
    );

/// A day an importer wrote — the `imported` flag is the marker both importers
/// have always put in the bundle.
Future<void> _imported(
  String date,
  double rhr, {
  String? source = 'whoop_export',
}) =>
    LocalDb.putDayResult(
      dayId: date,
      algoVersion: 1,
      payloadJson: '{"date":"$date","imported":true,"source":"whoop_export"}',
      windowJson: '{}',
      finalized: true,
      source: source,
      rhr: rhr,
      series: {'rhr': rhr},
    );

/// Age the stamps back to before the `source` column existed.
Future<void> _forgetSources() async {
  final db = await LocalDb.instance;
  await db.rawUpdate('UPDATE metric_series_version SET source = NULL');
}

Future<void> _clear() async {
  final db = await LocalDb.instance;
  await db.delete('day_result');
  await db.delete('metric_series');
  await db.delete('metric_series_version');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_baseline_imported_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(_clear);

  test('a mixed history baselines on the measured days only', () async {
    await _measured('2026-01-01', 50);
    await _imported('2026-01-02', 70);
    await _measured('2026-01-03', 51);
    await _imported('2026-01-04', 71);

    expect(await debugBaselineWindow('rhr'), [50, 51]);
  });

  test('pre-v43 days have NULL source and must NOT be dropped', () async {
    await _measured('2026-02-01', 50);
    await _measured('2026-02-02', 52);
    await _forgetSources();

    final window = await debugBaselineWindow('rhr');
    expect(window, isNotEmpty,
        reason: 'a NULL source is "written before the column existed", not '
            '"foreign" — filtering on source alone deletes real history');
    expect(window, [50, 52]);
  });

  test('a pre-v43 IMPORTED day is still excluded — the bundle says so',
      () async {
    await _measured('2026-03-01', 50);
    await _imported('2026-03-02', 70);
    await _forgetSources();

    expect(await debugBaselineWindow('rhr'), [50]);
  });

  test('importedDates names both eras and nothing else', () async {
    await _measured('2026-04-01', 50); // source = 'band'
    await _imported('2026-04-02', 70); // source = 'whoop_export'
    await _imported('2026-04-03', 71, source: null); // pre-v43 import
    await _measured('2026-04-04', 51, source: null); // pre-v43 band day

    expect(await LocalDb.importedDates(), {'2026-04-02', '2026-04-03'});
  });

  test('trailingSeriesValues excludes imported days by default', () async {
    await _measured('2026-05-01', 50);
    await _imported('2026-05-02', 70);
    await _measured('2026-05-03', 51);

    expect(await LocalDb.trailingSeriesValues('rhr', 28), [50, 51]);
    expect(await LocalDb.trailingSeriesValues('rhr', 28, measuredOnly: false),
        [50, 70, 51]);
  });

  test('metricSeries keeps imported days for trends, drops them when asked',
      () async {
    await _measured('2026-06-01', 50);
    await _imported('2026-06-02', 70);

    expect((await LocalDb.metricSeries('rhr')).length, 2);
    expect((await LocalDb.metricSeries('rhr', measuredOnly: true)).length, 1);
  });
}
