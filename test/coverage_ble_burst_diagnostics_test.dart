// Authored packet accounting and diagnostics over the production receive queue.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyEnd, until, record;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('ble-burst-diagnostics'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    test(
      '${band.type.name} counts all three battery-pack wrappers in the same durable burst',
      () async {
        final logs = <String>[], writes = <List<int>>[];
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: logs.add,
        );
        engine.debugInstallFakeLink(
          band: band,
          onCommit: (raw, samples, token, {archives, deviceFamily}) =>
              LocalDb.commitSyncBatch(
                raw,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              ),
          onWrite: (f) async {
            writes.add(p.parseFrame(f, profile: band)!.inner);
            expect((await LocalDb.instance).isOpen, true);
            expect(await LocalDb.getCursor('strap_trim'), '8172635445362718');
            return true;
          },
        );
        try {
          engine.debugReceiveFrame(p.Frame(historyStart(), true, true));
          await until(() => engine.offloadActive);
          engine.debugReceiveFrame(p.Frame(record(band), true, true));
          for (final type in [
            p.PacketType.relativePuffinEvents,
            p.PacketType.puffinEventsFromStrap,
            p.PacketType.relativeBatteryPackConsoleLogs,
          ]) {
            engine.debugReceiveFrame(
              p.Frame(Uint8List.fromList([type, 1, 0, 0]), true, true),
              role: 'events',
            );
          }
          engine.debugReceiveFrame(p.Frame(historyEnd(count: 4), true, true));
          await until(() => writes.isNotEmpty);
          expect(writes.single[2], p.Cmd.historicalDataResult);
          expect(writes.single[3], 1);
          expect(
            logs.where((l) => l.contains('counted as a burst member')),
            hasLength(3),
          );
          expect(engine.offloadSnapshot['successful_bursts'], 1);
          expect(engine.offloadSnapshot['burst_mismatch_total'], 0);
          expect(engine.offloadSnapshot['session_gap_summary'], 'none');
        } finally {
          await engine.disconnect();
        }
      },
    );

    test(
      '${band.type.name} cross-burst gaps and regressions remain diagnostic while each received row commits',
      () async {
        final writes = <List<int>>[], logs = <String>[];
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: logs.add,
        );
        engine.debugInstallFakeLink(
          band: band,
          onCommit: (raw, samples, token, {archives, deviceFamily}) =>
              LocalDb.commitSyncBatch(
                raw,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              ),
          onWrite: (f) async {
            writes.add(p.parseFrame(f, profile: band)!.inner);
            return true;
          },
        );
        try {
          var burst = 0;
          for (final counter in [10, 15, 13]) {
            final row = record(band);
            ByteData.sublistView(row)
              ..setUint32(3, counter, Endian.little)
              ..setUint32(7, 1760000000 + counter, Endian.little);
            for (final inner in [historyStart(), row, historyEnd()]) {
              engine.debugReceiveFrame(p.Frame(inner, true, true));
            }
            burst++;
            await until(() => writes.length == burst);
          }
          expect(
            writes.every(
              (w) => w[2] == p.Cmd.historicalDataResult && w[3] == 1,
            ),
            true,
          );
          expect(
            engine.offloadSnapshot['session_gap_summary'],
            '{crossBurst=1, missing=4, backward=1}',
          );
          expect(engine.offloadSnapshot['counter_regressions_total'], 1);
          expect(
            logs.where((l) => l.contains('Record counter regressed')),
            hasLength(1),
          );
          expect(
            await (await LocalDb.instance).query('decoded_onehz'),
            hasLength(3),
          );
          expect(
            await LocalDb.getCursorInt('rec_ts_hw'),
            1760000015,
            reason:
                'A diagnostic regression cannot move the durable high-water backwards',
          );
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
  test(
    'unsolicited historical data outside its data role records the missing-start diagnostic without trimming',
    () async {
      final writes = <Uint8List>[];
      final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
      engine.debugInstallFakeLink(
        onWrite: (f) async {
          writes.add(f);
          return true;
        },
        onCommit: (raw, samples, token, {archives, deviceFamily}) =>
            LocalDb.commitSyncBatch(
              raw,
              samples,
              trimToken: token,
              archives: archives,
            ),
      );
      try {
        engine.debugReceiveFrame(
          p.Frame(record(p.BandProfile.gen4), true, true),
          role: 'cmd_from',
        );
        expect(
          engine.offloadSnapshot['last_hps_reason'],
          'historical_data_while_not_syncing',
        );
        expect(writes, isEmpty);
        expect(await LocalDb.getCursor('strap_trim'), isNull);
      } finally {
        await engine.disconnect();
      }
    },
  );
  test(
    'high-frequency enabled and disabled events update the requested mode and clear the old wake reason',
    () async {
      final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
      engine.debugInstallFakeLink(onWrite: (_) async => true);
      try {
        await engine.applyHighFreqWakeWindow(
          enabled: true,
          targetWake: DateTime(2021, 4, 6, 7),
          reason: 'synthetic-wake',
        );
        for (final id in [
          p.EventId.highFreqSyncEnabled,
          p.EventId.highFreqSyncDisabled,
        ]) {
          final b = Uint8List(12)..[0] = p.PacketType.event;
          ByteData.sublistView(b).setUint16(2, id, Endian.little);
          engine.debugReceiveFrame(p.Frame(b, true, true), role: 'events');
          expect(
            engine.offloadSnapshot['high_freq_requested'],
            id == p.EventId.highFreqSyncEnabled,
          );
        }
        expect(engine.offloadSnapshot['high_freq_reason'], isNull);
        expect(engine.offloadSnapshot['high_freq_until_ms'], isNull);
      } finally {
        await engine.disconnect();
      }
    },
  );
}
