// Authored overnight observations through the ordinary coordinator. Cloud only:
// this is orchestration/preservation evidence, not physiological validation.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/sleep_profile_policy.dart';
import 'package:whoop_companion/data/db.dart';

import 'coverage_derived_night_continuity_test.dart' show seedContinuityNight;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('sleep-profile-continuation'));
  setUp(resetCoverageStore);
  tearDown(
    () async => (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_profile_refusal',
    ),
  );
  tearDownAll(LocalDb.close);
  const first = '2021-04-05', second = '2021-04-06';
  const profile = Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170);

  for (final refuse in [false, true]) {
    test(
      'a second automatic night ${refuse ? 'retains prior learning on refused fold' : 'extends learned profile exactly once'}',
      () async {
        final logs = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        await seedContinuityNight(first);
        expect(await engine.run(profile, force: true), 1);
        final original =
            (await LocalDb.baseline('sleep_user_profile'))!['payload_json']
                as String;
        expect(SleepProfilePolicy.foldedDays(original), {first});
        expect((jsonDecode(original) as Map)['nights'], 1);
        await seedContinuityNight(second);
        final db = await LocalDb.instance;
        final count = (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM decoded_onehz',
        )).single['n'];
        if (refuse) {
          await db.execute(
            "CREATE TRIGGER authored_profile_refusal BEFORE INSERT ON baselines WHEN NEW.key='sleep_user_profile' BEGIN SELECT RAISE(ABORT,'authored profile refusal'); END",
          );
        }
        expect(await engine.run(profile, force: true), 2);
        expect(engine.running, false);
        for (final day in [first, second]) {
          final row = (await LocalDb.dayResult(day))!;
          expect(row['skipped'], 0);
          expect(row['partial'], 0);
          // This short fixture supplies a staging observation without a usable
          // main-night TST. Learning must not manufacture overnight headlines.
          expect(row['rhr'], isNull);
          expect(row['rmssd'], isNull);
          expect(
            await LocalDb.sleepSessionCandidate(day, kAlgoVersion),
            isNotNull,
          );
        }
        final learned =
            (await LocalDb.baseline('sleep_user_profile'))!['payload_json']
                as String;
        expect(
          SleepProfilePolicy.foldedDays(learned),
          refuse ? {first} : {first, second},
        );
        expect((jsonDecode(learned) as Map)['nights'], refuse ? 1 : 2);
        if (refuse) {
          expect(learned, original);
          expect(
            logs.any(
              (s) =>
                  s.contains('sleep profile fold skipped for $second') &&
                  s.contains('authored profile refusal'),
            ),
            true,
          );
          await db.execute('DROP TRIGGER authored_profile_refusal');
        }
        expect(
          (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM decoded_onehz',
          )).single['n'],
          count,
        );
        // These nights are still inside finalization. A later staging pass can
        // retry a failed optional fold; a successful prior fold stays idempotent.
        expect(await engine.run(profile, force: true), 2);
        final retried =
            (await LocalDb.baseline('sleep_user_profile'))!['payload_json']
                as String;
        expect(SleepProfilePolicy.foldedDays(retried), {first, second});
        expect((jsonDecode(retried) as Map)['nights'], 2);
        if (!refuse) expect(retried, learned);
        expect(await engine.run(profile, force: true), 2);
        expect(
          (await LocalDb.baseline('sleep_user_profile'))!['payload_json'],
          retried,
        );
        expect(engine.running, false);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
