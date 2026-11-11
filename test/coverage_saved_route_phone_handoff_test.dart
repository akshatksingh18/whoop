// Real saved-session door,route and cached phone windows;all inputs are authored.
// Phone cadence supplements GPS;it must not add a second distance to the route.
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/motion_window.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/platform/phone_pedometer.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'coverage_session_destination_boundaries_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  final start = DateTime(2021, 4, 6, 8);
  final end = start.add(const Duration(minutes: 4));
  const id = 'authored-route-phone';
  const profile = Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70);
  late AppState app;
  final nativeCalls = <MethodCall>[];
  int sec(DateTime x) => x.millisecondsSinceEpoch ~/ 1000;
  String key(DateTime from, DateTime to) =>
      'motion.$id.${sec(from)}-${sec(to)}';
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('saved-route-phone-handoff', fresh: true);
    messenger.setMockMethodCallHandler(phoneStepsChannel, (call) async {
      nativeCalls.add(call);
      throw PlatformException(code: 'authored_no_sensor_for_old_history');
    });
  });
  setUp(() async {
    await resetCoverageStore();
    nativeCalls.clear();
    app = AppState.forTesting()..user = profile.toMap();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
  });
  tearDown(() async {
    app.dispose();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
  });
  tearDownAll(() async {
    messenger.setMockMethodCallHandler(phoneStepsChannel, null);
    await LocalDb.close();
  });

  for (final type in ['running', 'walking']) {
    for (final scenario in [
      'measured',
      'zero',
      'absent',
      'paused',
      'partial',
    ]) {
      testWidgets(
        'saved $type phone $scenario preserves GPS,metadata and honest cadence gaps',
        (t) async {
          final pause = start.add(const Duration(minutes: 1));
          final resume = start.add(const Duration(minutes: 2));
          final paused = scenario == 'paused' || scenario == 'partial';
          final saved = (await t.runAsync(() async {
            await LocalDb.putSession({
              'id': id,
              'type': type,
              'start_ts': sec(start),
              'end_ts': sec(end),
              'status': 'done',
              'private': 1,
              'rpe': 4,
              'created_at': 1617696000000,
              'source': 'manual',
            });
            await LocalDb.putSession({
              'id': 'authored-unrelated-history',
              'type': 'cycling',
              'start_ts': sec(start) - 86400,
              'end_ts': sec(end) - 86400,
              'status': 'done',
              'created_at': 1,
              'source': 'manual',
            });
            await WorkoutClock(
              id,
              start,
              end: end,
              profile: profile,
              pauses: paused ? [(start: pause, end: resume)] : [],
            ).persist();
            await LocalDb.appendRoutePoints(id, [
              for (var i = 0; i <= 16; i++)
                RoutePoint(
                  seq: i,
                  tsMs: start
                      .add(Duration(seconds: i * 15))
                      .millisecondsSinceEpoch,
                  lat: 0,
                  lng: i * .0001,
                  alt: 0,
                  accuracy: 5,
                  speed: .75,
                ).toRow(id),
            ]);
            final windows = paused
                ? [(start, pause), (resume, end)]
                : [(start, end)];
            var ordinal = 0;
            for (final (from, to) in windows) {
              final absent =
                  scenario == 'absent' ||
                  (scenario == 'partial' && ordinal == 1);
              final n = to.difference(from).inMinutes;
              final steps = [
                for (var i = 0; i < n; i++)
                  scenario == 'zero' ? 0 : (ordinal + i == 1 ? 0 : 120),
              ];
              await CalculationStore.write(
                key(from, to),
                absent
                    ? 'none'
                    : jsonEncode(
                        MotionWindow(
                          from,
                          60,
                          steps,
                          List<double>.filled(n, 1000),
                          seconds: List<double>.filled(n, 60),
                        ).toJson(),
                      ),
              );
              ordinal++;
            }
            return (
              row: (await LocalDb.session(id))!,
              other: (await LocalDb.session('authored-unrelated-history'))!,
              route: await LocalDb.routePoints(id),
              routeKm:
                  (await app.repo!.getWorkoutRoute(id))!.distanceMeters / 1000,
            );
          }))!;
          await localizedPage(
            t,
            const SessionDestination(id),
            app: app,
            settle: false,
          );
          await io(t);
          final summary = find.byType(ActivitySummary);
          expect(summary, findsOneWidget);
          final result = t.widget<ActivitySummary>(summary).result;
          expect(result.sessionId, id);
          expect(result.activity.typeKey, type);
          expect(result.private, true);
          expect(result.rpe, 4);
          expect(result.distanceKm, closeTo(saved.routeKm, .000001));
          expect(result.motionDistance, false);
          expect(result.track, isNotEmpty);
          expect(result.duration.inMinutes, paused ? 3 : 4);
          if (scenario == 'absent' || scenario == 'partial') {
            expect(result.phoneSteps, isNull);
            expect(result.cadence, isNull);
            expect(result.cadenceSeries, isEmpty);
          } else if (scenario == 'zero') {
            expect(result.phoneSteps, 0);
            expect(result.cadence, isNull);
            expect(result.cadenceSeries, [null, null, null, null]);
          } else if (paused) {
            expect(result.phoneSteps, 240);
            expect(result.cadence, 120);
            expect(result.cadenceSeries, [120, null, 120]);
          } else {
            expect(result.phoneSteps, 360);
            expect(result.cadence, 120);
            expect(result.cadenceSeries, [120, null, 120, 120]);
          }
          expect(nativeCalls, isEmpty);
          await t.runAsync(() async {
            final after = (await LocalDb.session(id))!;
            for (final name in [
              'id',
              'type',
              'start_ts',
              'end_ts',
              'private',
              'rpe',
              'source',
              'created_at',
            ]) {
              expect(after[name], saved.row[name], reason: name);
            }
            expect(
              await LocalDb.session('authored-unrelated-history'),
              saved.other,
            );
            expect(await LocalDb.routePoints(id), saved.route);
            expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          });
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
}
