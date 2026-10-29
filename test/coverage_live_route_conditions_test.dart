// Authored motion/permission inputs through real active live components.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/gps/gps_source.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('live-route-conditions');
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
  });
  for (final issue in GpsPermissionStatus.values.where(
    (s) => s != GpsPermissionStatus.granted,
  )) {
    testWidgets(
      'COV-47 live route issue ${issue.name} preserves the actual recovery action',
      (t) async {
        var retries = 0;
        final activity = activityByName('Running')!;
        LiveDraft.begin(
          activity,
          startedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        );
        await localizedPage(
          t,
          LiveMeasured(
            activity,
            feed: () => LiveFeed(
              routeIssue: issue,
              onFixRoute: () => retries++,
              bandConnected: true,
            ),
          ),
          push: true,
        );
        final content = (await readPage(t)).join(' ');
        expect(content, contains('No heart rate yet'));
        final cards = t.widgetList<StatusCard>(find.byType(StatusCard));
        final actionable = cards.where((c) => c.onFix != null);
        expect(actionable, isNotEmpty);
        await invokeControl(t, actionable.last.onFix);
        expect(retries, 1);
        expect(LiveDraft.current!.activityKey, activity.typeKey);
      },
    );
  }
  for (final name in ['Running', 'Walking', 'Cycling']) {
    for (final accurate in [false, true]) {
      testWidgets(
        'COV-47 live $name uses moving time and bounds current speed $accurate',
        (t) async {
          final activity = activityByName(name)!;
          LiveDraft.begin(
            activity,
            startedAt: DateTime.now().subtract(const Duration(minutes: 20)),
          );
          await localizedPage(
            t,
            LiveMeasured(
              activity,
              feed: () => LiveFeed(
                hr: 120,
                maxHr: 150,
                zone: 2,
                hrCurve: const [100, null, 140],
                zoneMinutes: const [1, 2, 0, 0, 0],
                calories: 80,
                strain: 2.5,
                steps: 1234,
                distanceKm: 1,
                gpsActive: true,
                movingSec: 600,
                currentSpeedMps: 1.5,
                currentSpeedAccuracyMps: accurate ? .2 : double.nan,
                bandConnected: true,
              ),
            ),
            push: true,
          );
          final text = (await readPage(t)).join(' ');
          expect(text, contains('120'));
          expect(text, contains('1.00'));
          expect(text, isNot(contains('NaN')));
          if (name != 'Cycling') {
            expect(text, contains('moving time'));
            expect(
              text,
              contains(
                accurate ? 'Latest GPS speed' : 'no valid fresh GPS speed',
              ),
            );
          }
          final pause = find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Pause',
          );
          await reveal(t, pause);
          await t.tap(pause);
          await t.pump();
          expect(LiveDraft.current!.pausedAt, isNotNull);
          await t.tap(
            find.byWidgetPredicate(
              (w) => w is Pressable && w.semanticLabel == 'Resume',
            ),
          );
          await t.runAsync(LiveDraft.retrySave);
          await t.pump();
          expect(LiveDraft.current!.pausedAt, isNull);
          t
              .state<LiveShellState>(find.byType(LiveShell))
              .didChangeAppLifecycleState(AppLifecycleState.resumed);
          await t.runAsync(LiveDraft.retrySave);
        },
      );
    }
  }
  testWidgets(
    'COV-47 LiveTick works inside and outside a running shell without fabricated elapsed time',
    (t) async {
      await localizedPage(
        t,
        Scaffold(body: LiveTick((_, elapsed) => Text('elapsed=$elapsed'))),
      );
      expect(find.text('elapsed=0'), findsOneWidget);
      final activity = activityByName('Running')!;
      LiveDraft.begin(
        activity,
        startedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      final live = LiveShell(
        activity,
        bodyFollowsClock: false,
        body: (_, _) => LiveTick((_, elapsed) => Text('elapsed=$elapsed')),
        footer: (_) => const Text('Synthetic footer'),
        result: (elapsed) => ActivityResult(
          activity,
          start: LiveDraft.current!.startedAt,
          duration: Duration(seconds: elapsed),
        ),
      );
      await localizedPage(t, live, push: true);
      expect(find.text('Synthetic footer'), findsOneWidget);
      expect(find.textContaining('elapsed=12'), findsOneWidget);
    },
  );
}
