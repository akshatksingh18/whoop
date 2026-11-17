// Real drain timers, stop policy and buffered commit/retry. Clock injection
// advances wall time alongside FakeAsync; no fake radio or physical claim.
import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/models.dart';

RawRecord authored(int counter) => RawRecord(
  counter: counter,
  packetType: 47,
  hex: 'authored-waiter-$counter',
  capturedAt: (1760000000 + counter) * 1000,
  recTs: 1760000000 + counter,
);

void main() {
  for (final stop in ['idle', 'timeout', 'link-down']) {
    for (final refused in [false, true]) {
      test(
        '$stop waiter never trims its tail and retains a refused flush=$refused',
        () {
          fakeAsync((time) {
            final persisted = <int>[];
            final tokens = <String?>[];
            final logs = <String>[];
            var deny = refused;
            final drain = DrainController(
              now: time.getClock(DateTime.utc(2021, 4, 6)).now,
              onRecord: (_, _) async =>
                  throw StateError('buffered sink required'),
              onArchive: null,
              onCommit: (raws, samples, token, {archives, deviceFamily}) async {
                tokens.add(token);
                if (deny) throw StateError('authored tail transaction refused');
                persisted.addAll(raws.map((r) => r.counter));
              },
              log: logs.add,
            );
            drain.startFreshTask();
            drain.onHistoricalRecord(authored(1), null, 99);
            drain.onHistoricalRecord(authored(2), null, 99);
            SyncReport? report;
            var completions = 0;
            drain
                .awaitComplete(
                  isLinkUp: () => stop != 'link-down',
                  timeout: Duration(seconds: stop == 'timeout' ? 3 : 600),
                )
                .then((r) {
                  report = r;
                  completions++;
                });
            time.elapse(
              Duration(
                seconds: stop == 'idle'
                    ? 59
                    : stop == 'timeout'
                    ? 2
                    : 0,
              ),
            );
            expect(report, isNull);
            expect(tokens, isEmpty);
            time.elapse(const Duration(seconds: 1));
            expect(report, isNotNull);
            expect(report!.complete, false);
            expect(report!.records, 2);
            expect(report!.batches, 0);
            expect(tokens, [
              null,
            ], reason: 'A tail flush has no trim checkpoint');
            expect(drain.lastTrimAdvanced, false);
            expect(drain.bufferedRecords, refused ? 2 : 0);
            expect(persisted, refused ? isEmpty : [1, 2]);
            expect(
              logs.join(' '),
              contains(stop == 'idle' ? 'idle timeout' : 'await stop='),
            );
            if (refused) {
              deny = false;
              bool? saved;
              drain.flush().then((ok) => saved = ok);
              time.flushMicrotasks();
              expect(saved, true);
              expect(tokens, [null, null]);
              expect(persisted, [1, 2]);
              expect(drain.bufferedRecords, 0);
            }
            time.elapse(const Duration(minutes: 3));
            expect(completions, 1);
            expect(time.periodicTimerCount, 0);
            expect(drain.lastTrimAdvanced, false);
          });
        },
      );
    }
  }

  test(
    'new records refresh the idle edge without prematurely completing or spending a trim',
    () {
      fakeAsync((time) {
        final batches = <List<int>>[];
        final drain = DrainController(
          now: time.getClock(DateTime.utc(2021, 4, 6)).now,
          onRecord: (_, _) async {},
          onArchive: null,
          onCommit: (raws, samples, token, {archives, deviceFamily}) async {
            expect(token, isNull);
            batches.add(raws.map((r) => r.counter).toList());
          },
          log: (_) {},
        );
        drain.onHistoricalRecord(authored(1), null, 99);
        SyncReport? report;
        drain.awaitComplete(isLinkUp: () => true).then((r) => report = r);
        time.elapse(const Duration(seconds: 50));
        drain.onHistoricalRecord(authored(2), null, 99);
        time.elapse(const Duration(seconds: 59));
        expect(report, isNull);
        expect(batches, isEmpty);
        time.elapse(const Duration(seconds: 1));
        expect(report!.complete, false);
        expect(batches, [
          [1, 2],
        ]);
        expect(drain.lastTrimAdvanced, false);
        expect(time.periodicTimerCount, 0);
      });
    },
  );

  test(
    'a stopped waiter waits for its tail transaction once and leaves newer records buffered',
    () {
      fakeAsync((time) {
        final held = Completer<void>();
        final persisted = <int>[];
        var commits = 0;
        final drain = DrainController(
          now: time.getClock(DateTime.utc(2021, 4, 6)).now,
          onRecord: (_, _) async {},
          onArchive: null,
          onCommit: (raws, samples, token, {archives, deviceFamily}) async {
            commits++;
            expect(token, isNull);
            if (commits == 1) await held.future;
            persisted.addAll(raws.map((r) => r.counter));
          },
          log: (_) {},
        );
        drain.onHistoricalRecord(authored(1), null, 99);
        SyncReport? report;
        drain.awaitComplete(isLinkUp: () => false).then((r) => report = r);
        time.elapse(const Duration(seconds: 1));
        expect(commits, 1);
        expect(report, isNull);
        drain.onHistoricalRecord(authored(2), null, 99);
        time.elapse(const Duration(minutes: 2));
        expect(commits, 1);
        expect(report, isNull);
        held.complete();
        time.flushMicrotasks();
        expect(report!.complete, false);
        expect(persisted, [1]);
        expect(drain.bufferedRecords, 1);
        drain.flush();
        time.flushMicrotasks();
        expect(persisted, [1, 2]);
        expect(drain.bufferedRecords, 0);
        expect(time.periodicTimerCount, 0);
      });
    },
  );
}
