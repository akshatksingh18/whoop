// A retained record without a precomputed timestamp keeps its own wire time.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as protocol;

import 'decode_integrity_test.dart' show hex, record;
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('legacy-wire-timestamp-ownership'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final version in [10, 24]) {
    test(
      'legacy R$version advances the durable frontier by its recorded time',
      () async {
        final wire = hex(record(version, 4));
        final decoded = protocol.decodeRecord(wire)!;
        final own = decoded.ts;
        final captured = (own + 3 * 86400) * 1000;
        final raw = RawRecord(
          counter: 1,
          packetType: protocol.PacketType.historicalData,
          hex: wire,
          capturedAt: captured,
        );
        final sample = Sample(tsEpoch: own, counter: 1, hr: decoded.hr);
        expect(raw.recTs, isNull);
        await LocalDb.upsertDevice(adapterId: 'gen4');

        Future<void> commit() =>
            SyncLedgerStore.commitBatch([raw], [sample], deviceFamily: 'gen4');
        await commit();
        expect(await CursorStore.readInt('rec_ts_hw'), own);
        expect(await CursorStore.readInt('counter_hw'), 1);
        final fresh = (await ComputeFreshnessStore.read('capture'))!;
        final receipt = jsonDecode(fresh['payload_json'] as String) as Map;
        expect(receipt['latest_raw_rec_ts'], own);
        final rows = await (await LocalDb.instance).query('samples');
        expect(rows.single, containsPair('ts', own));
        expect(rows.single, containsPair('hr', decoded.hr));

        await commit();
        expect(await (await LocalDb.instance).query('samples'), rows);
        expect(await CursorStore.readInt('rec_ts_hw'), own);
      },
    );
  }
}
