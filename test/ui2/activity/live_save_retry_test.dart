import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/ui2.dart' show StatusCard;

import '../../data/settings_controls_test.dart' show Store;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('live-save-retry', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  testWidgets(
    'Live Retry save restores both the original pause and the latest draft entries',
    (tester) async {
      const id = 'authored-live-save-retry';
      const anchorKey = 'calculation:workout.clock.$id';
      const draftKey = 'flutter.live.session_draft';
      const trigger = 'authored_live_clock_refusal';
      final previous = SharedPreferencesStorePlatform.instance;
      final store = Store();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      final db = await LocalDb.instance;
      addTearDown(() async {
        store.refuse = null;
        await db.execute('DROP TRIGGER IF EXISTS $trigger');
        await WorkoutClock.retryPending();
        LiveDraft.clear();
        await LiveDraft.retrySave();
        WorkoutClock.current = null;
        SharedPreferencesStorePlatform.instance = previous;
        SharedPreferences.resetStatic();
        LiveDraft.debugForget();
      });
      await Prefs.ensureLoaded();
      final activity = activityByName('Yoga')!;
      final start = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
      ).subtract(const Duration(minutes: 8));
      final pause = start.add(const Duration(minutes: 5));
      final clock = WorkoutClock(id, start);
      WorkoutClock.current = clock;
      await clock.persist();
      final draft = LiveDraft.begin(activity);
      draft.put('pose', 0);
      await LiveDraft.retrySave();
      final previousAnchor = await MetricSeriesStore.baseline(anchorKey);
      final previousDraft = store.values[draftKey];
      expect(previousAnchor, isNotNull);
      expect(previousDraft, isA<String>());

      await db.execute(
        "CREATE TRIGGER $trigger BEFORE INSERT ON baselines "
        "WHEN NEW.key='$anchorKey' BEGIN SELECT RAISE(ABORT,'authored clock refusal'); END",
      );
      store.refuse = draftKey;
      clock.setPaused(true, pause);
      draft.put('pose', 1);
      draft.put('pose', 2);
      await LiveDraft.retrySave();
      await WorkoutClock.flushWrites().catchError((Object _) {});
      expect(WorkoutClock.saveError.value, isNotNull);
      expect(LiveDraft.saveError.value, isNotNull);
      await localizedPage(tester, liveFor(activity), settle: false);
      final status = find.byWidgetPredicate(
        (widget) =>
            widget is StatusCard && widget.what == 'Workout changes not saved',
      );
      expect(find.text('Retry save'), findsOneWidget);
      Future<void> retry() async {
        final dynamic onFix = tester.widget<StatusCard>(status).onFix!;
        await tester.runAsync(() async => await onFix());
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
      }

      await retry();
      expect(status, findsOneWidget);
      expect(
        await tester.runAsync(() => MetricSeriesStore.baseline(anchorKey)),
        previousAnchor,
      );
      expect(store.values[draftKey], previousDraft);

      await tester.runAsync(() => db.execute('DROP TRIGGER $trigger'));
      store.refuse = null;
      await retry();
      expect(status, findsNothing);
      expect(WorkoutClock.saveError.value, isNull);
      expect(LiveDraft.saveError.value, isNull);
      WorkoutClock.current = null;
      expect(WorkoutClock.read(id, start).pausedAt, pause);
      LiveDraft.debugForget();
      expect(LiveDraft.current?.data['pose'], 2);
      final anchor = await tester.runAsync(
        () => MetricSeriesStore.baseline(anchorKey),
      );
      expect(jsonDecode(anchor!['payload_json'] as String), clock.toJson());
      expect(await tester.runAsync(() => db.query('sessions')), isEmpty);
    },
  );
}
