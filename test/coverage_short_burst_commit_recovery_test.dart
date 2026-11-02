// Refused real SQLite writes on the short-burst path cannot permit flash trim.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyEnd, record, until;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('short-burst-commit-recovery'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final refusal in ['decoded row', 'hardware frontier']) {
    test(
      'COV-48 short gen5 burst $refusal refusal preserves the old commit and retries',
      () async {
        const ts = 1760000000;
        const oldToken = '0011223344556677';
        const newToken = '8172635445362718';
        final db = await LocalDb.instance;
        await LocalDb.commitSyncBatch(
          [
            RawRecord(
              counter: 40,
              packetType: 47,
              hex: 'authored-prior-burst',
              recTs: ts - 1,
              capturedAt: (ts - 1) * 1000,
            ),
          ],
          [
            Sample(
              tsEpoch: ts - 1,
              counter: 40,
              hr: 65,
              rrIntervalsMs: [900],
              ax: 0,
              ay: 0,
              az: 1,
            ),
          ],
          trimToken: oldToken,
          deviceFamily: 'gen5',
        );
        final savedRows = await db.query('decoded_onehz');
        final savedBeats = await db.query('decoded_rr');
        final savedHeaders = await db.query('samples');
        final logs = <String>[], writes = <List<int>>[];
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: logs.add,
        );
        void install() => engine.debugInstallFakeLink(
          band: p.BandProfile.gen5,
          onCommit: (raws, samples, token, {archives, deviceFamily}) =>
              LocalDb.commitSyncBatch(
                raws,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              ),
          onWrite: (frame) async {
            final inner = p
                .parseFrame(frame, profile: p.BandProfile.gen5)!
                .inner;
            writes.add(List.of(inner));
            if (inner[2] == p.Cmd.historicalDataResult && inner[3] == 1) {
              expect(await db.query('decoded_onehz'), hasLength(2));
              expect(await LocalDb.getCursor('strap_trim'), newToken);
            }
            return true;
          },
        );
        void rx(Uint8List frame) =>
            engine.debugReceiveFrame(p.Frame(frame, true, true));
        try {
          await db.execute(
            refusal == 'decoded row'
                ? "CREATE TRIGGER authored_short_refusal BEFORE INSERT ON decoded_onehz BEGIN SELECT RAISE(ABORT,'authored short row refusal'); END"
                : "CREATE TRIGGER authored_short_refusal BEFORE INSERT ON sync_cursor WHEN NEW.name='rec_ts_hw' BEGIN SELECT RAISE(ABORT,'authored short frontier refusal'); END",
          );
          install();
          rx(historyStart());
          rx(record(p.BandProfile.gen5));
          rx(historyEnd(count: 3));
          await until(
            () => logs.any(
              (s) => s.contains('short-count burst ALSO failed to commit'),
            ),
            attempts: 1200,
          );
          await until(() => !engine.offloadActive, attempts: 1200);
          expect(
            writes.where((f) => f[2] == p.Cmd.historicalDataResult),
            isEmpty,
            reason:
                'Neither success nor retry result may precede a durable partial commit',
          );
          expect(await db.query('decoded_onehz'), savedRows);
          expect(await db.query('decoded_rr'), savedBeats);
          expect(await db.query('samples'), savedHeaders);
          expect(await LocalDb.getCursor('strap_trim'), oldToken);
          expect(await LocalDb.getCursorInt('rec_ts_hw'), ts - 1);
          await engine.disconnect();
          await db.execute('DROP TRIGGER authored_short_refusal');
          writes.clear();
          install();
          rx(historyStart());
          rx(record(p.BandProfile.gen5));
          rx(historyEnd());
          var acked = false;
          for (var i = 0; i < 1200; i++) {
            if ((await LocalDb.syncLedgerEntry('batch:$newToken'))?['status'] ==
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
          expect(await db.query('decoded_onehz'), hasLength(2));
          expect(await db.query('decoded_rr'), savedBeats);
          expect(await LocalDb.getCursor('strap_trim'), newToken);
          expect(await LocalDb.getCursorInt('rec_ts_hw'), ts);
        } finally {
          await db.execute('DROP TRIGGER IF EXISTS authored_short_refusal');
          await engine.disconnect();
        }
      },
    );
  }
}
