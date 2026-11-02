// Real GET_DATA_RANGE bytes and SQLite diagnostic storage; no hardware or loss estimate.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyEnd, record, until;
import 'support/coverage_store.dart';

Uint8List authoredRange() {
  final b = Uint8List(70);
  b.setRange(0, 6, [
    p.PacketType.commandResponse,
    17,
    p.Cmd.getDataRange,
    42,
    1,
    1,
  ]);
  ByteData.sublistView(b)
    ..setUint32(14, 1200, Endian.little)
    ..setUint32(18, 900, Endian.little)
    ..setUint32(22, 3, Endian.little)
    ..setUint32(26, 2048, Endian.little)
    ..setUint32(30, 4000, Endian.little)
    ..setUint32(34, 500, Endian.little);
  // All epoch slots remain zero. Ring telemetry does not need a valid RTC.
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('backlog-telemetry-recovery'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final mode in ['stored', 'write refused', 'store unavailable']) {
      test(
        'COV-48 ${band.type.name} backlog $mode preserves history and permits the real sync ACK',
        () async {
          final db = await LocalDb.instance;
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          await LocalDb.putBandBacklog(
            ts: now - 10,
            wrapCount: 1,
            freeRecords: 700,
            deviceFamily: band.type.name,
          );
          final prior = await LocalDb.bandBacklog();
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
            onWrite: (frame) async {
              writes.add(List.of(p.parseFrame(frame, profile: band)!.inner));
              return true;
            },
          );
          var unavailable = false;
          Future<void> stored() async {
            var done = false;
            for (var i = 0; i < 200; i++) {
              final rows = await LocalDb.bandBacklog();
              if (rows.length == 2 && rows.first['wrap_count'] == 3) {
                done = true;
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            expect(done, true, reason: logs.join('\n'));
          }

          void range() => engine.debugProcessImmediateFrame(
            p.Frame(authoredRange(), true, true),
          );
          try {
            if (mode == 'write refused') {
              await db.execute(
                "CREATE TRIGGER authored_backlog_refusal BEFORE INSERT ON band_backlog BEGIN SELECT RAISE(ABORT,'authored backlog refusal'); END",
              );
            } else if (mode == 'store unavailable') {
              await db.execute(
                'ALTER TABLE band_backlog RENAME TO authored_backlog_retained',
              );
              unavailable = true;
            }
            range();
            expect(engine.lastPagesBehind, {
              'written': 1200,
              'used': 4000,
              'capacity': 2048,
              'trim_page': 900,
              'wrap_count': 3,
              'free_records': 500,
            });
            expect(engine.strapHistoryNewestTs, isNull);
            expect(engine.state.dataRangeNewest, isNull);
            if (mode == 'stored') {
              await stored();
            } else {
              await until(
                () => logs.any(
                  (s) =>
                      s.contains('ledger write failed (non-fatal, continuing)'),
                ),
              );
              expect(
                await db.query(
                  unavailable ? 'authored_backlog_retained' : 'band_backlog',
                ),
                prior,
              );
              if (unavailable) {
                await db.execute(
                  'ALTER TABLE authored_backlog_retained RENAME TO band_backlog',
                );
                unavailable = false;
              } else {
                await db.execute('DROP TRIGGER authored_backlog_refusal');
              }
              range();
              await stored();
            }
            final rows = await LocalDb.bandBacklog();
            expect(rows.last, prior.single);
            expect(
              rows.first['device_family'],
              isNull,
              reason:
                  'A scripted wire profile alone does not establish link provenance',
            );
            expect(rows.first['written'], 1200);
            expect(rows.first['free_records'], 500);
            expect(logs.any((s) => s.contains('wrap=3 (prev=1, +2)')), true);
            for (final inner in [historyStart(), record(band), historyEnd()]) {
              engine.debugReceiveFrame(p.Frame(inner, true, true));
            }
            var acked = false;
            for (var i = 0; i < 1200; i++) {
              if ((await LocalDb.syncLedgerEntry(
                    'batch:8172635445362718',
                  ))?['status'] ==
                  'acked') {
                acked = true;
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            expect(acked, true, reason: logs.join('\n'));
            expect(
              writes.where((f) => f[2] == p.Cmd.historicalDataResult),
              hasLength(1),
            );
            expect(await LocalDb.bandBacklog(), rows);
            await engine.disconnect();
            await LocalDb.close();
            expect(await LocalDb.bandBacklog(), rows);
          } finally {
            if (unavailable) {
              await db.execute(
                'ALTER TABLE authored_backlog_retained RENAME TO band_backlog',
              );
            }
            if (db.isOpen) {
              await db.execute(
                'DROP TRIGGER IF EXISTS authored_backlog_refusal',
              );
            }
            await engine.disconnect();
          }
        },
      );
    }
  }
}
