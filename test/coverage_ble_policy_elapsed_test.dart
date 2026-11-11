// Real history/cooldown policies, frames and SQLite. Only radio/elapsed time are
// substituted. Bonding controls exercise the portable sequence, not iPhone bonds.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/adapters/_registry.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;

import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyComplete, record, until;
import 'support/coverage_store.dart';

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
        LocalDb.commitSyncBatch(
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

class _RefusedBond implements GattBootstrapOps {
  int subscriptions = 0;
  @override
  bool get bondingApplies => true;
  @override
  Future<void> preferLe2mPhy() async {}
  @override
  Future<BandEntry?> discoverAndValidate() async => kWhoopGen5;
  @override
  Future<int> requestMtu(int mtu) async => mtu;
  @override
  Future<bool> isBonded() async => false;
  @override
  Future<void> createBond() async => throw StateError('authored bond refusal');
  @override
  Future<void> subscribe(String role) async {
    subscriptions++;
  }

  @override
  Future<bool> subscribeOptionalMemfault() async {
    subscriptions++;
    return true;
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
          expect(await LocalDb.getCursor('strap_trim'), isNull);
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
        final token = await LocalDb.getCursor('strap_trim');

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
        expect(await LocalDb.getCursor('strap_trim'), token);

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

  test(
    'five actual bootstrap bond refusals pause, retain the guide during cooldown and rearm at its exact boundary',
    () async {
      final rig = _PolicyRig(p.BandProfile.gen5);
      addTearDown(rig.engine.disconnect);
      final ops = _RefusedBond();
      for (var i = 1; i <= 5; i++) {
        if (i > 1) rig.install();
        expect(await rig.engine.debugConnectGen5Official(ops), false);
        expect(rig.engine.state.bondRefusals, i);
        expect(rig.engine.state.autoReconnectPaused, i == 5);
      }
      expect(ops.subscriptions, 0);
      expect(rig.writes, isEmpty);
      expect(rig.engine.state.needsRepairGuide, true);
      final notifications = rig.states;
      expect(rig.engine.refreshAutoReconnectPause(), true);
      rig.now = rig.now.add(
        const Duration(minutes: 30) - const Duration(milliseconds: 1),
      );
      expect(rig.engine.refreshAutoReconnectPause(), true);
      expect(rig.states, notifications);
      rig.now = rig.now.add(const Duration(milliseconds: 1));
      expect(rig.engine.refreshAutoReconnectPause(), false);
      expect(rig.engine.state.autoReconnectPaused, false);
      expect(rig.engine.state.needsRepairGuide, false);
      expect(rig.engine.state.bondRefusals, 0);
      expect(rig.states, notifications + 1);
      expect(rig.engine.refreshAutoReconnectPause(), false);
      expect(rig.states, notifications + 1);
      rig.install();
      expect(await rig.engine.debugConnectGen5Official(ops), false);
      expect(rig.engine.state.bondRefusals, 1);
      expect(rig.engine.state.autoReconnectPaused, false);
      expect(rig.engine.state.needsRepairGuide, true);
    },
  );
}
