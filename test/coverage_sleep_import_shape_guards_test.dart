// Real tiny SQLite backups and correction ledgers; no derivation or real captures.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

const correctedDay = '2021-04-06';
const recoveryCursor = 'authored_recovery_cursor';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory root;
  setUpAll(() => coverageStore('sleep-import-shape-guards'));
  setUp(() async {
    await resetCoverageStore();
    db = await LocalDb.instance;
    await LocalDb.acceptSleepCorrection(dayId: correctedDay, action: 'clear');
    await LocalDb.setCursor(recoveryCursor, 'retain-me');
    await LocalDb.putMetricSeriesValue('2021-04-08', 'strain', 2.5);
    root = await (await Directory(
      'build/coverage-remainder/sleep-import-shape-guards',
    ).absolute.create(recursive: true)).createTemp('authored-');
  });
  tearDownAll(LocalDb.close);

  Future<File> backup({String? pin, String? broken, String? overlap}) async {
    final file = File('${root.path}/authored.sqlite');
    final src = await databaseFactory.openDatabase(
      file.path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) async {
          if (broken == 'baselines') {
            await d.execute('CREATE TABLE baselines (other_key TEXT)');
          }
          if (broken != null &&
              broken != 'baselines' &&
              broken != 'sync_cursor') {
            await d.execute('CREATE TABLE $broken (other_day TEXT)');
          }
          if (overlap != null) {
            final column =
                overlap == 'metric_series' || overlap == 'metric_series_version'
                ? 'date'
                : 'day_id';
            await d.execute('CREATE TABLE $overlap ($column TEXT)');
            await d.insert(overlap, {column: correctedDay});
          }
          if (broken == 'sync_cursor') {
            await d.execute(
              'CREATE TABLE sync_cursor (name TEXT, other_value TEXT)',
            );
          } else if (pin != null) {
            await d.execute(
              'CREATE TABLE sync_cursor (name TEXT PRIMARY KEY, value TEXT, updated_at INTEGER NOT NULL)',
            );
            await d.insert('sync_cursor', {
              'name': LocalDb.kFrozenHeadlineCursor,
              'value': pin,
              'updated_at': 1,
            });
          }
        },
      ),
    );
    await src.close();
    return file;
  }

  Future<Map<String, Object?>> evidence() async => {
    'intent': await LocalDb.sleepCorrection(correctedDay),
    'revision': await LocalDb.sleepCorrectionRevision(),
    'metric': await LocalDb.metricSeries('strain'),
    'cursor': await LocalDb.getCursor(recoveryCursor),
    'days': await db.query('day_result'),
  };

  Future<void> retained(
    File file,
    List<int> original,
    Map<String, Object?> before,
  ) async {
    expect(await evidence(), before);
    expect(await file.readAsBytes(), original);
    final renamed = await file.rename('${file.path}.retained');
    expect(
      await renamed.readAsBytes(),
      original,
      reason:
          'The refused or completed import must release its source database.',
    );
  }

  for (final table in [
    'day_result',
    'sleep_override',
    'metric_series',
    'metric_series_version',
  ]) {
    test(
      'a legacy backup with only $table still cannot overlap a corrected day',
      () async {
        final file = await backup(overlap: table);
        final original = await file.readAsBytes();
        final before = await evidence();
        await expectLater(
          LocalDb.importFromDbFile(file.path),
          throwsA(
            isA<DbImportException>()
                .having((e) => e.records, 'committed records', 0)
                .having(
                  (e) => '${e.cause}',
                  'preserved conflict',
                  contains('overlaps corrected sleep history'),
                ),
          ),
        );
        await retained(file, original, before);
      },
    );
  }

  test(
    'a valid frozen pin alone protects the corrected day despite absent history tables',
    () async {
      final file = await backup(pin: '{"day":"$correctedDay"}');
      final original = await file.readAsBytes();
      final before = await evidence();
      await expectLater(
        LocalDb.importFromDbFile(file.path),
        throwsA(
          isA<DbImportException>()
              .having((e) => e.records, 'committed records', 0)
              .having(
                (e) => '${e.cause}',
                'pin conflict',
                contains('overlaps corrected sleep history'),
              ),
        ),
      );
      await retained(file, original, before);
    },
  );

  for (final broken in [
    'baselines',
    'day_result',
    'metric_series_version',
    'sync_cursor',
  ]) {
    test(
      'a malformed $broken schema is refused rather than treated as an absent table',
      () async {
        final file = await backup(broken: broken);
        final original = await file.readAsBytes();
        final before = await evidence();
        await expectLater(
          LocalDb.importFromDbFile(file.path),
          throwsA(
            isA<DbImportException>()
                .having((e) => e.records, 'committed records', 0)
                .having(
                  (e) => '${e.cause}',
                  'real schema error',
                  contains('no such column'),
                ),
          ),
        );
        await retained(file, original, before);
      },
    );
  }

  for (final pin in <String?>[
    null,
    '{authored-unreadable',
    '[]',
    '{"day":"2021-04-07"}',
  ]) {
    test(
      'an unrelated legacy cache ${pin ?? 'with no cursor table'} cannot overwrite local corrections',
      () async {
        final file = await backup(pin: pin);
        final original = await file.readAsBytes();
        final before = await evidence();
        await LocalDb.importFromDbFile(file.path);
        await retained(file, original, before);
      },
    );
  }
}
