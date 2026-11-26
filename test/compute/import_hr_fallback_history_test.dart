// Full overnight calculations run on cloud CI, never as a local targeted probe.
// Authored 1 Hz inputs enter the actual import coordinator, without band capture.
// Night samples retain measured gravity;the longer search window has sparse accel.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('import-hr-fallback-history', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final hole in [false, true]) {
    test(
      'partial-accel overnight import keeps daytime-relative fallback and refuses a four-hour record hole=$hole',
      () async {
        const previous = '2021-04-06', day = '2021-04-07';
        final begin = localDayStartSec(previous)!;
        final midnight = localDayStartSec(day)!;
        final onset = midnight - 3600, wake = midnight + 7 * 3600;
        final ts = <int>[], hr = <int>[];
        for (var t = begin; t < midnight + 8 * 3600; t++) {
          if (hole && t >= midnight + 3600 && t < midnight + 5 * 3600) {
            continue;
          }
          ts.add(t);
          hr.add(t >= onset && t < wake ? 50 : 80);
        }
        final n = ts.length;
        final sub = Substrate(
          tsSec: ts,
          hr: hr,
          rrTsMs: [],
          rrMs: [],
          ax: List.filled(n, 0.0),
          ay: List.filled(n, 0.0),
          az: [for (final t in ts) t >= onset && t < wake ? 1.0 : 0.0],
          spo2Red: List.filled(n, null),
          spo2Ir: List.filled(n, null),
          skinTemp: List.filled(n, null),
          skinContact: List.filled(n, null),
          deviceFamily: 'gen5',
        );
        final input = jsonEncode(sub.toJson());
        final db = await LocalDb.instance;
        await LocalDb.setCursor('authored-unrelated-retention', 'keep');
        final engine = DerivationEngine(background: true);
        final completed = <String>[];
        expect(
          await engine.deriveImportedDays(
            sub,
            const Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70),
            {day},
            onDayDone: completed.add,
          ),
          1,
        );
        expect(completed, [day]);
        expect(engine.running, false);
        final row = (await LocalDb.dayResult(day))!;
        final payload = jsonDecode(row['payload_json'] as String) as Map;
        final scalars = payload['scalars'] as Map;
        final window = jsonDecode(row['window_json'] as String) as Map;
        if (hole) {
          expect(payload['sleep_source'], 'none');
          expect(scalars['tst_min'], isNull);
          expect(window, isEmpty);
          expect(payload['flags'], contains('NO_SLEEP_DETECTED'));
        } else {
          expect(payload['sleep_source'], 'auto_fallback');
          expect(
            window['onset_ms'],
            inInclusiveRange((onset - 600) * 1000, (onset + 600) * 1000),
          );
          expect(
            window['offset_ms'],
            inInclusiveRange((wake - 600) * 1000, (wake + 600) * 1000),
          );
          expect(scalars['tst_min'], greaterThan(180));
          expect(payload['flags'], contains('SLEEP_FALLBACK'));
          expect(payload['day_confidence'], lessThanOrEqualTo(.6));
        }
        expect(row['rmssd'], isNull, reason: 'No beat intervals were measured');
        expect(row['readiness'], isNull);
        expect(await LocalDb.dayResult(previous), isNull);
        expect(await LocalDb.getCursor('authored-unrelated-retention'), 'keep');
        expect(jsonEncode(sub.toJson()), input);
        expect(await db.query('raw_archive'), isEmpty);
        expect(await db.query('decoded_onehz'), isEmpty);
        expect(await db.query('decoded_rr'), isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 180)),
    );
  }
}
