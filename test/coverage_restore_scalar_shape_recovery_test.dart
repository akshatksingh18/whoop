// Approved restoration robustness: real merge/coordinator/SQLite preservation.
// Unsupported scalar detail stays unknown;no sensor values are reconstructed.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

Object malformed(String shape) => switch (shape) {
  'list' => <Object>[],
  'string' => 'unusable',
  'number' => 42,
  'bool' => false,
  _ => throw ArgumentError(shape),
};
const date = '2021-04-06', kept = '2021-04-01';

Future<File> sourceFile(String shape) async {
  final dir = await (await Directory(
    'build/coverage-remainder/restored-scalar-shapes',
  ).absolute.create(recursive: true)).createTemp('authored-');
  final file = File('${dir.path}/authored.db');
  final db = await databaseFactory.openDatabase(file.path);
  await db.execute(
    'CREATE TABLE day_result(day_id TEXT,algo_version INTEGER,payload_json TEXT,window_json TEXT,computed_at INTEGER,finalized INTEGER,skipped INTEGER,partial INTEGER,rhr REAL,rmssd REAL,readiness REAL,PRIMARY KEY(day_id,algo_version))',
  );
  final Object? scalar = switch (shape) {
    'map' => {'rhr': 99, 'rmssd': 99, 'readiness': 99, 'steps': 2345},
    'null' || 'missing' => null,
    'list' => <Object>[],
    'string' => 'unusable',
    'number' => 42,
    'bool' => false,
    _ => throw ArgumentError(shape),
  };
  await db.insert('day_result', {
    'day_id': date,
    'algo_version': kAlgoVersion,
    'payload_json': jsonEncode({
      if (shape != 'missing') 'scalars': scalar,
      'authored_note': 'retain source and unsupported detail',
    }),
    'window_json': '{}',
    'computed_at': 1,
    'finalized': 0,
    'skipped': 0,
    'partial': 0,
    'rhr': 57,
    'rmssd': 41,
    'readiness': 72,
  });
  await db.close();
  await LocalDb.putDayResult(
    dayId: kept,
    algoVersion: kAlgoVersion,
    payloadJson: '{"scalars":{"rhr":55}}',
    windowJson: '{}',
    finalized: true,
    rhr: 55,
  );
  // Three usable days reach the real rollup;two honestly skip it.
  await LocalDb.putDayResult(
    dayId: '2021-04-02',
    algoVersion: kAlgoVersion,
    payloadJson: '{"scalars":{"rhr":59}}',
    windowJson: '{}',
    finalized: true,
    rhr: 59,
  );
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('restored-scalar-shapes'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final shape in [
    'map',
    'missing',
    'null',
    'list',
    'string',
    'number',
    'bool',
  ]) {
    test(
      'real restore $shape scalar detail rebuilds with indexed values and preserves its source',
      () async {
        final file = await sourceFile(shape);
        final bytes = await file.readAsBytes();
        final db = await LocalDb.instance;
        final other = await db.query(
          'day_result',
          orderBy: 'day_id,algo_version',
        );
        final source = await databaseFactory.openDatabase(
          file.path,
          options: OpenDatabaseOptions(readOnly: true),
        );
        final expected = (await source.query('day_result')).single;
        await source.close();
        final app = AppState.forTesting();
        try {
          expect(await app.importEdgeBackup(file.path), 1);
          expect(app.lastImportRecords, 1);
          expect(app.importRollupError, isNull);
          final restored = (await LocalDb.dayResult(date))!;
          expect(restored['payload_json'], expected['payload_json']);
          expect(restored['window_json'], expected['window_json']);
          expect(restored['computed_at'], expected['computed_at']);
          // Compare raw rows with raw rows,including every saved version.
          // dayResult additionally projects a convenience `date` alias.
          expect(
            await db.query(
              'day_result',
              where: 'day_id <> ?',
              whereArgs: [date],
              orderBy: 'day_id,algo_version',
            ),
            other,
          );
          final input =
              jsonDecode(
                    (await LocalDb.baseline('crossday_input'))!['payload_json']
                        as String,
                  )
                  as Map;
          expect(input['algo_version'], kAlgoVersion);
          final rec = (input['days'] as List).cast<Map>().singleWhere(
            (v) => v['date'] == date,
          );
          expect(rec['rhr'], 57);
          expect(rec['rmssd'], 41);
          expect(rec['readiness'], 72);
          expect(rec['steps'], shape == 'map' ? 2345 : null);
          for (final key in [
            'resp_rate',
            'skin_temp_z',
            'skin_temp_adc',
            'trimp',
            'trimp_net',
            'worn_min',
            'sleep_coverage',
            'onset_sec',
            'wake_sec',
            'tst_min',
          ]) {
            expect(
              rec[key],
              isNull,
              reason: 'unsupported $key must remain unknown',
            );
          }
          final rollup =
              jsonDecode(
                    (await LocalDb.baseline('crossday'))!['payload_json']
                        as String,
                  )
                  as Map;
          expect(rollup['n_days'], 3);
          expect((rollup['illness'] as Map)['note'], contains('need_baseline'));
          expect(await file.readAsBytes(), bytes);
          final beforeInput = (await LocalDb.baseline(
            'crossday_input',
          ))!['payload_json'];
          await DerivationEngine().finalizeImport(const Profile());
          expect(
            (await LocalDb.baseline('crossday_input'))!['payload_json'],
            beforeInput,
          );
          final again =
              jsonDecode(
                    (await LocalDb.baseline('crossday'))!['payload_json']
                        as String,
                  )
                  as Map;
          expect(
            again.remove('built_at_epoch'),
            greaterThanOrEqualTo(rollup.remove('built_at_epoch')),
          );
          expect(again, rollup);
          expect(await LocalDb.dayResult(date), restored);
          expect(await file.readAsBytes(), bytes);
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(await db.query('raw_archive'), isEmpty);
        } finally {
          app.dispose();
          await app.engine.disconnect();
        }
      },
    );
  }
  const older = '2021-04-06', newer = '2021-04-07';
  for (final entry in ['ordinary', 'rescan']) {
    for (final shape in ['list', 'string', 'number', 'bool']) {
      for (final anchor in ['rhr', 'rmssd', 'readiness']) {
        test(
          '$entry retains indexed $anchor with $shape restored malformed scalar detail',
          () async {
            final db = await LocalDb.instance;
            for (final (index, date) in [(1, older), (2, newer)]) {
              final ts = localDayStartSec(date)! + 12 * 3600;
              await LocalDb.putDayResult(
                dayId: date,
                algoVersion: kAlgoVersion,
                payloadJson: jsonEncode({
                  'date': date,
                  if (date == newer)
                    'scalars': {'rhr': 57, 'readiness': 72}
                  else
                    'scalars': malformed(shape),
                  'legacy_detail': {
                    'note': 'retain banked measurement evidence',
                    'trace': [1, null, 3],
                  },
                }),
                windowJson: '{}',
                finalized: false,
                rhr: date == newer || anchor == 'rhr' ? 57 : null,
                rmssd: date == newer || anchor == 'rmssd' ? 41 : null,
                readiness: date == newer || anchor == 'readiness' ? 72 : null,
                series: date == newer
                    ? {'rhr': 57, 'rmssd': 41, 'readiness': 72}
                    : {
                        anchor: anchor == 'rhr'
                            ? 57.0
                            : anchor == 'rmssd'
                            ? 41.0
                            : 72.0,
                      },
              );
              await LocalDb.insertRecord(
                RawRecord(
                  counter: index,
                  packetType: 47,
                  hex: 'authored-column-fallback-$index',
                  recTs: ts,
                  capturedAt: ts * 1000,
                ),
                Sample(
                  tsEpoch: ts,
                  counter: index,
                  hr: 60,
                  ax: 0,
                  ay: 0,
                  az: 1,
                ),
              );
            }
            final before = await LocalDb.dayResult(older);
            final series = await db.query(
              'metric_series',
              where: 'date=?',
              whereArgs: [older],
              orderBy: 'key',
            );
            final versions = await db.query(
              'metric_series_version',
              where: 'date=?',
              whereArgs: [older],
            );
            final latest = await db.query(
              'decoded_onehz',
              where: 'rec_ts>=?',
              whereArgs: [localDayStartSec(newer)!],
            );
            Future<int>? pruned;
            final completed = <String>[], logs = <String>[];
            void done(String date, int index, int total) {
              completed.add(date);
              expect(total, 2);
              expect(index, completed.length);
              if (date == newer) {
                // The real callback queues this write before sequential preparation
                // of the selected older day. No synthetic empty import is injected.
                pruned = db.delete(
                  'decoded_onehz',
                  where: 'rec_ts<?',
                  whereArgs: [localDayStartSec(newer)!],
                );
              }
            }

            final engine = DerivationEngine(background: true, log: logs.add);
            final count = entry == 'ordinary'
                ? await engine.run(
                    const Profile(),
                    heavy: true,
                    force: true,
                    onDayDone: done,
                  )
                : await engine.rescanRecent(const Profile(), onDayDone: done);
            expect(count, 2, reason: logs.join('\n'));
            expect(completed, [newer, older]);
            expect(pruned, isNotNull);
            expect(await pruned!, 1);
            expect(
              logs,
              contains(
                contains(
                  'derive $older: no substrate (raw pruned) — kept the existing result',
                ),
              ),
            );
            expect(await LocalDb.dayResult(older), before);
            expect(
              await db.query(
                'metric_series',
                where: 'date=?',
                whereArgs: [older],
                orderBy: 'key',
              ),
              series,
            );
            expect(
              await db.query(
                'metric_series_version',
                where: 'date=?',
                whereArgs: [older],
              ),
              versions,
            );
            expect(await db.query('decoded_onehz'), latest);
            expect(engine.running, false);
            expect(
              await engine.run(const Profile(), heavy: true, force: true),
              1,
            );
            expect(await LocalDb.dayResult(older), before);
            expect(await db.query('decoded_onehz'), latest);
            expect(engine.running, false);
          },
        );
      }
    }
  }
}
