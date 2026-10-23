// Synthetic independent audit of nested target editing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/nutrition_screen.dart';
import 'package:openstrap_edge/ui2/screens/food_diary.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/picker.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ProfileFailure extends AppState {
  _ProfileFailure() : super.forTesting();
  int calls = 0;
  @override
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> fields,
  ) async {
    calls++;
    if (calls == 1) throw StateError('synthetic profile failure');
    user = {...?user, ...fields};
    return user!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'audit_build95_nested_targets_synthetic.db';
    await databaseFactory.deleteDatabase(
      p.join(await getDatabasesPath(), LocalDb.dbName),
    );
    await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    LiveDraft.clear();
    await LiveDraft.retrySave();
    app = AppState.forTesting()
      ..user = {
        'kcal_target': 2300.5,
        'protein_target': 150.5,
        'carbs_target': 260.5,
        'fat_target': 75.5,
        'fibre_target': 30.5,
      };
  });
  tearDown(() {
    app.dispose();
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await getDatabasesPath(), LocalDb.dbName),
    );
  });
  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 1050);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => editNutritionGoals(c),
                child: const Text('Open targets'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open targets'));
    await t.pumpAndSettle();
  }

  Future<void> finishDraft(WidgetTester t) async {
    LiveDraft.clear();
    var saved = false;
    final write = LiveDraft.retrySave().then((_) => saved = true);
    for (var i = 0; i < 100 && !saved; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump();
    }
    expect(saved, isTrue, reason: 'Finish draft writes inside their widget clock');
    await write;
  }

  testWidgets('regression: unchanged decimal targets retain their precision', (
    t,
  ) async {
    await open(t);
    final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.first.controller!.text, '2300.5');
    final save = find.widgetWithText(BigButton, 'Save');
    await t.ensureVisible(save);
    final dynamic callback = t.widget<BigButton>(save).onTap!;
    await t.runAsync(() async {
      await callback();
    });
    await t.pumpAndSettle();
    expect(app.user!['kcal_target'], 2300.5);
    expect(app.user!['protein_target'], 150.5);
  });
  testWidgets(
    'positive: dirty target survives tested edge drag and close offers discard',
    (t) async {
      await open(t);
      await t.enterText(find.byType(TextField).first, '2450');
      t.testTextInput.hide();
      await t.pumpAndSettle();
      final rect = t.getRect(find.byType(BottomSheet));
      await t.flingFrom(
        Offset(rect.left + 3, rect.top + 35),
        const Offset(0, 850),
        1800,
      );
      await t.pumpAndSettle();
      expect(find.text('Daily targets'), findsOneWidget);
      if (find.text('Discard changes?').evaluate().isEmpty) {
        await t.tap(
          find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Close',
          ),
        );
        await t.pumpAndSettle();
      }
      expect(find.text('Discard changes?'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller!.text,
        '2450',
      );
      expect(app.user!['kcal_target'], 2300.5);
    },
  );

  testWidgets(
    'regression: deleted-food edit retains recorded portion and conversion',
    (t) async {
      const entry = FoodEntry(
        id: 'deleted-food-synthetic',
        date: '2026-09-10',
        meal: 'breakfast',
        label: 'Synthetic links',
        foodKey: 'deleted-synthetic-key',
        quantity: 2,
        unit: 'link',
        conv: '{"u":"link","m":""}',
        kcal: 200,
        proteinG: 20,
        confirmed: true,
        atTs: 1789027200,
      );
      await t.runAsync(
        () async => NutritionDb.put(await LocalDb.instance, entry),
      );
      t.view.physicalSize = const Size(650, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Builder(
              builder: (c) => Scaffold(
                body: TextButton(
                  onPressed: () => editDiaryEntry(c, entry),
                  child: const Text('Edit synthetic entry'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Edit synthetic entry'));
      for (
        var i = 0;
        i < 40 && find.byType(QuickAddSheet).evaluate().isEmpty;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await t.pump();
      }
      expect(find.byType(QuickAddSheet), findsOneWidget);
      final save = find.widgetWithText(BigButton, 'Save changes');
      await t.ensureVisible(save);
      final dynamic callback = t.widget<BigButton>(save).onTap!;
      await t.runAsync(() async {
        await callback();
      });
      await t.pumpAndSettle();
      final stored = (await t.runAsync(
        () async =>
            NutritionDb.entriesForDay(await LocalDb.instance, entry.date),
      ))!.single;
      expect(stored.quantity, 2);
      expect(stored.conv, entry.conv);
      expect(stored.unit, 'link');
      expect(stored.kcal, 200);
    },
  );

  testWidgets(
    'regression: Body retry finishes profile update without duplicating its reading',
    (t) async {
      app.dispose();
      final failure = _ProfileFailure()..user = {'weight_kg': 70.0};
      app = failure;
      await t.runAsync(() async {
        await (await LocalDb.instance).insert('body_photo', {
          'id': 'synthetic-load-sentinel',
          'date': todayLabel(),
          'pose': 'front',
          'recorded_at': 1,
          'source': 'whoop',
          'created_at': 1,
        });
      });
      t.view.physicalSize = const Size(650, 1300);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Builder(
              builder: (c) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(c).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          BodyEntryScreen(unit: 'kg', date: todayLabel()),
                    ),
                  ),
                  child: const Text('Open body'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open body'));
      await t.pumpAndSettle();
      for (
        var i = 0;
        i < 150 && find.textContaining('1 for this day').evaluate().isEmpty;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await t.pump();
      }
      expect(find.textContaining('1 for this day'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, '80');
      Future<void> save() async {
        final finder = find.widgetWithText(BigButton, 'Save').first;
        await t.ensureVisible(finder);
        final dynamic cb = t.widget<BigButton>(finder).onTap!;
        await t.runAsync(() async {
          await cb().timeout(const Duration(seconds: 8));
        });
        await t.pumpAndSettle();
      }

      await save();
      expect(failure.calls, 1);
      expect(find.byType(BodyEntryScreen), findsOneWidget);
      expect(
        (await t.runAsync(() => BodyLogDb.readingsOn(todayLabel())))!,
        hasLength(1),
      );
      await save();
      expect(find.byType(BodyEntryScreen), findsNothing);
      expect(failure.calls, 2);
      expect(app.user!['weight_kg'], 80);
    },
  );

  testWidgets('regression: picker quotes the same active energy as setup', (
    t,
  ) async {
    final a = activityByName('Weight training')!;
    final kcal = sessionActiveKcal(
      type: a.typeKey,
      p: const Profile(weightKg: 70),
      minutes: 30,
    )!.round();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: ActivityRow(a, weightKg: 70)),
      ),
    );
    expect(find.text('$kcal kcal / 30 min'), findsOneWidget);
  });

  testWidgets(
    'regression: non-swim and non-yoga activities do not invent those measurements',
    (t) async {
      expect(liveFor(activityByName('Rowing')!), isA<LiveSwim>());
      final a = activityByName('Sauna')!;
      expect(liveFor(a), isA<LiveMeasured>());
      LiveDraft.begin(a);
      await t.pumpWidget(
        MaterialApp(theme: buildTheme(Brightness.light), home: liveFor(a)),
      );
      final result = t.widget<LiveShell>(find.byType(LiveShell)).result(60);
      expect(result.poses, isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
      await finishDraft(t);
    },
  );

  testWidgets(
    'regression: interval clock and completed rounds survive navigation',
    (t) async {
      final a = allActivities.firstWhere((x) => x.track == Track.interval);
      LiveDraft.begin(
        a,
        startedAt: DateTime.now().subtract(const Duration(seconds: 80)),
      );
      Widget page() =>
          MaterialApp(theme: buildTheme(Brightness.light), home: liveFor(a));
      await t.pumpWidget(page());
      await t.pump(const Duration(seconds: 1));
      final before = t.widget<LiveShell>(find.byType(LiveShell)).result(80);
      expect(before.rounds, hasLength(1));
      await t.pumpWidget(const SizedBox.shrink());
      expect(LiveDraft.current, isNotNull);
      await t.pumpWidget(page());
      final after = t.widget<LiveShell>(find.byType(LiveShell)).result(80);
      expect(after.rounds, hasLength(1));
      expect(find.text('ROUND 2'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await finishDraft(t);
    },
  );

  testWidgets(
    'regression: Body history refreshes after immediate deletion then Back',
    (t) async {
      const date = '2026-09-10';
      await t.runAsync(() => BodyLogDb.putWeight(date, 80, 'kg'));
      final weights = (await t.runAsync(() => BodyLogDb.weights()))!;
      final data = ProgressData(
        weights: weights,
        measures: [],
        photos: [],
        lifts: [],
        food: [],
        steps: [],
        sleepMin: [],
        recovery: [],
        sessions: [],
        baseline: null,
        heightCm: null,
      );
      t.view.physicalSize = const Size(650, 1500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: BodyHistoryScreen(data: data),
          ),
        ),
      );
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is Pressable && (w.semanticLabel ?? '').startsWith('Edit '),
        ),
      );
      await t.pumpAndSettle();
      for (
        var i = 0;
        i < 150 &&
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Pressable &&
                      (w.semanticLabel ?? '').endsWith('. Delete'),
                )
                .evaluate()
                .isEmpty;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await t.pump();
      }
      final del = find.byWidgetPredicate(
        (w) => w is Pressable && (w.semanticLabel ?? '').endsWith('. Delete'),
      );
      await t.ensureVisible(del);
      await t.tap(del);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete').last);
      for (var i = 0; i < 100; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
        if (del.evaluate().isEmpty) break;
      }
      expect((await t.runAsync(() => BodyLogDb.readingsOn(date)))!, isEmpty);
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Back',
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(BodyHistoryScreen), findsOneWidget);
      for (var i = 0; i < 50 && find.text('80 kg').evaluate().isNotEmpty; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
      }
      expect(find.text('80 kg'), findsNothing);
    },
  );
}
