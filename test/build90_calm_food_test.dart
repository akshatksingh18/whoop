import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/ui2/grammar.dart';
import 'package:openstrap_edge/ui2/screens/food_diary.dart';
import 'package:openstrap_edge/ui2/screens/nutrition_screen.dart';
import 'package:openstrap_edge/ui2/theme.dart';

const _entries = [
  FoodEntry(
    id: 'a',
    date: '2025-01-05',
    meal: 'breakfast',
    label: 'Synthetic oats',
    kcal: 400,
    proteinG: 20,
    carbsG: 60,
    fatG: 10,
  ),
  FoodEntry(
    id: 'b',
    date: '2025-01-05',
    meal: 'breakfast',
    label: 'Synthetic soup',
    kcal: 300,
  ),
];

void main() {
  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets(
      'compact Food keeps all totals honest and Add reachable at ${scale}x',
      (t) async {
        t.view.physicalSize = const Size(1170, 2532);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        var added = 0, opened = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CalorieCard(
                    eaten: 700,
                    goal: 2300,
                    maintenance: 2400,
                    day: rollupDay('2025-01-05', _entries, today: '2025-01-06'),
                    profile: const {
                      'protein_target': 160,
                      'carbs_target': 240,
                      'fat_target': 70,
                      'fibre_target': 30,
                    },
                    onAdd: () => added++,
                    onTap: () => opened++,
                  ),
                ),
              ),
            ),
          ),
        );
        for (final label in ['Protein', 'Carbs', 'Fat', 'Fibre']) {
          expect(find.text(label), findsOneWidget);
          final value = t.widget<Text>(
            find.byKey(ValueKey('food-macro-$label')),
          );
          expect(value.softWrap, isFalse);
        }
        expect(find.text('≥20 / 160 g'), findsOneWidget);
        expect(find.text('— / 30 g'), findsOneWidget);
        expect(find.textContaining('— not logged'), findsOneWidget);
        expect(find.textContaining('≥ partial total'), findsOneWidget);
        expect(find.textContaining('estimated maintenance'), findsNothing);
        expect(
          find.byType(GoalBar),
          findsNWidgets(4),
        ); // calories + 3 known macros
        await t.ensureVisible(find.text('Add food'));
        await t.tap(find.text('Add food'));
        expect(added, 1);
        await t.ensureVisible(find.byKey(const ValueKey('food-eaten')));
        await t.tap(find.byKey(const ValueKey('food-eaten')));
        expect(opened, 1);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'meal overview stays readable with its edit and menu routes at ${scale}x',
      (t) async {
        t.view.physicalSize = const Size(1170, 2532);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: MealCard(
                    date: '2025-01-05',
                    meal: 'breakfast',
                    entries: _entries,
                    onChanged: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Breakfast'), findsOneWidget);
        expect(find.text('20 g protein'), findsOneWidget);
        expect(find.text('Protein not logged'), findsOneWidget);
        expect(find.text('700 kcal'), findsOneWidget);
        expect(find.byTooltip('Breakfast options'), findsOneWidget);
        expect(find.byTooltip('Log Breakfast'), findsOneWidget);
        // The overview is shorter, while mealTotals still includes every nutrient
        // for the full meal and group views that retain the detailed breakdown.
        expect(mealTotals(_entries), contains('C ≥60'));
        expect(mealTotals(_entries), contains('Fb –'));
        expect(t.takeException(), isNull);
      },
    );
  }
}
