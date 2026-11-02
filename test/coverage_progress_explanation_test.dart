// Goal evidence and explanation controls, separate from the historical range.
// Every value is synthetic; the dates are relative to the app's local today.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/goal_plan.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

String ago(int n) {
  final now = DateTime.parse(todayLabel());
  return dayLabelOf(DateTime(now.year, now.month, now.day - n));
}

ProgressData data(
  GoalPhase phase, {
  bool enough = false,
  List<String> errors = const [],
}) => ProgressData(
  weights: [
    if (enough)
      for (var i = 60; i >= 0; i--)
        (
          date: ago(i),
          kg: 80.0,
          atTs: localDayStartSec(ago(i))!,
          unit: 'kg',
          entered: 80.0,
          source: 'synthetic',
          originId: null,
          historyOnly: false,
        ),
  ],
  measures: [],
  photos: [],
  lifts: [],
  food: [
    if (enough)
      for (var i = 60; i >= 0; i--)
        (
          date: ago(i),
          kcal: 2200.0,
          counts: true,
          protein: 160.0,
          proteinComplete: true,
        ),
  ],
  steps: [],
  sleepMin: [],
  recovery: [],
  sessions: [],
  baseline: ago(70),
  heightCm: 180,
  goal: GoalPlan(
    phase: phase,
    since: ago(70),
    holdKg: phase == GoalPhase.maintain ? 80 : null,
  ),
  goalChosen: true,
  user: const {
    'kcal_target': 2200,
    'sex': 'm',
    'age': 30,
    'height_cm': 180,
    'weight_kg': 80,
  },
  readErrors: errors,
);

Finder action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
Future<void> choose(WidgetTester t, Finder target) async {
  // Controls may be above the last fully read viewport.
  t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(
    target,
    250,
    maxScrolls: 80,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<Set<String>> readAll(WidgetTester t) async {
  final seen = <String>{};
  final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
  pos.jumpTo(0);
  await t.pumpAndSettle();
  for (var n = 0; n < 80; n++) {
    seen.addAll(t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''));
    expect(t.takeException(), isNull);
    if (pos.extentAfter < .5) return seen;
    pos.jumpTo((pos.pixels + 400).clamp(0, pos.maxScrollExtent));
    await t.pumpAndSettle();
  }
  fail('Full Progress scroll was not reached');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAuditFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    DayClock.install([], []);
  });
  Future<void> open(WidgetTester t, ProgressData d, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(body: ProgressScreen(data: d)),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final phase in GoalPhase.values) {
    testWidgets(
      '${phase.name} explains missing evidence and can collapse without changing targets',
      (t) async {
        final d = data(phase);
        await open(t, d);
        await choose(t, action('Show how the check works'));
        final text = await readAll(t);
        expect(text, containsAll(['WHAT IT WAITS FOR', 'HOW IT JUDGES']));
        expect(text.any((s) => s.contains('Monday-to-Sunday')), isTrue);
        expect(
          text.any((s) => s.contains('protein') && s.contains('g/kg')),
          isTrue,
        );
        expect(
          text.any((s) => s.contains('never changed automatically')),
          isTrue,
        );
        await choose(t, action('Hide how the check works'));
        expect(find.text('HOW IT JUDGES'), findsNothing);
        expect(d.user['kcal_target'], 2200);
        expect(d.goal.phase, phase);
      },
    );
  }
  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets(
      'a qualified review explains its closed-week comparison at ${scale}x',
      (t) async {
        await open(t, data(GoalPhase.fatLoss, enough: true), scale: scale);
        await choose(t, action('Show how the check works'));
        final text = await readAll(t);
        expect(text, contains('HOW IT JUDGES'));
        expect(text, isNot(contains('WHAT IT WAITS FOR')));
        expect(
          text.any(
            (s) => s.startsWith('It compares') && s.contains('last 7 days'),
          ),
          isTrue,
        );
        expect(text.any((s) => s.contains('Review unavailable')), isFalse);
      },
    );
  }
  testWidgets(
    'a failed evidence family withholds the verdict and explains why',
    (t) async {
      await open(t, data(GoalPhase.fatLoss, enough: true, errors: ['Weight']));
      await choose(t, action('Show how the check works'));
      final text = await readAll(t);
      expect(text, contains('Unavailable'));
      expect(text, contains('Review unavailable until the records refresh.'));
      expect(text, isNot(contains('Adjust')));
    },
  );
  testWidgets(
    'a failed context family does not invalidate the independent goal verdict',
    (t) async {
      await open(t, data(GoalPhase.fatLoss, enough: true, errors: ['Sleep']));
      await choose(t, action('Show how the check works'));
      final text = await readAll(t);
      expect(text, isNot(contains('Unavailable')));
      expect(
        text,
        isNot(contains('Review unavailable until the records refresh.')),
      );
      expect(text, contains('Adjust'));
    },
  );
  testWidgets(
    'Change goal opens the actual picker and Back preserves the existing review',
    (t) async {
      await open(t, data(GoalPhase.maintain, enough: true));
      await choose(t, action('Show how the check works'));
      await choose(t, action('Change goal'));
      expect(find.byType(GoalScreen), findsOneWidget);
      Navigator.of(t.element(find.byType(GoalScreen))).pop();
      await t.pumpAndSettle();
      expect(find.byType(ProgressScreen), findsOneWidget);
      expect(
        (await readAll(t)).any((s) => s.startsWith('Keep it off')),
        isTrue,
      );
    },
  );
}
