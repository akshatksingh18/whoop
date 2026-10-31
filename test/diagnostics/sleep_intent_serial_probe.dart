// Cloud-only counterfactual: isolate explicit intent from overlapping scheduling.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import '../coverage_derived_night_continuity_test.dart'
    show seedContinuityNight;
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('sleep-intent-serial'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final action in ['reject', 'clear']) {
    test(
      'serial $action must not continue serving the removed manual intent',
      () async {
        const day = '2021-04-06';
        final start = await seedContinuityNight(day);
        final app = AppState.forTesting()
          ..user = const Profile(
            ageYears: 30,
            sex: 'f',
            weightKg: 70,
            heightCm: 170,
          ).toMap();
        final repo = LocalRepositoryImpl(getProfileMap: () => app.user);
        app.repo = repo;
        addTearDown(app.dispose);
        DateTime at(int delta) =>
            DateTime.fromMillisecondsSinceEpoch((start + delta) * 1000);
        await app.setSleepOverride(day, at(900), at(9900));
        final before = await repo.getDaySleep(day);
        expect(before['has_sleep'], true);
        expect(before['sleep_source'], 'manual');
        expect(app.reanalyzing, false);
        if (action == 'reject') {
          await app.rejectSleep(day);
          expect((await LocalDb.getSleepOverride(day))!['source'], 'rejected');
        } else {
          await app.clearSleepOverride(day);
          expect(await LocalDb.getSleepOverride(day), isNull);
        }
        expect(app.reanalyzing, false);
        final after = await repo.getDaySleep(day);
        expect(
          await LocalDb.lastDecodedRecTs(),
          start + 10799,
          reason: 'The complete authored substrate must still be present',
        );
        expect(
          action == 'reject' ? after['has_sleep'] : after['sleep_source'],
          action == 'reject' ? false : isNot('manual'),
          reason: app.logLines.join('\n'),
        );
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
