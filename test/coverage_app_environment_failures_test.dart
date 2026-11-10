// Real AppState/SQLite/notification scheduling, with OS cancellation replaced.
// No sensor calculation or personal provisioning profile is needed here.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('app-environment-failures'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'An unreadable installed profile clears an older expiry and its two standing alerts once',
    () async {
      final app = AppState.forTesting()
        ..signingExpiry = DateTime.utc(2021, 4, 8);
      final service = NotificationService.instance;
      final previous = service.debugCancel;
      final cancelled = <int?>[];
      service.debugCancel = (id) async => cancelled.add(id);
      var notices = 0;
      app.addListener(() => notices++);
      try {
        await app.refreshSigningStatus();
        expect(app.signingExpiry, isNull);
        expect(notices, 1);
        expect(cancelled, [
          NotificationService.idSigningExpiry48,
          NotificationService.idSigningExpiry24,
        ]);
        await app.refreshSigningStatus();
        expect(notices, 1);
        expect(cancelled, [
          NotificationService.idSigningExpiry48,
          NotificationService.idSigningExpiry24,
          NotificationService.idSigningExpiry48,
          NotificationService.idSigningExpiry24,
        ]);
      } finally {
        service.debugCancel = previous;
        app.dispose();
      }
    },
  );

  test(
    'Malformed reminder preferences preserve data, log deferral and permit a repaired retry',
    () async {
      final app = AppState.forTesting();
      final service = NotificationService.instance;
      final previous = service.debugCancel;
      final cancelled = <int?>[];
      service.debugCancel = (id) async => cancelled.add(id);
      final db = await LocalDb.instance;
      await LocalDb.setCursor('authored-recovery', 'keep');
      final before = await db.query('sync_cursor');
      SharedPreferences.setMockInitialValues({
        'notif_reminders': 'authored wrong type',
      });
      try {
        await app.refreshReminders();
        expect(
          app.logLines,
          contains(contains('[notify] schedule reminders skipped:')),
        );
        expect(cancelled, isEmpty);
        SharedPreferences.setMockInitialValues({'notif_reminders': false});
        await app.refreshReminders();
        expect(cancelled, [NotificationService.idWeeklyRecap]);
        expect(await db.query('sync_cursor'), before);
      } finally {
        service.debugCancel = previous;
        app.dispose();
        await Prefs.ensureLoaded();
      }
    },
  );

  test(
    'Foreground schema check reports missing tables and keeps the 24-hour throttle',
    () async {
      final app = AppState.forTesting()
        ..paired = PairedDevice('authored-band', null);
      final db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE lab_result RENAME TO authored_held_lab_result',
      );
      try {
        await app.runCadenceChecks();
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!app.logLines.any(
              (s) => s.contains('[db] schemaHealth FAILED:'),
            ) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final failure = app.logLines.where(
          (s) => s.contains('[db] schemaHealth FAILED:'),
        );
        expect(failure, hasLength(1));
        expect(failure.single, contains('lab_result'));
        await app.runCadenceChecks();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          app.logLines.where((s) => s.contains('[db] schemaHealth FAILED:')),
          hasLength(1),
        );
        expect(await db.query('authored_held_lab_result'), isEmpty);
      } finally {
        await db.execute(
          'ALTER TABLE authored_held_lab_result RENAME TO lab_result',
        );
        app.dispose();
      }
    },
  );

  test(
    'Committed backup rows still publish when the later rollup write fails, and retry remains possible',
    () async {
      final root = await (await Directory(
        'build/coverage-remainder/app-environment-failures',
      ).absolute.create(recursive: true)).createTemp('authored-');
      final file = File('${root.path}/authored.sqlite');
      final source = await databaseFactory.openDatabase(file.path);
      await source.execute(
        'CREATE TABLE journal(date TEXT PRIMARY KEY,tags_json TEXT,note TEXT,updated_at INTEGER NOT NULL)',
      );
      await source.insert('journal', {
        'date': '2021-04-06',
        'tags_json': '["authored"]',
        'note': 'retain committed import',
        'updated_at': 1,
      });
      await source.close();
      final bytes = await file.readAsBytes();
      final app = AppState.forTesting();
      final db = await LocalDb.instance;
      await db.execute(
        "CREATE TRIGGER authored_rollup_refusal BEFORE INSERT ON baselines "
        "WHEN NEW.key='crossday_input' BEGIN SELECT RAISE(ABORT,'authored rollup refusal'); END",
      );
      try {
        final revision = app.insightsRevision.value;
        expect(await app.importEdgeBackup(file.path), 0);
        expect(app.lastImportRecords, 1);
        expect(app.importRollupError, contains('authored rollup refusal'));
        expect(app.insightsRevision.value, greaterThan(revision));
        expect(
          jsonDecode((await db.query('journal')).single['tags_json'] as String),
          ['authored'],
        );
        expect(
          (await db.query('journal')).single['note'],
          'retain committed import',
        );
        expect(await file.readAsBytes(), bytes);
        await db.execute('DROP TRIGGER authored_rollup_refusal');
        expect(await app.importEdgeBackup(file.path), 0);
        expect(app.importRollupError, isNull);
        expect(await db.query('journal'), hasLength(1));
        expect(await file.readAsBytes(), bytes);
      } finally {
        await db.execute('DROP TRIGGER IF EXISTS authored_rollup_refusal');
        app.dispose();
      }
    },
  );

  for (final value in ['-1', 'authored-invalid']) {
    for (final hasJournal in [false, true]) {
      test(
        'Invalid correction revision $value reports exactly the $hasJournal committed prefix and permits a repaired-copy retry',
        () async {
          final root = await (await Directory(
            'build/coverage-remainder/app-environment-failures',
          ).absolute.create(recursive: true)).createTemp('authored-revision-');
          final original = File('${root.path}/invalid.sqlite');
          final source = await databaseFactory.openDatabase(original.path);
          await source.execute(
            'CREATE TABLE sync_cursor(name TEXT PRIMARY KEY,value TEXT,updated_at INTEGER NOT NULL)',
          );
          await source.insert('sync_cursor', {
            'name': 'sleep_correction_revision',
            'value': value,
            'updated_at': 1,
          });
          if (hasJournal) {
            await source.execute(
              'CREATE TABLE journal(date TEXT PRIMARY KEY,tags_json TEXT,note TEXT,updated_at INTEGER NOT NULL)',
            );
            await source.insert('journal', {
              'date': '2021-04-06',
              'tags_json': '["authored"]',
              'note': 'committed prefix',
              'updated_at': 1,
            });
          }
          await source.close();
          final bytes = await original.readAsBytes();
          await LocalDb.setCursor('authored-recovery', 'keep');
          final revision = await LocalDb.sleepCorrectionRevision();
          final app = AppState.forTesting();
          final published = app.insightsRevision.value;
          try {
            await expectLater(
              app.importEdgeBackup(original.path),
              throwsA(
                isA<DbImportException>()
                    .having(
                      (e) => e.records,
                      'actual committed rows',
                      hasJournal ? 1 : 0,
                    )
                    .having(
                      (e) => e.toString(),
                      'recovery explanation',
                      contains(
                        '${hasJournal ? 1 : 0} rows committed before restore stopped. Retry the same backup to continue.',
                      ),
                    )
                    .having(
                      (e) => '${e.cause}',
                      'original refusal',
                      contains('invalid sleep correction revision'),
                    ),
              ),
            );
            expect(app.lastImportRecords, hasJournal ? 1 : 0);
            expect(
              app.importRollupError,
              hasJournal
                  ? 'Restore stopped after committed rows. Retry the backup, then rebuild if needed.'
                  : null,
            );
            expect(
              app.insightsRevision.value,
              published + (hasJournal ? 2 : 0),
            );
            expect(await LocalDb.sleepCorrectionRevision(), revision);
            expect(await LocalDb.getCursor('authored-recovery'), 'keep');
            expect(
              await (await LocalDb.instance).query('journal'),
              hasJournal ? hasLength(1) : isEmpty,
            );
            expect(await original.readAsBytes(), bytes);
            final repaired = await original.copy(
              '${root.path}/repaired.sqlite',
            );
            final fix = await databaseFactory.openDatabase(repaired.path);
            await fix.update('sync_cursor', {'value': '0'});
            await fix.close();
            expect(await app.importEdgeBackup(repaired.path), 0);
            expect(app.importRollupError, isNull);
            expect(
              await LocalDb.sleepCorrectionRevision(),
              greaterThan(revision),
            );
            expect(await original.readAsBytes(), bytes);
            expect(await LocalDb.getCursor('authored-recovery'), 'keep');
          } finally {
            app.dispose();
          }
        },
      );
    }
  }
}
