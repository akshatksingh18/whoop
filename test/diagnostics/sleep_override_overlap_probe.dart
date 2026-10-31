// Cloud-only diagnostic using the verified complete-night fixture and public commands.
// Run explicitly through sleep-correction-probe.yml; it is not combined coverage.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/state/app_state.dart';
import '../coverage_derived_night_continuity_test.dart'
    show seedContinuityNight;
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('sleep-override-overlap-probe'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  test(
    'a sleep correction accepted during real reanalysis reaches its derived window',
    () async {
      const day = '2021-04-06';
      final start = await seedContinuityNight(day);
      final older = localDayStartSec('2021-04-05')! + 43200;
      await LocalDb.insertRecord(
        RawRecord(
          counter: 1,
          packetType: 47,
          hex: 'authored-overlap-older',
          recTs: older,
          capturedAt: older * 1000,
        ),
        Sample(tsEpoch: older, counter: 1, hr: 60, ax: 0, ay: 0, az: 1),
      );
      await LocalDb.putSleepOverride(
        dayId: day,
        onsetTs: start + 900,
        offsetTs: start + 9900,
        source: 'manual',
      );
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
      Future<void>? correction;
      bool? acceptedWhileBusy;
      var started = false;
      app.addListener(() {
        if (app.reanalyzing &&
            app.reanalyzeProgress == 'Analyzing 1/2' &&
            !started) {
          started = true;
          correction = app
              .setSleepOverride(
                day,
                DateTime.fromMillisecondsSinceEpoch((start + 1200) * 1000),
                DateTime.fromMillisecondsSinceEpoch((start + 9600) * 1000),
              )
              .then((_) {
                acceptedWhileBusy = app.reanalyzing;
              });
        }
      });
      expect(await app.reanalyzeAll(), 2, reason: app.logLines.join('\n'));
      expect(
        started,
        true,
        reason:
            'Use the actual first-day completion, without faking busy state',
      );
      await correction!;
      expect(
        acceptedWhileBusy,
        true,
        reason: 'The correction must actually overlap the command',
      );
      final override = (await LocalDb.getSleepOverride(day))!;
      expect(override['onset_ts'], start + 1200);
      expect(override['offset_ts'], start + 9600);
      final sleep = await repo.getDaySleep(day);
      expect(sleep['has_sleep'], true, reason: app.logLines.join('\n'));
      expect(sleep['sleep_source'], 'manual');
      expect(
        sleep['onset_ts'],
        start + 1200,
        reason:
            'Accepted manual boundaries must not leave a stale calculated window',
      );
      expect(sleep['wake_ts'], start + 9600);
      expect(app.reanalyzing, false);
      expect(await LocalDb.lastDecodedRecTs(), start + 10799);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
