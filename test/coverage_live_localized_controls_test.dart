// Shipped live controls with authored counters and normalized route points.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_live_typed_detail_test.dart' show action, io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('live-localized-controls');
  });
  setUp(() async {
    await resetCoverageStore();
    LiveDraft.clear();
    await LiveDraft.retrySave();
  });
  tearDown(() async {
    LiveDraft.clear();
    await LiveDraft.retrySave();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
  });
  tearDownAll(LocalDb.close);
  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await io(t);
    await t.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester t,
    Widget live, {
    ValueNotifier<bool>? reduced,
    bool settle = true,
  }) async {
    final motion = reduced ?? ValueNotifier(true);
    if (reduced == null) addTearDown(motion.dispose);
    await localizedPage(
      t,
      ValueListenableBuilder<bool>(
        valueListenable: motion,
        builder: (c, off, _) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: off),
          child: live,
        ),
      ),
      settle: settle,
    );
    await io(t);
  }

  void begin(String name, {int ago = 240}) {
    LiveDraft.begin(
      activityByName(name)!,
      startedAt: DateTime.now().subtract(Duration(seconds: ago)),
    );
  }

  testWidgets(
    'pool and stroke changes preserve counted laps under shipped copy',
    (t) async {
      begin('Swimming');
      LiveDraft.current!
        ..put('lap_at', [40, 85])
        ..put('pool', 25)
        ..put('stroke', 0);
      await open(t, LiveSwim(activityByName('Swimming')!));
      expect(find.text('2 laps · Free'), findsOneWidget);
      for (final stroke in ['Back', 'Breast', 'Fly', 'Free']) {
        await tap(t, action('Change stroke'));
        expect(find.text('2 laps · $stroke'), findsOneWidget);
      }
      await tap(t, action('50 metre pool'));
      expect(LiveDraft.current!.data['pool'], 50);
      await tap(t, action('Add a lap'));
      expect((LiveDraft.current!.data['lap_at'] as List), hasLength(3));
      await tap(t, action('One lap fewer'));
      expect(LiveDraft.current!.data['lap_at'], [40, 85]);
      expect((await readPage(t)).join(' '), contains('LAPS'));
    },
  );
  testWidgets(
    'Yoga reaches every pose without forgetting its furthest completed position',
    (t) async {
      begin('Yoga');
      await open(t, LiveFlow(activityByName('Yoga')!));
      for (final pose in [
        'Forward fold',
        'Plank',
        'Warrior II',
        'Triangle',
        'Chair',
        'Pigeon',
        'Bridge',
        "Child's pose",
        'Savasana',
      ]) {
        await tap(t, find.text('Next pose'));
        expect(find.text(pose), findsOneWidget);
      }
      await tap(t, find.text('Previous'));
      expect(LiveDraft.current!.data['pose'], 8);
      expect(LiveDraft.current!.data['pose_max'], 9);
      expect(find.textContaining('Hold · '), findsOneWidget);
    },
  );
  testWidgets(
    'turning reduced motion on stops an already running breathing guide',
    (t) async {
      begin('Breathwork');
      final reduced = ValueNotifier(false);
      addTearDown(reduced.dispose);
      await open(
        t,
        LiveFlow(activityByName('Breathwork')!),
        reduced: reduced,
        settle: false,
      );
      await t.pump(const Duration(milliseconds: 100));
      reduced.value = true;
      await t.pumpAndSettle();
      expect(find.text('Breathe at your own pace'), findsOneWidget);
      expect(find.text('Guide only'), findsOneWidget);
      expect(t.binding.hasScheduledFrame, isFalse);
    },
  );
  testWidgets(
    'match counters close an explicit set and retain the next set separately',
    (t) async {
      begin('Tennis');
      await open(t, LiveMatch(activityByName('Tennis')!));
      await tap(t, action('YOU up'));
      await tap(t, action('OPPONENT up'));
      await tap(t, find.text('End set'));
      expect(LiveDraft.current!.data['score'], [1, 1]);
      expect(LiveDraft.current!.data['me'], 0);
      expect(find.text('Set 1'), findsOneWidget);
      await tap(t, action('YOU up'));
      expect(LiveDraft.current!.data['score'], [1, 1]);
      expect(LiveDraft.current!.data['me'], 1);
      expect(find.text('SET 2'), findsOneWidget);
    },
  );
  for (final distance in <double?>[null, 1]) {
    testWidgets(
      'normalized route preview ${distance == null ? 'discloses missing distance' : 'uses its recorded distance'}',
      (t) async {
        begin('Running');
        await open(
          t,
          LiveMeasured(
            activityByName('Running')!,
            feed: () => LiveFeed(
              hr: 120,
              steps: 1200,
              strain: 2.5,
              route: const [Offset(.1, .2), Offset(.5, .6), Offset(.8, .3)],
              distanceKm: distance,
            ),
          ),
        );
        final text = (await readPage(t)).join(' ');
        expect(text, contains('ROUTE SO FAR'));
        expect(
          text,
          contains(
            distance == null
                ? 'distance appears once the fixes settle'
                : '1.00 km from the fixes',
          ),
        );
        final frame = t.widget<ChartFrame>(
          find.byWidgetPredicate(
            (w) => w is ChartFrame && w.title == 'ROUTE SO FAR',
          ),
        );
        expect(frame.unit, 'km');
      },
    );
  }
}
