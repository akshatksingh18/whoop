import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/gps/live_cadence.dart';
import 'package:openstrap_edge/gps/heart_rate_drift.dart';
import 'package:openstrap_edge/gps/workout_context.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/run_voice.dart';
import 'package:openstrap_edge/ble/live_cadence.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime(2026, 10, 5, 8);
  testWidgets(
    'run and walk show live cadence, measured zero and unknown distinctly',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      if (const bool.fromEnvironment('UI_CAPTURE')) {
        await t.runAsync(() async {
          for (final family in ['Manrope', '.SF Pro Text']) {
            final loader = FontLoader(family);
            for (final file
                in Directory('assets/fonts/Manrope')
                    .listSync()
                    .whereType<File>()
                    .where((f) => f.path.endsWith('.ttf'))) {
              loader.addFont(
                file.readAsBytes().then(
                  (b) => ByteData.sublistView(Uint8List.fromList(b)),
                ),
              );
            }
            await loader.load();
          }
        });
      }
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      for (final name in ['running', 'walking']) {
        double? rate = 150;
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: RepaintBoundary(
              key: const ValueKey('live-cadence-capture'),
              child: LiveMeasured(
                activityByName(name)!,
                feed: () => LiveFeed(
                  hr: 132,
                  bandConnected: true,
                  cadence: rate,
                  cadenceSource: 'Your phone',
                  steps: 3200,
                  distanceKm: 2.5,
                  calories: 142,
                  acsmCalories: 200,
                ),
              ),
            ),
          ),
        );
        await t.pump(const Duration(seconds: 1));
        await t.ensureVisible(find.text('Cadence'));
        await t.pump();
        expect(find.text('150 steps/min'), findsOneWidget);
        expect(find.text('3200'), findsOneWidget);
        expect(find.text('kcal · active'), findsNothing);
        if (const bool.fromEnvironment('UI_CAPTURE')) {
          await t.runAsync(() async {
            final boundary = t.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('live-cadence-capture')),
            );
            final shot = await boundary.toImage(pixelRatio: 2);
            final bytes = (await shot.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            Directory('test/goldens').createSync(recursive: true);
            File(
              'test/goldens/build74-live-$name.png',
            ).writeAsBytesSync(bytes.buffer.asUint8List());
            shot.dispose();
          });
        }
        rate = 0;
        await t.pump(const Duration(seconds: 1));
        expect(find.text('0 steps/min'), findsOneWidget);
        rate = null;
        await t.pump(const Duration(seconds: 1));
        expect(find.text('Waiting for movement'), findsOneWidget);
        expect(
          find.textContaining('Cadence does not change your calorie estimate.'),
          findsNothing, // build 81: the explanation paragraph is gone
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
      }
    },
  );
  test(
    'cadence converts measured steps/second once and rejects stale/nonfinite rates',
    () {
      final r = CadenceReading.fromMap({
        'stepsPerSecond': 2.5,
        'atMs': start.millisecondsSinceEpoch,
      })!;
      expect(r.spm, 150);
      expect(r.fresh(start.add(const Duration(seconds: 20))), isTrue);
      expect(r.fresh(start.add(const Duration(seconds: 21))), isFalse);
      expect(r.fresh(start.add(const Duration(milliseconds: 20001))), isFalse);
      expect(r.fresh(start.subtract(const Duration(seconds: 5))), isFalse);
      expect(
        CadenceReading.fromMap({'stepsPerSecond': double.nan, 'atMs': 1}),
        isNull,
      );
      expect(CadenceReading.fromMap({'stepsPerSecond': -1, 'atMs': 1}), isNull);
      expect(
        CadenceReading.fromMap({'stepsPerSecond': 2, 'atMs': 1e100}),
        isNull,
      );
      expect(CadenceReading.fromMap({'stepsPerSecond': 0, 'atMs': 1})!.spm, 0);
      expect(minuteCadenceSpm(10), isNull);
      expect(minuteCadenceSpm(160), isNotNull);
      expect(sessionCadenceSpm([160]), isNull);
    },
  );
  test(
    'late native cadence cannot cross a pause or session boundary',
    () async {
      const channel = MethodChannel('openstrap/phone_cadence');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final starts = <int>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'start')
          starts.add((call.arguments as Map)['generation']);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final source = PhoneCadence();
      var changed = 0;
      Future<void> sample(int token, double rate) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('cadence', {
              'generation': token,
              'stepsPerSecond': rate,
              'atMs': start.millisecondsSinceEpoch,
            }),
          ),
          (_) => done.complete(),
        );
        await done.future;
      }

      await source.start(() => changed++);
      await sample(starts.last, 2.5);
      expect(source.reading!.spm, 150);
      final old = starts.last;
      source.stop();
      await source.start(() => changed++);
      await sample(old, 3);
      expect(source.reading, isNull);
      expect(changed, 1);
      await sample(starts.last, 2);
      expect(source.reading!.spm, 120);
      source.stop();
      expect(source.reading, isNull);
    },
  );
  List<RoutePoint> track({bool paused = false, bool faster = false}) => [
    for (var i = 0; i <= 180; i++)
      RoutePoint(
        seq: i,
        tsMs:
            start.millisecondsSinceEpoch +
            i * 10000 +
            (paused && i >= 90 ? 600000 : 0),
        lat: 0,
        lng: (i + (faster && i > 90 ? i - 90 : 0)) * .0002,
      ),
  ];
  test('HR drift requires similar pace and actual route/HR coverage', () {
    final clock = WorkoutClock(
      'drift',
      start,
      end: start.add(const Duration(minutes: 30)),
    );
    final hr = [for (var i = 0; i < 30; i++) i < 15 ? 120.0 : 130.0];
    final result = heartRateDrift(track(), hr, clock, clock.end!);
    expect(activeRouteCoverage(track(), clock, clock.end!), greaterThan(.99));
    expect(
      activeRouteCoverage([track().first, track().last], clock, clock.end!),
      0,
    );
    expect(result, isNotNull);
    expect(result!.change, closeTo(10, .001));
    expect(heartRateDrift(track(faster: true), hr, clock, clock.end!), isNull);
    expect(
      heartRateDrift(
        track(),
        [...List<double?>.filled(15, null), ...hr.skip(15)],
        clock,
        clock.end!,
      ),
      isNull,
    );
    expect(
      heartRateDrift([track().first, track().last], hr, clock, clock.end!),
      isNull,
    );
    expect(
      heartRateDrift(track(), hr, clock, clock.end!, tags: ['hills']),
      isNull,
    );
  });
  test('pause time and route seam stay out of both drift halves', () {
    final clock = WorkoutClock(
      'paused',
      start,
      end: start.add(const Duration(minutes: 40)),
      pauses: [
        (
          start: start.add(const Duration(minutes: 15)),
          end: start.add(const Duration(minutes: 25)),
        ),
      ],
    );
    final hr = [for (var i = 0; i < 30; i++) i < 15 ? 120.0 : 130.0];
    final result = heartRateDrift(track(paused: true), hr, clock, clock.end!);
    expect(
      activeRouteCoverage(track(paused: true), clock, clock.end!),
      greaterThan(.98),
    );
    expect(result, isNotNull);
    expect(result!.change, closeTo(10, .01));
  });
  test(
    'manual context is optional, terrain exclusive and unknown is retained',
    () {
      expect(workoutContext(['heat', 'flat', 'injected-weather', 'heat']), [
        'flat',
        'heat',
      ]);
      expect(toggleWorkoutContext(['flat', 'heat'], 'hills'), [
        'heat',
        'hills',
      ]);
      expect(toggleWorkoutContext(['heat'], 'heat'), isEmpty);
      expect(workoutContext(null), isEmpty);
    },
  );
  test('fortnightly comparisons do not match different recorded context', () {
    ana.TrainingObservation observation(
      int i,
      bool old,
      List<String> context,
    ) => ana.TrainingObservation(
      id: '$old-$i',
      day: old ? '2026-09-10' : '2026-09-25',
      type: 'Running',
      seconds: 1800,
      meters: 5000,
      hr: old ? 150 : 140,
      coverage: 1,
      context: context,
    );
    final rows = [
      for (var i = 0; i < 3; i++) observation(i, true, ['flat']),
      for (var i = 0; i < 3; i++) observation(i, false, ['heat']),
    ];
    expect(
      ana.compareTraining(
        rows,
        firstDay: '2026-09-01',
        splitDay: '2026-09-15',
        endDay: '2026-10-01',
      ),
      isEmpty,
    );
    final same = [
      for (var i = 0; i < 3; i++) observation(i, true, []),
      for (var i = 0; i < 3; i++) observation(i, false, []),
    ];
    expect(
      ana.compareTraining(
        same,
        firstDay: '2026-09-01',
        splitDay: '2026-09-15',
        endDay: '2026-10-01',
      ),
      isNotEmpty,
    );
  });
  test(
    'last kilometre split survives resume without replaying announcements',
    () {
      final voice = KmVoice();
      voice.update(1, 300, speak: false);
      expect(voice.lastSplitSec, 300);
      final restored = KmVoice.restore(voice.snapshot());
      expect(restored.lastSplitSec, 300);
      expect(restored.update(1.1, 330, speak: false), isNull);
      restored.update(2, 610, speak: false);
      expect(restored.lastSplitSec, 310);
    },
  );
}
