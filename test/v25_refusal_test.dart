// Waveform records must not become 1 Hz substrate or stored biometric rows.
// Authored payloads exercise routing/refusal without distributing real PPG.

import 'package:flutter_test/flutter_test.dart';
import '../packages/protocol/test/support/synthetic_packet.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as proto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';

// Two independently authored waveform buffers.
final _v25a = syntheticHex('g4-v25-inner-0');
final _v25b = syntheticHex('g4-v25-inner-1');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await LocalDb.close();
  });

  test(
    'protocol hands us no vector at all now — and we still drop the record',
    () {
      // This used to assert the opposite: protocol handed over a "gravity"
      // vector from inner[69/71/73] and edge dropped the record anyway. Those
      // offsets were refuted on real data and protocol 60676cf stopped emitting
      // them, so `accelG` is empty — absent, not (0,0,0), the same idiom gen5's
      // `gravityG` uses. Asserted so that if the decoder changes again, whoever
      // changes it learns edge is deliberately dropping the record either way.
      final r = proto.FirmwareAwareR24Decoder().decode(proto.hexToBytes(_v25a));
      expect(r, isNotNull);
      expect(r!.histVersion, 25);
      expect(r.hr, 0, reason: 'v25 carries no heart rate');
      expect(r.accelG, isEmpty, reason: 'absent, never a still wrist');
      final s = proto.FirmwareAwareR24Decoder().decode(
        proto.hexToBytes(_v25b),
      )!;
      expect(s.accelG, isEmpty);
    },
  );

  test('decodeSubstrate drops v25 rather than banking a still wrist', () {
    // A v25-only page produces NO seconds at all — not seconds with a
    // fabricated gravity vector and hr 0.
    expect(decodeSubstrate([_v25a, _v25b]).length, 0);
  });

  test('no path banks a v25 second into decoded_onehz', () async {
    await LocalDb.close();
    LocalDb.dbName = 'v25_refusal_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/v25_refusal_test.db');

    // sample: null is the shape every non-live-drain path uses (raw-hex
    // import, the mid-ladder raw_records replay, an archive re-drive), so the
    // hex is decoded inside the DB layer — the seam that must refuse.
    await LocalDb.insertRecord(
      RawRecord(
        counter: 0,
        packetType: 47,
        hex: _v25a,
        capturedAt: 1609459200000,
      ),
      null,
    );
    final db = await LocalDb.instance;
    final n = (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM decoded_onehz',
    )).first['n'];
    expect(n, 0);
  });

  test('v25 is not re-drivable — the bytes stay archived, whole', () {
    // Adding it here would route the same fabricated vector through
    // `_decodeOneHzSample`. It is also the store RESP-15/SD-15 will need.
    expect(
      LocalDb.redrivableArchiveReasons,
      isNot(contains('undecodable_rec_v25')),
    );
  });
}
