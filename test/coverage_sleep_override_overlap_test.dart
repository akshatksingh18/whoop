// Complete authored nights and real command overlap. Run on Linux CI only.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'coverage_derived_night_continuity_test.dart' show seedContinuityNight;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('sleep-override-overlap'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final action in [
    'edit',
    'repeat',
    'confirm',
    'reject',
    'clear',
    'read refusal',
    'dispose',
    'background',
    'reset',
  ]) {
    test(
      'COV-48 real sleep correction overlap: $action',
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
        var disposed = false;
        addTearDown(() {
          if (!disposed) app.dispose();
        });
        DateTime at(int offset) =>
            DateTime.fromMillisecondsSinceEpoch((start + offset) * 1000);
        // These actions read the existing result; give them a real saved night.
        if (['confirm', 'reject', 'clear'].contains(action)) {
          expect(await app.reanalyzeAll(), 2);
          expect((await repo.getDaySleep(day))['sleep_source'], 'manual');
        }
        final entered = Completer<void>();
        Future<void>? correction, refusedRead;
        var refused = false;
        final db = await LocalDb.instance;
        app.addListener(() {
          if (app.reanalyzing &&
              app.reanalyzeProgress == 'Analyzing 1/2' &&
              !entered.isCompleted) {
            correction = switch (action) {
              'confirm' => app.confirmSleep(day),
              'reject' => app.rejectSleep(day),
              'clear' => app.clearSleepOverride(day),
              _ => app.setSleepOverride(day, at(1200), at(9600)),
            };
            entered.complete();
          }
          if (action == 'read refusal' &&
              entered.isCompleted &&
              !app.reanalyzing &&
              !refused) {
            refused = true;
            refusedRead = db.execute(
              'ALTER TABLE decoded_onehz RENAME TO authored_overlap_retained',
            );
          }
        });
        final run = app.reanalyzeAll();
        await entered.future;
        // Observe durable acceptance while the actual engine is busy. Completion
        // now waits for recalculation, so it cannot measure acceptance.
        Future<void> accepted(String source, int? onset) async {
          var observed = false;
          for (var i = 0; i < 200; i++) {
            final row = await LocalDb.getSleepOverride(day);
            final matches = action == 'clear'
                ? row == null
                : row?['source'] == source && row?['onset_ts'] == onset;
            if (matches) {
              observed = app.reanalyzing;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(
            observed,
            true,
            reason: 'The durable edit must really overlap',
          );
        }

        final source = switch (action) {
          'confirm' => 'confirmed',
          'reject' => 'rejected',
          _ => 'manual',
        };
        await accepted(
          source,
          ['confirm', 'reject'].contains(action) ? start + 900 : start + 1200,
        );
        Future<void>? later;
        if (action == 'repeat') {
          later = app.setSleepOverride(day, at(1500), at(9300));
          await accepted('manual', start + 1500);
        } else if (action == 'dispose') {
          app.dispose();
          disposed = true;
        } else if (action == 'background') {
          await app.pauseForBackground();
        } else if (action == 'reset') {
          later = app.resetAllData();
        }
        final count = await run;
        if (action != 'reset') {
          expect(count, 2, reason: app.logLines.join('\n'));
        }
        await correction;
        await later;
        if (action == 'reset') {
          expect(await LocalDb.getSleepOverride(day), isNull);
          expect(await LocalDb.dayResult(day), isNull);
          expect(await LocalDb.lastDecodedRecTs(), isNull);
          expect(app.reanalyzing, false);
          await Future<void>.delayed(const Duration(milliseconds: 550));
          expect(await LocalDb.dayResult(day), isNull);
          return;
        }
        if (action == 'background') {
          expect((await repo.getDaySleep(day))['onset_ts'], start + 900);
          await app.openSession();
          for (var i = 0; i < 300; i++) {
            if (!app.reanalyzing &&
                (await repo.getDaySleep(day))['onset_ts'] == start + 1200) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        } else if (action == 'read refusal') {
          await refusedRead;
          try {
            expect(refused, true);
            expect((await repo.getDaySleep(day))['onset_ts'], start + 900);
            expect(
              (await LocalDb.getSleepOverride(day))!['onset_ts'],
              start + 1200,
            );
          } finally {
            await db.execute(
              'ALTER TABLE authored_overlap_retained RENAME TO decoded_onehz',
            );
          }
          await app.setSleepOverride(day, at(1200), at(9600));
        }
        final override = await LocalDb.getSleepOverride(day);
        final sleep = await repo.getDaySleep(day);
        if (action == 'clear') {
          expect(override, isNull);
          expect(sleep['sleep_source'], isNot('manual'));
        } else if (action == 'reject') {
          expect(override!['source'], 'rejected');
          expect(sleep['has_sleep'], false);
        } else {
          final onset = action == 'repeat'
              ? 1500
              : action == 'confirm'
              ? 900
              : 1200;
          final offset = action == 'repeat'
              ? 9300
              : action == 'confirm'
              ? 9900
              : 9600;
          expect(override!['onset_ts'], start + onset);
          expect(override['offset_ts'], start + offset);
          expect(sleep['has_sleep'], true, reason: app.logLines.join('\n'));
          expect(sleep['sleep_source'], source);
          expect(
            sleep['onset_ts'],
            start + (action == 'dispose' ? 900 : onset),
            reason:
                'Accepted boundaries must be derived unless the owner was disposed',
          );
          expect(
            sleep['wake_ts'],
            start + (action == 'dispose' ? 9900 : offset),
          );
        }
        expect(app.reanalyzing, false);
        expect(await LocalDb.lastDecodedRecTs(), start + 10799);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
