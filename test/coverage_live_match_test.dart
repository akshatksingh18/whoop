// Typed match scores through the live controls, durable draft and summary.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

Finder action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
Future<void> io(WidgetTester t) async {
  await t.runAsync(LiveDraft.retrySave);
  await t.pump(const Duration(milliseconds: 20));
  expect(t.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final activity = allActivities.firstWhere((a) => a.name == 'Tennis');
  setUpAll(loadAuditFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    WorkoutClock.current = null;
    LiveDraft.clear();
    await LiveDraft.retrySave();
  });
  tearDown(() async {
    LiveDraft.clear();
    await LiveDraft.retrySave();
    WorkoutClock.current = null;
  });
  Future<void> open(
    WidgetTester t, {
    int me = 0,
    int them = 0,
    List<int> sets = const [],
  }) async {
    LiveDraft.begin(
        activity,
        startedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      )
      ..put('me', me)
      ..put('them', them)
      ..put('score', sets);
    await LiveDraft.retrySave();
    t.view.physicalSize = const Size(390, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: LiveMatch(activity),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(action(label));
    await t.pumpAndSettle();
    await t.tap(action(label));
    await io(t);
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await io(t);
  }

  for (final side in ['YOU', 'OPPONENT']) {
    for (final score in [101, 140]) {
      testWidgets(
        '$side decrease removes one point from $score without an invented upper limit',
        (t) async {
          await open(t, me: score, them: score);
          await tap(t, '$side down');
          expect(
            LiveDraft.current!.data[side == 'YOU' ? 'me' : 'them'],
            score - 1,
          );
          expect(LiveDraft.current!.data[side == 'YOU' ? 'them' : 'me'], score);
          await close(t);
        },
      );
    }
    testWidgets('$side zero stays zero and both point controls persist', (
      t,
    ) async {
      await open(t);
      final key = side == 'YOU' ? 'me' : 'them';
      await tap(t, '$side down');
      expect(LiveDraft.current!.data[key], 0);
      await tap(t, '$side point');
      await tap(t, '$side up');
      expect(LiveDraft.current!.data[key], 2);
      await close(t);
      LiveDraft.debugForget();
      expect(LiveDraft.current!.data[key], 2);
    });
  }
  testWidgets(
    'End set appends its score, resets the live points and restores after reopening',
    (t) async {
      await open(t, me: 6, them: 4, sets: [4, 6]);
      await t.tap(find.text('End set'));
      await io(t);
      expect(LiveDraft.current!.data['score'], [4, 6, 6, 4]);
      expect(LiveDraft.current!.data['me'], 0);
      expect(LiveDraft.current!.data['them'], 0);
      await close(t);
      LiveDraft.debugForget();
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: LiveMatch(activity),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('4 — 6'), findsOneWidget);
      expect(find.text('6 — 4'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets('Keep going cancels Finish without clearing the typed score', (
    t,
  ) async {
    await open(t, me: 8, them: 6);
    await tap(t, 'Finish session');
    expect(find.text('Finish this workout?'), findsOneWidget);
    await t.tap(find.text('Keep going'));
    await t.pumpAndSettle();
    expect(find.byType(ActivitySummary), findsNothing);
    expect(find.text('Finish this workout?'), findsNothing);
    expect(LiveDraft.current!.data['me'], 8);
    expect(LiveDraft.current!.data['them'], 6);
    await close(t);
  });
  testWidgets(
    'finishing carries closed sets and the current partial set into the summary',
    (t) async {
      await open(t, me: 3, them: 2, sets: [6, 4]);
      final expected = t.widget<LiveShell>(find.byType(LiveShell)).result(600);
      expect(expected.gameScore, [(6, 4), (3, 2)]);
      await tap(t, 'Finish session');
      await t.tap(find.text('Finish'));
      for (
        var i = 0;
        i < 30 && find.byType(ActivitySummary).evaluate().isEmpty;
        i++
      ) {
        await io(t);
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(ActivitySummary), findsOneWidget);
      expect(
        t
            .widget<ActivitySummary>(find.byType(ActivitySummary))
            .result
            .gameScore,
        [(6, 4), (3, 2)],
      );
      expect(LiveDraft.current, isNull);
      await close(t);
    },
  );
}
