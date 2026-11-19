// Legacy stores without observed IANA boundaries retain the travel hold.
// This guards actual scheduler selection, not a new timezone/calculation rule.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('legacy-travel-scope'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const savedDay = '2021-04-06';
  Future<void> seed(List<String> pending) async {
    await LocalDb.putDayResult(
      dayId: savedDay,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': {'rhr': 56},
      }),
      windowJson: '{}',
      finalized: true,
      rhr: 56,
      series: {'rhr': 56},
    );
    final db = await LocalDb.instance;
    for (var i = 0; i < pending.length; i++) {
      final ts = localDayStartSec(pending[i])! + 12 * 3600;
      await db.insert('decoded_onehz', {
        'device_id': '',
        'ts_ms': ts * 1000,
        'rec_ts': ts,
        'counter': i + 1,
        'hr': 65,
        'device_family': 'gen4',
      });
    }
    await LocalDb.putBaseline(
      'tz_travel_guard',
      jsonEncode({'offset_min': DateTime.now().timeZoneOffset.inMinutes + 180}),
    );
    expect(
      DayClock.days,
      isEmpty,
      reason:
          'This compatibility policy applies before observed day boundaries exist',
    );
  }

  for (final heavy in [false, true]) {
    for (final adjacent in ['2021-04-05', '2021-04-07']) {
      test(
        'guarded legacy $adjacent stays held across repeated heavy=$heavy passes',
        () async {
          await seed([adjacent]);
          final db = await LocalDb.instance;
          final prior = await db.query('day_result');
          final raw = await db.query('decoded_onehz');
          final metrics = await db.query('metric_series');
          final guard = await LocalDb.baseline('tz_travel_guard');
          final logs = <String>[];
          final engine = DerivationEngine(background: true, log: logs.add);
          for (var pass = 0; pass < 2; pass++) {
            expect(await engine.run(const Profile(), heavy: heavy), 0);
            expect(engine.running, false);
            expect(engine.snapshot()['scope_reason'], 'tz-travel-hold');
            expect(engine.snapshot()['scope_days'], 0);
            expect(engine.snapshot()['prepared_days'], 0);
            expect(await db.query('day_result'), prior);
            expect(await db.query('metric_series'), metrics);
            expect(await db.query('decoded_onehz'), raw);
            expect(await LocalDb.baseline('tz_travel_guard'), guard);
          }
          expect(
            logs.where((l) => l.contains('possible timezone change')),
            hasLength(2),
          );
          expect(
            await LocalDb.dayResult(adjacent),
            isNull,
            reason:
                'An all-held scope must never fall back to the newest raw day',
          );
        },
      );
    }
    test(
      'a mixed legacy scope derives only the independent day heavy=$heavy',
      () async {
        // Includes an actual prepare/day worker: run this control in Linux CI.
        const held = '2021-04-07', independent = '2021-04-10';
        await seed([held, independent]);
        final prior = await LocalDb.dayResult(savedDay);
        final guard = await LocalDb.baseline('tz_travel_guard');
        final completed = <String>[];
        final engine = DerivationEngine(background: true);
        expect(
          await engine.run(
            const Profile(),
            heavy: heavy,
            onDayDone: (day, _, _) => completed.add(day),
          ),
          1,
        );
        expect(completed, [independent]);
        expect(await LocalDb.dayResult(held), isNull);
        expect(await LocalDb.dayResult(independent), isNotNull);
        expect(await LocalDb.dayResult(savedDay), prior);
        expect(await LocalDb.baseline('tz_travel_guard'), guard);
        expect(engine.running, false);
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  }
}
