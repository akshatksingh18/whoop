import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/ui2/screens/food_day_copy.dart';
import 'package:openstrap_edge/ui2/screens/nutrition_screen.dart';
import 'package:openstrap_edge/ui2/screens/food_calendar.dart';
import 'package:openstrap_edge/ui2/grammar.dart' show Pressable;
import 'package:openstrap_edge/ui2/theme.dart';

const entries = [
  FoodEntry(
    id: 'a',
    date: '2025-01-05',
    meal: 'breakfast',
    label: 'Synthetic oats',
    quantity: 100,
    unit: 'g',
    kcal: 400,
    proteinG: 20,
    carbsG: 60,
    fatG: 10,
  ),
  FoodEntry(
    id: 'b',
    date: '2025-01-05',
    meal: 'dinner',
    label: 'Synthetic soup',
    kcal: 300,
  ),
];

void main() {
  test(
    'reviewed day copies atomically into the destination with new logging provenance',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      try {
        await createNutritionTables(db);
        final src = FoodEntry(
          id: 'source',
          date: '2025-01-05',
          meal: 'breakfast',
          label: 'Synthetic oats',
          quantity: 100,
          unit: 'g',
          kcal: 400,
          proteinG: 20,
          atTs: DateTime(2025, 1, 5, 8).millisecondsSinceEpoch ~/ 1000,
          group: 'Oats',
          loggedAt: 100,
        );
        expect(
          await NutritionDb.logDayCopy(
            db,
            date: '2025-01-06',
            reviewed: [src.scaledPortion(.5)],
          ),
          1,
        );
        final copied = (await NutritionDb.entriesForDay(
          db,
          '2025-01-06',
        )).single;
        expect(copied.id, isNot(src.id));
        expect(copied.quantity, 50);
        expect(copied.kcal, 200);
        expect(copied.fibreG, isNull);
        expect(copied.group, 'Oats');
        expect(copied.meal, 'breakfast');
        expect(
          copied.atTs,
          DateTime(2025, 1, 6, 8).millisecondsSinceEpoch ~/ 1000,
        );
        expect(copied.loggedAt, isNot(100));
        await db.execute(
          "CREATE TRIGGER fail_copy BEFORE INSERT ON food_entry WHEN NEW.label='fail' BEGIN SELECT RAISE(ABORT,'synthetic'); END",
        );
        await expectLater(
          NutritionDb.logDayCopy(
            db,
            date: '2025-01-07',
            reviewed: [
              src,
              const FoodEntry(
                id: 'fail',
                date: '2025-01-05',
                meal: 'dinner',
                label: 'fail',
              ),
            ],
          ),
          throwsA(anything),
        );
        expect(await NutritionDb.entriesForDay(db, '2025-01-07'), isEmpty);
      } finally {
        await db.close();
      }
    },
  );
  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets('all macros and week labels remain visible at ${scale}x', (
      t,
    ) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      FoodWeekStrip(
                        date: '2025-01-06',
                        onDay: (_) {},
                        marks: const {},
                      ),
                      CalorieCard(
                        eaten: 700,
                        goal: 2300,
                        day: rollupDay(
                          '2025-01-05',
                          entries,
                          today: '2025-01-06',
                        ),
                        profile: const {
                          'protein_target': 160,
                          'carbs_target': 240,
                          'fat_target': 70,
                          'fibre_target': 30,
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (final label in [
        'Protein',
        'Carbs',
        'Fat',
        'Fibre',
        'Counted',
        'Logged',
        'Empty',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets(
      'copy review adjusts and unticks without writing until explicit Log at ${scale}x',
      (t) async {
        t.view.physicalSize = const Size(1170, 9000);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        List<FoodEntry>? saved;
        await t.pumpWidget(
          MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            theme: buildTheme(Brightness.light),
            home: Builder(
              builder: (c) => Scaffold(
                body: TextButton(
                  onPressed: () => reviewFoodDayCopy(
                    c,
                    from: '2025-01-05',
                    to: '2025-01-06',
                    entries: entries,
                    onLog: (xs) async {
                      saved = xs;
                    },
                  ),
                  child: const Text('Open review'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open review'));
        await t.pumpAndSettle();
        expect(saved, isNull);
        final list = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        final soup = find.text('Synthetic soup');
        await t.scrollUntilVisible(
          soup,
          300,
          scrollable: list,
        );
        await t.tap(soup);
        await t.pump();
        final oats = find.byWidgetPredicate(
          (w) =>
              w is Pressable &&
              w.semanticLabel == 'Portion of Synthetic oats, 1×',
        );
        await t.scrollUntilVisible(
          oats,
          -300,
          scrollable: list,
        );
        await t.tap(oats);
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), '0.5');
        await t.ensureVisible(find.text('Save'));
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(saved, isNull);
        final copy = find.textContaining('Copy 1 item');
        await t.scrollUntilVisible(
          copy,
          300,
          scrollable: list,
        );
        await t.tap(copy);
        await t.pumpAndSettle();
        expect(saved, hasLength(1));
        expect(saved!.single.kcal, 200);
        expect(saved!.single.fibreG, isNull);
        saved = null;
        await t.tap(find.text('Open review'));
        await t.pumpAndSettle();
        // Leaving without Copy writes nothing.
        Navigator.of(t.element(find.text('Copy a day'))).pop();
        await t.pumpAndSettle();
        expect(saved, isNull);
      },
    );
  }
}
