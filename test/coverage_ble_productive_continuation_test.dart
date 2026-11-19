// Authored real frames/SQLite. A productive completed task may request the next
// task, but that claim must not deadlock its own marker handler or lose rows.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyEnd, historyComplete, record, until;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('productive-continuation'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final refuse in [false, true]) {
      test(
        'COV-48 ${band.type.name} productive completion continues with refused=$refuse and preserves the ACKed rows',
        () async {
          final commands = <int>[], logs = <String>[];
          var refusing = refuse;
          late BleEngine engine;
          engine = BleEngine(
            onRecord: (_, _) async {},
            onState: (_) {},
            log: logs.add,
          );
          engine.debugInstallFakeLink(
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
              final op = inner[2];
              commands.add(op);
              if (op == p.Cmd.historicalDataResult) {
                expect(
                  await (await LocalDb.instance).query('decoded_onehz'),
                  hasLength(1),
                );
                expect(
                  await LocalDb.getCursor('strap_trim'),
                  '8172635445362718',
                );
              }
              if (op == p.Cmd.sendHistoricalData) return !refusing;
              if (op == p.Cmd.getClock || op == p.Cmd.getDataRange) {
                final body = Uint8List(op == p.Cmd.getClock ? 4 : 65);
                final data = ByteData.sublistView(body);
                if (op == p.Cmd.getClock) {
                  data.setUint32(
                    0,
                    DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    Endian.little,
                  );
                } else {
                  body[0] = 1;
                  data.setUint32(33, 1760000000 - 100, Endian.little);
                  // A fresh banked row proves productivity even when the reported
                  // range ends at that row. Do not invent a larger backlog target.
                  data.setUint32(57, 1760000000, Endian.little);
                }
                engine.debugProcessImmediateFrame(
                  p.Frame(
                    Uint8List.fromList([
                      p.PacketType.commandResponse,
                      17,
                      op,
                      inner[1],
                      1,
                      ...body,
                    ]),
                    true,
                    true,
                  ),
                );
              }
              return true;
            },
          );
          void rx(Uint8List inner) =>
              engine.debugReceiveFrame(p.Frame(inner, true, true));
          try {
            for (final inner in [historyStart(), record(band), historyEnd()]) {
              rx(inner);
            }
            await until(
              () => commands.contains(p.Cmd.historicalDataResult),
              attempts: 1200,
            );
            // The transport callback precedes the engine's own publication.
            for (var i = 0; i < 1200; i++) {
              if ((await LocalDb.syncLedgerEntry(
                    'batch:8172635445362718',
                  ))?['status'] ==
                  'acked') {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            expect(
              (await LocalDb.syncLedgerEntry(
                'batch:8172635445362718',
              ))?['status'],
              'acked',
            );
            final saved = await (await LocalDb.instance).query('decoded_onehz');
            rx(historyComplete());
            await until(
              () => commands.contains(p.Cmd.sendHistoricalData),
              attempts: 1200,
            );
            expect(
              commands.where((op) => op == p.Cmd.sendHistoricalData),
              hasLength(1),
            );
            expect(
              commands.where((op) => op == p.Cmd.historicalDataResult),
              hasLength(1),
            );
            expect(logs.any((s) => s.contains('auto-continue')), true);
            if (refuse) {
              await until(() => !engine.offloadActive);
              refusing = false;
              expect(await engine.debugStartHistoricalRefresh(), true);
              expect(
                commands.where((op) => op == p.Cmd.sendHistoricalData),
                hasLength(2),
              );
            }
            expect(engine.offloadActive, true);
            // The replacement round contains no records or trim token. COMPLETE
            // cannot send another ACK, overwrite the cursor or spin a third task.
            rx(historyStart());
            rx(historyComplete());
            await until(() => !engine.offloadActive, attempts: 1200);
            expect(
              await (await LocalDb.instance).query('decoded_onehz'),
              saved,
            );
            expect(await LocalDb.getCursor('strap_trim'), '8172635445362718');
            expect(
              commands.where((op) => op == p.Cmd.historicalDataResult),
              hasLength(1),
            );
            expect(
              commands.where((op) => op == p.Cmd.sendHistoricalData),
              hasLength(refuse ? 2 : 1),
            );
            expect(engine.pendingCommandCount, 0);
            expect(engine.historyPausedForClock, false);
          } finally {
            await engine.disconnect();
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}
