// Real SQLite queue and coordinator policy. The injected platform policy does
// not claim an OS background wake, native worker budget or physical acceptance.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/derive_scheduler.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 300 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), true, reason: 'Authored queue handoff must settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('scheduler-background-queue'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  DeriveScheduler make({
    required Future<void> Function({required DeriveJobKind kind}) run,
    bool hold = true,
    bool Function()? busy,
    List<String>? logs,
  }) {
    final s = DeriveScheduler(
      run: run,
      engineBusy: busy ?? () => false,
      holdWhileBackgrounded: hold,
      log: (s) => logs?.add(s),
      onChanged: () {},
      lightSettle: const Duration(milliseconds: 5),
      heavySettle: const Duration(milliseconds: 5),
    );
    addTearDown(s.dispose);
    return s;
  }

  test(
    'background hold keeps coalesced heavy intent durable and foreground drains it once',
    () async {
      final runs = <DeriveJobKind>[], logs = <String>[];
      final s = make(
        run: ({required kind}) async => runs.add(kind),
        logs: logs,
      );
      await s.init();
      final gen = DeriveStop.generation;
      s.setBackground(true);
      s.setBackground(true);
      await s.markStoredData();
      s.requestHeavy();
      await until(() => !s.pendingLight && s.pendingHeavy);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(runs, isEmpty);
      expect(
        DeriveStop.generation,
        gen,
        reason: 'No worker is running to cancel',
      );
      expect(s.snapshot()['background'], true);
      expect(
        await LocalDb.computeJobs(state: 'queued', limit: 10),
        hasLength(1),
      );
      expect(logs.where((s) => s.contains('backgrounded')), hasLength(1));
      s.setBackground(false);
      s.setBackground(false);
      await until(() => runs.length == 1 && !s.running);
      expect(runs, [DeriveJobKind.heavy]);
      expect(await LocalDb.computeJobs(state: 'queued', limit: 10), isEmpty);
      expect(await LocalDb.computeJobs(state: 'failed', limit: 10), isEmpty);
      expect(logs.where((s) => s.contains('foregrounded')), hasLength(1));
    },
  );

  test(
    'a nonholding platform policy keeps queued work runnable without a stop request',
    () async {
      var runs = 0;
      final s = make(hold: false, run: ({required kind}) async => runs++);
      await s.init();
      final gen = DeriveStop.generation;
      s.setBackground(true);
      await s.markStoredData();
      await until(() => runs == 1 && !s.running);
      expect(s.snapshot()['background'], false);
      expect(DeriveStop.generation, gen);
      expect(await LocalDb.computeJobs(state: 'queued', limit: 10), isEmpty);
    },
  );

  test(
    'a detached busy engine receives one stop even when the scheduler itself is idle',
    () async {
      var runs = 0, busy = true;
      final s = make(busy: () => busy, run: ({required kind}) async => runs++);
      await s.init();
      final gen = DeriveStop.generation;
      s.setBackground(true);
      expect(DeriveStop.generation, gen + 1);
      expect(s.running, false);
      s.setBackground(true);
      expect(DeriveStop.generation, gen + 1);
      busy = false;
      s.setBackground(false);
      expect(runs, 0);
      expect(s.snapshot()['background'], false);
    },
  );

  test(
    'background cancellation requeues the same running job without spending an attempt',
    () async {
      var runs = 0;
      final entered = Completer<void>(), release = Completer<void>();
      final s = make(
        run: ({required kind}) async {
          final gen = DeriveStop.generation;
          runs++;
          if (runs == 1) {
            entered.complete();
            await release.future;
            DeriveStop.check(gen);
          }
        },
      );
      await LocalDb.putMetricSeriesValue('2021-04-06', 'steps', 1234);
      await s.init();
      await s.markStoredData();
      await entered.future.timeout(const Duration(seconds: 2));
      final claimed = (await LocalDb.computeJobs(
        state: 'running',
        limit: 10,
      )).single;
      s.setBackground(true);
      release.complete();
      await until(() => !s.running && s.pendingLight);
      final queued = (await LocalDb.computeJobs(
        state: 'queued',
        limit: 10,
      )).single;
      expect(queued['id'], claimed['id']);
      expect(queued['attempts'], 0);
      expect(await LocalDb.computeJobs(state: 'failed', limit: 10), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(runs, 1);
      s.setBackground(false);
      await until(() => runs == 2 && !s.running);
      expect(await LocalDb.computeJobs(state: 'queued', limit: 10), isEmpty);
      final values = await LocalDb.metricSeries('steps');
      expect(values.single['value'], 1234);
    },
  );

  test('foreground release does not bypass an active capture hold', () async {
    var runs = 0;
    final s = make(run: ({required kind}) async => runs++);
    await s.init();
    s.setOffloadActive(true);
    s.setBackground(true);
    await s.markStoredData();
    s.setBackground(false);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(s.offloadActive, true);
    expect(s.snapshot()['background'], false);
    expect(runs, 0);
    expect(await LocalDb.computeJobs(state: 'queued', limit: 10), hasLength(1));
    s.setOffloadActive(false);
    await until(() => runs == 1 && !s.running);
    expect(await LocalDb.computeJobs(state: 'queued', limit: 10), isEmpty);
  });

  test(
    'restart recovers the old claim but keeps it durable until foreground',
    () async {
      await LocalDb.enqueueDeriveJob(
        type: 'derive_heavy',
        reason: 'authored restart',
      );
      final prior = (await LocalDb.takeNextComputeJob())!;
      final runs = <DeriveJobKind>[];
      final s = make(run: ({required kind}) async => runs.add(kind));
      s.setBackground(true);
      await s.init();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(runs, isEmpty);
      final queued = (await LocalDb.computeJobs(
        state: 'queued',
        limit: 10,
      )).single;
      expect(queued['id'], prior['id']);
      expect(s.pendingHeavy, true);
      s.setBackground(false);
      await until(() => runs.length == 1 && !s.running);
      expect(runs, [DeriveJobKind.heavy]);
      expect(await LocalDb.computeJobs(state: 'queued', limit: 10), isEmpty);
      expect(await LocalDb.computeJobs(state: 'failed', limit: 10), isEmpty);
    },
  );
}
