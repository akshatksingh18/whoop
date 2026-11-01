// Real frame routing, gate, refusal ledger and reconnect escalation. The
// peripheral refuses writes; no command is delivered to hardware.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'build90_decode_integrity_test.dart' show record;
import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyEnd, until;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('ble-refusal-escalation'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final last in [false, true]) {
      for (final timeout in [false, true]) {
        test(
          'COV-48 ${band.type.name} refused INIT last=$last timeout=$timeout releases history and its retry floor',
          () async {
            final attempts = <int>[], delivered = <int>[], logs = <String>[];
            var refusing = true;
            final failAt = last
                ? (band.isGen5 ? 1 : p.initPackets.length - 1)
                : 0;
            final engine = BleEngine(
              onRecord: (_, _) async {},
              onState: (_) {},
              log: logs.add,
            );
            engine.debugInstallFakeLink(
              band: band,
              onWrite: (frame) async {
                final inner = p.parseFrame(frame, profile: band)!.inner;
                final op = inner[2];
                attempts.add(op);
                if (refusing && attempts.length == failAt + 1) {
                  if (timeout) {
                    throw TimeoutException('authored GATT write timeout');
                  }
                  return false;
                }
                delivered.add(op);
                if (op == p.Cmd.getClock) {
                  final payload = Uint8List(4);
                  ByteData.sublistView(payload).setUint32(
                    0,
                    DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    Endian.little,
                  );
                  engine.debugReceiveFrame(
                    p.Frame(
                      Uint8List.fromList([
                        p.PacketType.commandResponse,
                        17,
                        op,
                        inner[1],
                        1,
                        ...payload,
                      ]),
                      true,
                      true,
                    ),
                  );
                }
                return true;
              },
            );
            try {
              // A failed INIT does not invalidate this live link; it rolls back
              // the pre-armed drain so an ordinary foreground catch-up may retry.
              expect(await engine.debugStartInitDrain(), true);
              expect(attempts, hasLength(failAt + 1));
              expect(delivered, isNot(contains(p.Cmd.sendHistoricalData)));
              expect(engine.offloadActive, false);
              expect(
                logs.any((l) => l.contains('INIT did not fully write')),
                true,
              );
              expect(logs.any((l) => l.contains('write timeout:')), timeout);
              refusing = false;
              attempts.clear();
              delivered.clear();
              expect(await engine.requestForegroundSync(), true);
              expect(delivered, [
                p.Cmd.getDataRange,
                p.Cmd.getClock,
                p.Cmd.sendHistoricalData,
              ]);
              expect(engine.offloadActive, true);
              final written = attempts.length;
              expect(await engine.requestForegroundSync(), false);
              expect(attempts, hasLength(written));
              expect(await LocalDb.getCursor('strap_trim'), isNull);
              expect(
                await (await LocalDb.instance).query('decoded_onehz'),
                isEmpty,
              );
            } finally {
              await engine.disconnect();
            }
          },
        );
      }
    }
  }
  test(
    'drop-only history never ACKs and three failed clock remedies become visible across reconnects',
    () async {
      final logs = <String>[], writes = <int>[];
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: logs.add,
      );
      final future = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7 * 86400;
      final db = await LocalDb.instance;
      try {
        for (var attempt = 1; attempt <= 9; attempt++) {
          engine.debugInstallFakeLink(
            onWrite: (f) async {
              writes.add(p.parseFrame(f)!.inner[2]);
              return false;
            },
            onCommit: (raw, samples, token, {archives, deviceFamily}) =>
                LocalDb.commitSyncBatch(
                  raw,
                  samples,
                  trimToken: token,
                  archives: archives,
                  deviceFamily: deviceFamily,
                ),
          );
          final packet = record(24, 1);
          ByteData.sublistView(packet)
            ..setUint32(3, attempt, Endian.little)
            ..setUint32(7, future + attempt, Endian.little);
          for (final inner in [historyStart(), packet, historyEnd()]) {
            engine.debugReceiveFrame(p.Frame(inner, true, true));
          }
          await until(
            () =>
                logs.where((l) => l.contains('has no durable rows')).length ==
                attempt,
          );
          // Wait for the actual ledger write, rather than observing its preceding log.
          Map<String, dynamic>? ledger;
          for (var i = 0; i < 200; i++) {
            ledger = await LocalDb.syncLedgerEntry('batch:8172635445362718');
            if (ledger?['last_error'] == 'no_durable_progress' &&
                jsonDecode(
                      ledger!['meta_json'] as String,
                    )['no_durable_refuse_streak'] ==
                    attempt % 3 &&
                jsonDecode(
                      ledger['meta_json'] as String,
                    )['no_durable_remedy_cycles'] ==
                    attempt ~/ 3) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(ledger!['status'], 'trim_refused');
          final meta = jsonDecode(ledger['meta_json'] as String) as Map;
          expect(meta['no_durable_refuse_streak'], attempt % 3);
          expect(meta['no_durable_remedy_cycles'], attempt ~/ 3);
          if (attempt % 3 == 0) {
            await until(() => !engine.offloadActive, attempts: 1200);
          }
          expect(writes.where((c) => c == p.Cmd.historicalDataResult), isEmpty);
          expect(await LocalDb.getCursor('strap_trim'), isNull);
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(engine.state.syncClockLost, attempt == 9);
          await engine.disconnect();
        }
        expect(
          logs.where((l) => l.contains('defensive SET_CLOCK + bounce')),
          hasLength(3),
        );
        expect(
          logs.where((l) => l.contains('surfacing syncClockLost')),
          hasLength(1),
        );
        expect(writes.where((c) => c == p.Cmd.setClock), hasLength(3));
        final archived = await db.query('raw_archive');
        expect(
          archived,
          isEmpty,
          reason:
              'Drop-only bursts do not assert durable progress; no ACK permits a flash trim',
        );
      } finally {
        await engine.disconnect();
      }
    },
  );

  for (final version in [10, 12]) {
    test(
      'historical revision $version carries accepted beats and does not invent a missing channel',
      () async {
        final samples = <Sample>[], logs = <String>[];
        final engine = BleEngine(
          onRecord: (s, _) async {
            if (s != null) samples.add(s);
          },
          onState: (_) {},
          log: logs.add,
        );
        final packet = record(version, 4);
        // This retains the four-slot prefix case. The approved independent
        // R10 eight-slot contract has separate codec and durable-ingest checks.
        if (version == 10) {
          for (var i = 0; i < 4; i++) {
            ByteData.sublistView(
              packet,
            ).setInt16(19 + i * 2, 800 + i, Endian.little);
          }
        }
        final bounded = version == 12
            ? Uint8List.sublistView(packet, 0, 88)
            : packet;
        try {
          engine.debugIngestHistoricalFrame(p.Frame(bounded, true, true));
          await until(() => samples.isNotEmpty);
          expect(samples.single.rrIntervalsMs, [800, 801, 802, 803]);
          expect(samples.single.hr, 60);
          if (version == 10) {
            expect([
              samples.single.ax,
              samples.single.ay,
              samples.single.az,
            ], everyElement(isNull));
          } else {
            expect(samples.single.az, 1);
          }
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
}
