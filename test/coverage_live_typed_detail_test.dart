// Restored typed workout detail -> live controls -> finish -> actual summary.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

Finder action(String name) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == name);
Future<void> io(WidgetTester t) async {
  await t.runAsync(LiveDraft.retrySave);
  await t.pump(const Duration(milliseconds: 30));
  expect(t.takeException(), isNull);
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await io(t);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ActivityResult? handed;
  setUpAll(loadAuditFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    WorkoutClock.current = null;
    LiveDraft.clear();
    await LiveDraft.retrySave();
    handed = null;
  });
  tearDown(() async {
    LiveDraft.clear();
    await LiveDraft.retrySave();
    WorkoutClock.current = null;
  });
  Future<void> open(WidgetTester t, Activity a) async {
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: w!,
        ),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              child: const Text('Open live'),
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => liveFor(
                    a,
                    host: ActivityHost(
                      onFinish: (r) async {
                        handed = r;
                        return r;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tap(t, find.text('Open live'));
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await io(t);
    });
  }

  Future<void> finish(WidgetTester t) async {
    await tap(t, action('Finish session'));
    await tap(t, find.text('Finish').last);
    expect(find.byType(ActivitySummary), findsOneWidget);
    expect(handed, isNotNull);
    expect(LiveDraft.current, isNull);
  }

  testWidgets(
    'swim lap Undo, pool and stroke survive reopening and reach the summary',
    (t) async {
      final a = activityByName('Swimming')!;
      LiveDraft.begin(
          a,
          startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        )
        ..put('lap_at', [40, 85])
        ..put('pool', 25)
        ..put('stroke', 0);
      await LiveDraft.retrySave();
      await open(t, a);
      await tap(t, action('Add a lap'));
      expect((LiveDraft.current!.data['lap_at'] as List), hasLength(3));
      await tap(t, action('One lap fewer'));
      expect(LiveDraft.current!.data['lap_at'], [40, 85]);
      await tap(t, action('50 metre pool'));
      await tap(t, action('Change stroke'));
      expect(LiveDraft.current!.data['pool'], 50);
      expect(LiveDraft.current!.data['stroke'], 1);
      await t.pumpWidget(const SizedBox());
      await io(t);
      LiveDraft.debugForget();
      await open(t, a);
      expect(find.text('2 laps · Back'), findsOneWidget);
      await finish(t);
      expect(handed!.lapSecs, [40, 45]);
      expect(handed!.poolLengthM, 50);
      expect(handed!.stroke, 'Back');
      expect(handed!.swimMetres, 100);
    },
  );
  testWidgets(
    'rowing keeps counted lap times without inventing pool distance or a stroke',
    (t) async {
      final a = activityByName('Rowing')!;
      LiveDraft.begin(
        a,
        startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      )..put('lap_at', [50, 110]);
      await LiveDraft.retrySave();
      await open(t, a);
      expect(
        find.text('Laps counted by you · distance not measured'),
        findsOneWidget,
      );
      expect(action('Change stroke'), findsNothing);
      expect(action('50 metre pool'), findsNothing);
      await finish(t);
      expect(handed!.lapSecs, [50, 60]);
      expect(handed!.poolLengthM, isNull);
      expect(handed!.stroke, isNull);
      expect(handed!.swimMetres, isNull);
    },
  );
  testWidgets(
    'yoga stepping back retains the poses already reached after reopening',
    (t) async {
      final a = activityByName('Yoga')!;
      LiveDraft.begin(
          a,
          startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        )
        ..put('pose', 2)
        ..put('pose_max', 4);
      await LiveDraft.retrySave();
      await open(t, a);
      await tap(t, find.text('Previous'));
      expect(LiveDraft.current!.data['pose'], 1);
      expect(LiveDraft.current!.data['pose_max'], 4);
      await t.pumpWidget(const SizedBox());
      await io(t);
      LiveDraft.debugForget();
      await open(t, a);
      expect(find.text('Forward fold'), findsOneWidget);
      await finish(t);
      expect(handed!.poses, [
        'Mountain',
        'Forward fold',
        'Plank',
        'Warrior II',
        'Triangle',
      ]);
      expect(handed!.breathsPerMin, isNull);
    },
  );
  testWidgets(
    'a non-yoga breathing guide records no unmeasured poses or breathing rate',
    (t) async {
      final a = activityByName('Breathwork')!;
      LiveDraft.begin(
        a,
        startedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      await LiveDraft.retrySave();
      await open(t, a);
      expect(find.text('Breathe at your own pace'), findsOneWidget);
      expect(find.text('Next pose'), findsNothing);
      await finish(t);
      expect(handed!.poses, isEmpty);
      expect(handed!.breathsPerMin, isNull);
      expect(handed!.hr, isEmpty);
    },
  );
  testWidgets(
    'paused HIIT reconstructs completed rounds from active elapsed time',
    (t) async {
      final a = activityByName('HIIT')!;
      final now = DateTime.now();
      LiveDraft.begin(a, startedAt: now.subtract(const Duration(seconds: 150)))
        ..pausedAt = now
        ..put('interval_hr', {
          '0': [240, 2],
          '1': [0, 0],
        });
      await LiveDraft.retrySave();
      await open(t, a);
      expect(find.text('ROUND 3'), findsOneWidget);
      expect(find.text('WORK'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await io(t);
      expect(find.text('ROUND 3'), findsOneWidget);
      await finish(t);
      expect(handed!.rounds, hasLength(2));
      expect(handed!.rounds.first.workSec, 45);
      expect(handed!.rounds.first.restSec, 30);
      expect(handed!.rounds.first.avgHr, 120);
      expect(handed!.rounds.last.avgHr, isNull);
      expect(handed!.duration.inSeconds, 150);
    },
  );
}
