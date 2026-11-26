// The same real SQL refusal gets a different outcome when its owner stops.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derive-cancelled-read-refusal', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final stop in [false, true]) {
    test(
      'a refused first derivation read honours a concurrent stop: $stop',
      () async {
        const date = '2021-04-06';
        await LocalDb.putDayResult(
          dayId: date,
          algoVersion: kAlgoVersion,
          payloadJson: '{"scalars":{"rhr":61}}',
          windowJson: '{}',
          rhr: 61,
          series: {'rhr': 61},
        );
        final db = await LocalDb.instance;
        final stored = await db.query('day_result');
        final series = await db.query('metric_series');
        final logs = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        await db.execute(
          'ALTER TABLE decoded_onehz RENAME TO authored_held_decoded_onehz',
        );
        try {
          final pending = engine.run(const Profile());
          expect(engine.running, isTrue);
          if (stop) {
            DeriveStop.request('authored background transition');
            await expectLater(pending, throwsA(isA<DeriveCancelled>()));
            expect(logs, contains(contains('derive stopped mid-step')));
            expect(
              logs.where((line) => line.startsWith('derive ERROR')),
              isEmpty,
            );
          } else {
            expect(await pending, 0);
            expect(logs, contains(contains('derive ERROR')));
            expect(logs, contains(contains('no such table: decoded_onehz')));
          }
          expect(engine.running, isFalse);
          expect(await db.query('day_result'), stored);
          expect(await db.query('metric_series'), series);
        } finally {
          await db.execute(
            'ALTER TABLE authored_held_decoded_onehz RENAME TO decoded_onehz',
          );
        }
        logs.clear();
        expect(await engine.run(const Profile()), 0);
        expect(logs, contains(contains('derive: no decoded data')));
        expect(engine.running, isFalse);
        expect(await db.query('day_result'), stored);
        expect(await db.query('metric_series'), series);
      },
    );
  }
}
