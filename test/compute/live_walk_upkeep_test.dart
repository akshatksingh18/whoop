// The open walk's recorded route owns distance only for its active windows.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/day_upkeep.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/workout_clock.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('live-walk-upkeep'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final paused in [false, true]) {
    test(
      'open GPS walk preserves route and motion ownership while paused: $paused',
      () async {
        const id = 'authored-open-walk';
        final anchor = DateTime.now().subtract(const Duration(minutes: 15));
        final day = dayLabelAt(anchor);
        final ts = math.min(
          anchor.millisecondsSinceEpoch ~/ 1000,
          localDayEndSec(day)! - 480,
        );
        final start = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        const profile = Profile(
          ageYears: 29,
          sex: 'f',
          heightCm: 171,
          weightKg: 72,
        );
        await SessionStore.put({
          'id': id,
          'type': 'walking',
          'start_ts': ts,
          'status': 'live',
          'source': 'manual',
          'created_at': ts * 1000,
        });
        await StepCoverageStore.replacePhoneForDay(
          day,
          [
            (startTs: ts, endTs: ts + 180, steps: 300),
            (startTs: ts + 180, endTs: ts + 360, steps: 300),
          ],
          distances: {'$ts-${ts + 180}': 90, '${ts + 180}-${ts + 360}': 90},
        );
        final clock = WorkoutClock.begin(id, start, profile);
        if (paused) {
          clock.setPaused(true, start.add(const Duration(minutes: 3)));
        }
        await WorkoutClock.flushWrites();
        await WorkoutRouteStore.appendPoints(id, [
          for (var i = 0; i <= 12; i++)
            RoutePoint(
              seq: i,
              tsMs: (ts + i * 30) * 1000,
              lat: 0,
              lng: i * 30 / 111195,
            ).toRow(id),
        ]);
        final row = await SessionStore.byId(id);
        final db = await LocalDb.instance;
        final motion = await db.query('live_coverage');
        final repo = LocalRepositoryImpl(getProfileMap: profile.toMap);
        final daily = await DayUpkeep.read(
          repo,
          day,
          profile,
          eaten: 0,
          runs: [],
        );

        expect(daily.steps, 600);
        expect(daily.walkedSteps, 600);
        expect(daily.runs.count, 0);
        expect(daily.parts!.run, 0);
        // The authored longitude uses a rounded metres-per-degree scale.
        expect(daily.walkingMeters, closeTo(paused ? 270 : 360, .5));
        expect(
          daily.distanceSource,
          paused
              ? 'Walking route + phone motion / estimated step length'
              : 'Recorded walking route',
        );
        expect(await SessionStore.byId(id), row);
        expect(row!['end_ts'], isNull);
        expect(await db.query('live_coverage'), motion);
        expect(WorkoutClock.current, same(clock));
      },
    );
  }
}
