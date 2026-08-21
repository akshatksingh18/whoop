// SLP-05's routing half, REFUSED — and the refusal pinned so a future wave
// cannot reintroduce it by accident.
//
// `_parseV25` returns an `accelG` that is not an accelerometer reading. On all
// 28,395 v25 records in the real `whoop-4.db` export the "z" axis takes three
// distinct values (0, 1, 256), the "y" seventeen (68% of them the single value
// 2896), and the "x" is the upper half of a little-endian f32 that starts two
// bytes earlier — which is the whole reason |g| sits near 0.97 and passes
// protocol's own plausibility window. Against the v24 record for the SAME
// second the per-axis correlation is 0.16 / 0.22 / 0.06 and the median angle
// between the two vectors is 83°.
//
// A near-constant vector reads downstream as a perfectly still wrist, which is
// exactly what van Hees immobility would consume it as. So v25 must not reach
// `Substrate` or `decoded_onehz` through ANY seam.
//
// The two hexes below are real records lifted verbatim from `whoop-4.db`'s
// `raw_archive` (reason `undecodable_rec_v25`).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' as proto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';

// Two consecutive v25 seconds, 76-byte inner each.
const _v25a =
    '2f190000000000358a776ad83a1e00f55101006a008000890094008e00a600750061ffc3'
    'fea3fee6fe2bff70ffe8ff1c0048001e001b001c002e0040005a006800640000ae143c50'
    '0b000000';
const _v25b =
    '2f190001000000368a776ae8351e009852010090009800a2007d0083ff9bfe70fe8bfebf'
    'fe30ff83ffdbff180019001000f9ff250026003e00520065007000870086000012ea3b50'
    '0b000000';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await LocalDb.close();
  });

  test('protocol hands us no vector at all now — and we still drop the record',
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
    final s = proto.FirmwareAwareR24Decoder().decode(proto.hexToBytes(_v25b))!;
    expect(s.accelG, isEmpty);
  });

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
        capturedAt: 1786078529000,
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
