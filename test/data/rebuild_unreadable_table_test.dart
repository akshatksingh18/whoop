// An unreadable table must not erase the rest of a quarantined store.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('rebuild-partial-journal', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(() async {
    LocalDb.lastRebuild = null;
    await LocalDb.close();
  });

  for (final incompatible in [false, true]) {
    test(
      'quarantine recovers later tables when a journal table is incompatible: $incompatible',
      () async {
        const day = '2021-04-06';
        await JournalStore.put(day, '["water"]', 'Authored daily evidence');
        await MetricSeriesStore.putBaseline('authored-marker', '{"bound":7}');
        final prior = await LocalDb.instance;
        final journal = await prior.query('journal');
        final baseline = (await prior.query(
          'baselines',
          where: 'key = ?',
          whereArgs: ['authored-marker'],
        )).single;
        final path = LocalDb.dbName;
        await LocalDb.close();
        final original = await databaseFactory.openDatabase(path);
        try {
          // Preserve a whole synthetic source whose historical migration cannot
          // rename raw_records because a previous attempt reserved its name.
          await original.execute('CREATE TABLE _raw_old (hex TEXT)');
          if (incompatible) {
            await original.execute(
              'ALTER TABLE journal RENAME TO authored_journal',
            );
            await original.execute(
              'CREATE TABLE journal (date TEXT PRIMARY KEY, tags_json TEXT, '
              'note TEXT, updated_at INTEGER) WITHOUT ROWID',
            );
            await original.execute(
              'INSERT INTO journal SELECT date, tags_json, '
              'note, updated_at FROM authored_journal',
            );
          }
          await original.execute('PRAGMA user_version = 2');
        } finally {
          await original.close();
        }

        LocalDb.lastRebuild = null;
        final recovered = await LocalDb.instance;
        final receipt = LocalDb.lastRebuild!;
        expect(receipt.salvaged['journal'], incompatible ? 0 : 1);
        expect(receipt.salvaged['baselines'], greaterThanOrEqualTo(1));
        expect(
          await recovered.query('journal'),
          incompatible ? isEmpty : journal,
        );
        expect(await MetricSeriesStore.baseline('authored-marker'), baseline);
        expect((await DiagnosticsStore.schemaHealth())['ok'], isTrue);
        final quarantine = File(receipt.quarantinePath);
        expect(quarantine.existsSync(), isTrue);
        final quarantined = await databaseFactory.openDatabase(
          quarantine.path,
          options: OpenDatabaseOptions(readOnly: true),
        );
        try {
          final preserved = await quarantined.query('journal');
          expect(preserved.single['note'], journal.single['note']);
          expect(preserved.single['tags_json'], journal.single['tags_json']);
          if (incompatible) {
            expect(await quarantined.query('authored_journal'), journal);
          }
          expect(
            await quarantined.query(
              'baselines',
              where: 'key = ?',
              whereArgs: ['authored-marker'],
            ),
            [baseline],
          );
        } finally {
          await quarantined.close();
        }
      },
    );
  }
}
