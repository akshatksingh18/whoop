// Observe real SQLite acquisition, then close the gate before its await returns.
// No fabricated queue rows or production timing seam is used.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/derive_scheduler.dart';
import 'package:whoop_companion/data/db.dart';
import 'coverage_scheduler_background_queue_test.dart' show until;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void Function()? onAcquire;
  setUpAll(() async {
    await coverageStore('scheduler-acquisition-races');
    // ignore: experimental_member_use
    databaseFactory = SqfliteDatabaseFactoryLogger(
      databaseFactoryFfiNoIsolate,
      options: SqfliteLoggerOptions(
        log: (event) {
          if (event is SqfliteLoggerSqlEvent &&
              event.sql.startsWith('SELECT * FROM compute_jobs ') &&
              onAcquire != null) {
            final action = onAcquire!;
            onAcquire = null;
            action();
          }
        },
      ),
    );
  });
  setUp(resetCoverageStore);
  tearDown(() => onAcquire = null);
  tearDownAll(LocalDb.close);

  for (final heavy in [false, true]) {
    for (final gate in ['background', 'capture', 'workout', 'reset']) {
      test(
        '$gate during ${heavy ? 'heavy' : 'light'} acquisition returns the exact durable claim',
        () async {
          final runs = <DeriveJobKind>[];
          final s = DeriveScheduler(
            run: ({required kind}) async => runs.add(kind),
            log: (_) {},
            onChanged: () {},
            holdWhileBackgrounded: true,
            lightSettle: const Duration(milliseconds: 5),
            heavySettle: const Duration(milliseconds: 5),
          );
          addTearDown(s.dispose);
          s.setOffloadActive(true);
          await s.init();
          await LocalDb.enqueueDeriveJob(
            type: heavy ? 'derive_heavy' : 'derive_light',
            reason: 'authored acquisition race',
          );
          await s.init();
          final before = (await LocalDb.computeJobs(state: 'queued')).single;
          var intercepted = false;
          void closeGate() {
            intercepted = true;
            switch (gate) {
              case 'background':
                s.setBackground(true);
              case 'capture':
                s.setOffloadActive(true);
              case 'workout':
                s.setWorkoutActive(true);
              case 'reset':
                s.suspendForReset(true);
            }
          }

          onAcquire = closeGate;
          s.setOffloadActive(false);
          await until(() => intercepted);
          // Wait for the actual requeue, not just the acquisition callback.
          Map<String, dynamic>? queued;
          for (var i = 0; i < 300; i++) {
            final rows = await LocalDb.computeJobs(state: 'queued');
            if (rows.isNotEmpty && rows.single['attempts'] == 0) {
              queued = rows.single;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(queued, isNotNull);
          expect(queued!['id'], before['id']);
          expect(queued['reason'], before['reason']);
          expect(queued['type'], before['type']);
          expect(runs, isEmpty);
          expect(await LocalDb.computeJobs(state: 'running'), isEmpty);
          expect(await LocalDb.computeJobs(state: 'failed'), isEmpty);
          switch (gate) {
            case 'background':
              s.setBackground(false);
            case 'capture':
              s.setOffloadActive(false);
            case 'workout':
              s.setWorkoutActive(false);
            case 'reset':
              s.suspendForReset(false);
              await s.init();
          }
          await until(() => runs.length == 1 && !s.running);
          expect(runs, [heavy ? DeriveJobKind.heavy : DeriveJobKind.light]);
          expect(await LocalDb.computeJobs(), isEmpty);
        },
      );
    }
  }

  test(
    'a real worker refusal marks failure, releases running state and allows a later request',
    () async {
      final errors = <Object>[];
      late DeriveScheduler s;
      var runs = 0;
      await runZonedGuarded(() async {
        s = DeriveScheduler(
          run: ({required kind}) async {
            runs++;
            if (runs == 1) throw StateError('authored worker refusal');
          },
          log: (_) {},
          onChanged: () {},
          lightSettle: const Duration(milliseconds: 5),
        );
        addTearDown(s.dispose);
        await s.init();
        await s.markStoredData();
        await until(() => errors.isNotEmpty && !s.running);
        final failed = (await LocalDb.computeJobs(state: 'failed')).single;
        expect(failed['attempts'], 1);
        expect(failed['reason'], contains('authored worker refusal'));
        expect(await LocalDb.computeJobs(state: 'running'), isEmpty);
        await s.markStoredData();
        await until(() => runs == 2 && !s.running);
        expect(await LocalDb.computeJobs(state: 'queued'), isEmpty);
        expect(
          (await LocalDb.computeJobs(state: 'failed')).single['id'],
          failed['id'],
        );
        expect(errors, hasLength(1));
      }, (error, stack) => errors.add(error));
    },
  );
}
