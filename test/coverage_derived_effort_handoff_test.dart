// Complete authored night/activity orchestration runs only in Linux CI.
// The preflight checks the synthetic detector input, not physiological accuracy.
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_analytics/onehz.dart' as ana;
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/series_codec.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'support/coverage_store.dart';

const day = '2021-04-06';
Substrate authored() {
  final start = localDayStartSec(day)! + 3600;
  // Main sleep requires >=3 h. The earlier 2.5 h fixture correctly scored no
  // sleep, so it could not supply the nocturnal resting HR this test requires.
  const extraSleep = 2 * 3600;
  const n = 3 * 3600 + 40 * 60 + 480 + extraSleep;
  bool asleep(int i) => i >= 900 && i < 9900 + extraSleep;
  bool effort(int i) => i >= 10800 + extraSleep && i < 13200 + extraSleep;
  return Substrate(
    tsSec: [for (var i = 0; i < n; i++) start + i],
    hr: [
      for (var i = 0; i < n; i++)
        asleep(i)
            ? 60 + i ~/ 30 % 3
            : effort(i)
            ? 160
            : i >= 13200 + extraSleep
            ? (70 + 90 * math.exp(-(i - 13200 - extraSleep) / 30)).round()
            : 95,
    ],
    rrTsMs: [for (var i = 0; i < n; i++) (start + i) * 1000.0],
    rrMs: [
      for (var i = 0; i < n; i++) 1000 + 35 * math.sin(i / 4 * 2 * math.pi),
    ],
    ax: [
      for (var i = 0; i < n; i++)
        asleep(i)
            ? .001 * math.sin(i / 30)
            : i.isEven
            ? .4
            : -.4,
    ],
    ay: List.filled(n, .001),
    az: List.filled(n, 1.0),
    skinTemp: List.filled(n, null),
    skinContact: List.filled(n, null),
    spo2Red: List.filled(n, null),
    spo2Ir: List.filled(n, null),
    deviceFamily: 'gen4',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derived-effort-handoff'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  test(
    'preflight authored effort has a bounded elevated window and recoverable tail',
    () {
      final s = authored();
      final detected = ana.autoDetectWorkouts(
        hrTs: s.tsSec,
        hrBpm: s.hr,
        restingBpm: 60,
        maxBpm: 187,
        motion: ana.AutoWorkoutDetector.motionPoints(s.tsSec, s.ax, s.ay, s.az),
      );
      expect(detected.value, hasLength(1));
      expect(detected.value!.single.durationMin, inInclusiveRange(39, 41));
    },
  );
  test(
    'COV-48 ordinary night uses the all-time prior ceiling without same-day or future leakage',
    () async {
      final target = DateTime.parse(day);
      String label(int offset) => DateTime(
        target.year,
        target.month,
        target.day + offset,
      ).toIso8601String().substring(0, 10);
      for (final sample in [
        (-90, 195.0),
        (-7, 190.0),
        (0, 240.0),
        (1, 245.0),
      ]) {
        await LocalDb.putDayResult(
          dayId: label(sample.$1),
          algoVersion: kAlgoVersion,
          payloadJson: jsonEncode({
            'date': label(sample.$1),
            'device_family': 'gen4',
            'scalars': {'hr_ceiling_bpm': sample.$2},
          }),
          windowJson: '{}',
          finalized: sample.$1 != 0,
          source: 'band',
          series: {'hr_ceiling_bpm': sample.$2},
        );
      }
      final db = await LocalDb.instance;
      final preserved = await db.query(
        'metric_series',
        where: 'date != ?',
        whereArgs: [day],
        orderBy: 'date,key',
      );
      final substrate = authored();
      final samples = <Sample?>[], raws = <RawRecord>[];
      for (var i = 0; i < substrate.length; i++) {
        final ts = substrate.tsSec[i];
        raws.add(
          RawRecord(
            counter: i + 1,
            packetType: 47,
            hex: 'authored-prior-ceiling-$i',
            capturedAt: ts * 1000,
            recTs: ts,
          ),
        );
        samples.add(
          Sample(
            tsEpoch: ts,
            counter: i + 1,
            hr: substrate.hr[i],
            rrIntervalsMs: [substrate.rrMs[i].round()],
            ax: substrate.ax[i],
            ay: substrate.ay[i],
            az: substrate.az[i],
          ),
        );
      }
      await LocalDb.upsertDevice(adapterId: 'gen4');
      await LocalDb.commitSyncBatch(raws, samples, deviceFamily: 'gen4');
      final logs = <String>[], done = <String>[];
      final engine = DerivationEngine(background: true, log: logs.add);
      expect(
        await engine.run(
          const Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170),
          force: true,
          heavy: true,
          onDayDone: (d, i, n) {
            expect(i, 1);
            expect(n, 1);
            done.add(d);
          },
        ),
        1,
        reason: logs.join('\n'),
      );
      expect(done, [day]);
      final row = (await LocalDb.dayResult(day))!;
      expect(row['partial'], 0);
      expect(row['skipped'], 0);
      final bundle = SeriesCodec.decodePayloadJson(
        row['payload_json'] as String,
      )!;
      expect(bundle['device_family'], 'gen4');
      expect(bundle['zone_source'], 'observed');
      expect(bundle['zone_max_hr'], 195);
      // TRIMP/calorie basis deliberately retains the age estimate. A measured
      // ceiling moves zone bands only under the existing reviewed policy.
      expect(bundle['max_hr_used'], 187);
      expect((bundle['scalars'] as Map)['rhr'], isNotNull);
      expect(
        await db.query(
          'metric_series',
          where: 'date != ?',
          whereArgs: [day],
          orderBy: 'date,key',
        ),
        preserved,
      );
      expect(await LocalDb.lastDecodedRecTs(), substrate.tsSec.last);
      expect(engine.running, false);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'complete night publishes an unlogged effort and its recovery without manufacturing a session',
    () async {
      final center = NotificationCenter.instance,
          previous = NotificationCenter.instance.presentSink;
      final events = <NotificationEvent>[];
      center.presentSink = (e, {bool allowPermissionPrompt = true}) async {
        events.add(e);
        return true;
      };
      addTearDown(() => center.presentSink = previous);
      await const NotificationPrefs(quietEnabled: false).save();
      final logs = <String>[];
      final engine = DerivationEngine(background: true, log: logs.add);
      expect(
        await engine.deriveImportedDays(
          authored(),
          const Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170),
          {day},
        ),
        1,
        reason: logs.join('\n'),
      );
      final row = (await LocalDb.dayResult(day))!;
      final bundle = SeriesCodec.decodePayloadJson(
        row['payload_json'] as String,
      )!;
      expect((bundle['scalars'] as Map)['rhr'], isNotNull);
      final suggestions = await LocalDb.activeWorkoutSuggestions();
      expect(suggestions, hasLength(1));
      final suggestion = suggestions.single;
      expect(suggestion['date'], day);
      expect(suggestion['duration_min'], inInclusiveRange(39, 41));
      final db = await LocalDb.instance;
      expect(await db.query('sessions'), isEmpty);
      expect(events.where((e) => e.title == 'Did you work out?'), hasLength(1));
      final route = events
          .singleWhere((e) => e.title == 'Did you work out?')
          .route!;
      expect(Uri.parse(route).queryParameters['id'], suggestion['id']);
      // Logging the actual window supersedes the suggestion without deleting it.
      await LocalDb.putSession({
        'id': 'synthetic-accepted',
        'type': 'general_workout',
        'start_ts': suggestion['start_ts'],
        'end_ts': suggestion['end_ts'],
        'status': 'done',
        'source': 'manual',
        'created_at': 1,
      });
      expect(await LocalDb.activeWorkoutSuggestions(), isEmpty);
      expect(await db.query('workout_suggestions'), hasLength(1));
      expect(row['partial'], 0);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
