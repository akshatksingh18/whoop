// Real goal-picker choices, persistence, cancellation and storage refusal.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/goal_plan.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

Future<void> until(WidgetTester t, bool Function() ready) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
  expect(t.takeException(), isNull);
}

Finder pressable(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  bool? result;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/goals',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    result = null;
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, {double? kg = 80, double scale = 1}) async {
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
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(c).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => GoalScreen(
                      plan: const GoalPlan(phase: GoalPhase.recomp),
                      kg: kg,
                    ),
                  ),
                );
              },
              child: const Text('Open goal'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open goal'));
    await t.pumpAndSettle();
  }

  Future<void> choose(WidgetTester t, String label) async {
    await t.scrollUntilVisible(
      find.text(label),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 60,
    );
    await t.pumpAndSettle();
    await t.tap(find.text(label));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  }

  for (final pace in GoalPace.values) {
    testWidgets('Lose fat saves the chosen ${pace.name} pace and start date', (
      t,
    ) async {
      await open(t);
      await choose(t, 'Lose fat');
      await choose(t, pace.title);
      expect(pressable('${pace.title}, selected'), findsOneWidget);
      await choose(t, 'Use this goal from today');
      await until(t, () => result != null);
      final saved = (await t.runAsync(() => GoalPlan.read(strict: true)))!;
      expect(result, isTrue);
      expect(saved.phase, GoalPhase.fatLoss);
      expect(saved.pace, pace);
      expect(saved.since, todayLabel());
      expect(saved.holdKg, isNull);
      await close(t);
    });
  }
  for (final age in TrainingAge.values) {
    testWidgets('Build muscle saves the chosen ${age.name} training age', (
      t,
    ) async {
      await open(t);
      await choose(t, 'Build muscle');
      await choose(t, age.title);
      await choose(t, 'Use this goal from today');
      await until(t, () => result != null);
      final saved = (await t.runAsync(() => GoalPlan.read(strict: true)))!;
      expect(saved.phase, GoalPhase.leanGain);
      expect(saved.trainingAge, age);
      expect(saved.holdKg, isNull);
      await close(t);
    });
  }
  for (final kg in <double?>[80, null]) {
    testWidgets(
      'Keep it off retains ${kg == null ? 'an absent' : 'the measured'} holding weight',
      (t) async {
        await open(t, kg: kg);
        await choose(t, 'Keep it off');
        await choose(t, 'Use this goal from today');
        await until(t, () => result != null);
        final saved = (await t.runAsync(() => GoalPlan.read(strict: true)))!;
        expect(saved.phase, GoalPhase.maintain);
        expect(saved.holdKg, kg);
        await close(t);
      },
    );
  }
  testWidgets(
    'the explicit from-today action can save the current recomposition goal',
    (t) async {
      await open(t);
      await choose(t, 'Use this goal from today');
      await until(t, () => result != null);
      final saved = (await t.runAsync(() => GoalPlan.read(strict: true)))!;
      expect(saved.phase, GoalPhase.recomp);
      expect(saved.since, todayLabel());
      expect(saved.holdKg, isNull);
      await close(t);
    },
  );
  testWidgets('strength goal saves without carrying a maintenance anchor', (
    t,
  ) async {
    await open(t);
    await choose(t, 'Get stronger at this weight');
    await choose(t, 'Use this goal from today');
    await until(t, () => result != null);
    final saved = (await t.runAsync(() => GoalPlan.read(strict: true)))!;
    expect(saved.phase, GoalPhase.strength);
    expect(saved.holdKg, isNull);
    await close(t);
  });
  testWidgets(
    'Back retains choices when kept and discards without changing the stored goal',
    (t) async {
      const original = GoalPlan(phase: GoalPhase.recomp, since: '2026-01-02');
      await t.runAsync(() => GoalPlan.save(original));
      await open(t);
      await choose(t, 'Lose fat');
      await t.tap(pressable('Back'));
      await t.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(pressable('Lose fat, selected'), findsOneWidget);
      await t.tap(pressable('Back'));
      await t.pumpAndSettle();
      await t.tap(find.text('Discard'));
      await t.pumpAndSettle();
      expect(find.text('Open goal'), findsOneWidget);
      final saved = (await t.runAsync(() => GoalPlan.read(strict: true)))!;
      expect(saved.phase, original.phase);
      expect(saved.since, original.since);
      await close(t);
    },
  );
  testWidgets(
    'a refused goal write retains choices and the previous goal for a successful retry',
    (t) async {
      await t.runAsync(
        () => GoalPlan.save(
          const GoalPlan(phase: GoalPhase.recomp, since: '2026-01-02'),
        ),
      );
      await open(t);
      await choose(t, 'Lose fat');
      await choose(t, 'Gentle');
      await t.runAsync(
        () => db.execute(
          "CREATE TEMP TRIGGER reject_goal BEFORE INSERT ON baselines BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
        ),
      );
      try {
        await choose(t, 'Use this goal from today');
        await until(t, () => find.text('Try again').evaluate().isNotEmpty);
        expect(result, isNull);
        expect(pressable('Gentle, selected'), findsOneWidget);
        expect(
          (await t.runAsync(() => GoalPlan.read(strict: true)))!.phase,
          GoalPhase.recomp,
        );
      } finally {
        await t.runAsync(() => db.execute('DROP TRIGGER reject_goal'));
      }
      await choose(t, 'Try again');
      await until(t, () => result != null);
      expect(
        (await t.runAsync(() => GoalPlan.read(strict: true)))!.pace,
        GoalPace.gentle,
      );
      await close(t);
    },
  );
  for (final scale in [2.0, 3.1]) {
    testWidgets('the entire goal picker remains reachable at ${scale}x', (
      t,
    ) async {
      await open(t, scale: scale);
      await choose(t, 'Build muscle');
      await choose(t, 'More than three years');
      await choose(t, 'Use this goal from today');
      await until(t, () => result != null);
      expect(
        (await t.runAsync(() => GoalPlan.read(strict: true)))!.trainingAge,
        TrainingAge.advanced,
      );
      await close(t);
    });
  }
}
