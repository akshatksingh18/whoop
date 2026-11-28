// Real history/cooldown policies, frames and SQLite. Only radio/elapsed time
// are substituted.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;

import 'durable_boundary_test.dart'
    show historyStart, historyComplete, record, until;
import '../support/coverage_store.dart';

class _PolicyRig {
  _PolicyRig(this.band) {
    engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) => states++,
      log: logs.add,
      policyNow: () => now,
    );
    install();
  }
  final p.BandProfile band;
  DateTime now = DateTime.now();
  final logs = <String>[];
  final writes = <Uint8List>[];
  int states = 0;
  late final BleEngine engine;

  void install() => engine.debugInstallFakeLink(
    band: band,
    onCommit: (raws, samples, token, {archives, deviceFamily}) =>
        SyncLedgerStore.commitBatch(
          raws,
          samples,
          trimToken: token,
          archives: archives,
          deviceFamily: deviceFamily,
        ),
    onWrite: (frame) async {
      final inner = p.parseFrame(frame, profile: band)!.inner;
      writes.add(inner);
      if (inner[2] == p.Cmd.getClock) {
        scheduleMicrotask(
          () => engine.debugAbsorbDecoded(
            p.Decoded('cmd_response', {
              'opcode': p.Cmd.getClock,
              'req_seq': inner[1],
              'cmd_status': 1,
              'clock_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            }),
          ),
        );
      }
      return true;
    },
  );
  int count(int opcode) => writes.where((inner) => inner[2] == opcode).length;
  void rx(Uint8List inner) =>
      engine.debugReceiveFrame(p.Frame(inner, true, true));
  Future<void> begin() async {
    rx(historyStart());
    await until(() => engine.offloadActive);
  }

  Future<void> complete() async {
    rx(historyComplete());
    await until(() => !engine.offloadActive);
    // The terminal's detector/ledger work follows its observable flag change.
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('ble-policy-elapsed'));
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(LocalDb.close);

  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final retire in [false, true]) {
      test(
        '${band.type.name} history floor ${retire ? 'retires an old claim' : 'spaces an accepted retry'}',
        () async {
          final rig = _PolicyRig(band);
          addTearDown(rig.engine.disconnect);
          expect(await rig.engine.debugStartHistoricalRefresh(), true);
          expect(rig.count(p.Cmd.sendHistoricalData), 1);
          rig.rx(historyStart());
          await rig.complete();
          rig.now = rig.now.add(const Duration(milliseconds: 4800));
          final next = rig.engine.debugStartHistoricalRefresh();
          await until(
            () => rig.logs.any(
              (s) => s.contains('waiting 0.20s for the 0x16 floor'),
            ),
          );
          expect(rig.count(p.Cmd.sendHistoricalData), 1);
          if (retire) await rig.engine.disconnect();
          expect(await next, !retire);
          expect(rig.count(p.Cmd.sendHistoricalData), retire ? 1 : 2);
          expect(rig.engine.offloadActive, !retire);
          expect(
            await (await LocalDb.instance).query('decoded_onehz'),
            isEmpty,
          );
          expect(await CursorStore.read('strap_trim'), isNull);
          if (retire) {
            rig.install();
            rig.now = rig.now.add(const Duration(seconds: 1));
            expect(await rig.engine.debugStartHistoricalRefresh(), true);
            expect(rig.count(p.Cmd.sendHistoricalData), 2);
          }
          expect(rig.engine.pendingCommandCount, 0);
        },
      );
    }

    test(
      '${band.type.name} completed frozen frontier escalates only after ten minutes and real progress clears it',
      () async {
        final rig = _PolicyRig(band);
        addTearDown(rig.engine.disconnect);
        rig.engine.debugAbsorbDecoded(
          p.Decoded('cmd_response', {
            'opcode': p.Cmd.getDataRange,
            'range_oldest': 1760000000,
            'range_newest': 1760000900,
          }),
        );
        await rig.begin();
        rig.rx(record(band));
        await rig.complete();
        expect(rig.engine.state.strapNeedsReboot, false);
        final db = await LocalDb.instance;
        final rows = await db.query('decoded_onehz');
        expect(rows, hasLength(1));
        final token = await CursorStore.read('strap_trim');

        rig.now = rig.now.add(const Duration(seconds: 599));
        await rig.begin();
        await rig.complete();
        expect(rig.engine.state.strapNeedsReboot, false);
        rig.now = rig.now.add(const Duration(seconds: 1));
        await rig.begin();
        await rig.complete();
        await until(
          () => rig.logs.any((s) => s.contains('stuck-strap tripped')),
        );
        expect(rig.engine.state.strapNeedsReboot, true);
        expect(await db.query('decoded_onehz'), rows);
        expect(await CursorStore.read('strap_trim'), token);

        await rig.begin();
        final newer = record(band);
        ByteData.sublistView(newer)
          ..setUint32(3, 42, Endian.little)
          ..setUint32(7, 1760000001, Endian.little);
        rig.rx(newer);
        await rig.complete();
        expect(rig.engine.state.strapNeedsReboot, false);
        final recovered = await db.query('decoded_onehz');
        expect(recovered, hasLength(2));
        expect(
          recovered.singleWhere((r) => r['ts_ms'] == 1760000000000),
          rows.single,
        );
        expect(
          rig.logs.any(
            (s) => s.contains(
              'records banked — clearing syncClockLost/strapNeedsReboot',
            ),
          ),
          true,
        );
        expect(rig.writes.any((f) => p.dangerousCmds.contains(f[2])), false);
      },
    );
  }
}
