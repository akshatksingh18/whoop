// The headless engine's single-record sink stores through the app's own
// storage. Production drains commit in batches; this pins the direct sink.
// Authored record and sample; no radio.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/sync/background_sync.dart';
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('headless-engine-sink'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test('a single headless record lands in the decoded ledger', () async {
    const ts = 1617700000;
    await headlessEngine().onRecord(
      Sample(tsEpoch: ts, counter: 7, hr: 61, ax: 0, ay: 0, az: 1),
      RawRecord(
        counter: 7,
        packetType: 47,
        hex: 'authored-headless-record',
        capturedAt: ts * 1000,
        recTs: ts,
      ),
    );
    final rows = await (await LocalDb.instance).query('decoded_onehz');
    expect(rows, hasLength(1));
    expect(rows.single['ts_ms'], ts * 1000);
  });
}
