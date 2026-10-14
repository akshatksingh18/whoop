// Build 89: the AI-analysis file explains its columns, never prints a missing
// value as zero, adds weekly averages over counted days and lists food items
// only when asked to.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/analysis_export.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';

void main() {
  AnalysisDay day(String d, {double? kg, double? kcal, bool? counted}) =>
      AnalysisDay(d)
        ..weightKg = kg
        ..kcal = kcal
        ..protein = kcal == null ? null : 150
        ..counted = counted
        ..steps = 9000;

  String build({Map<String, List<FoodEntry>> foods = const {}}) =>
      buildAnalysisMarkdown(
        range: AnalysisRange.twoWeeks,
        from: '2026-10-01',
        today: '2026-10-13',
        profile: Profile.fromMap(const {'height_cm': 178}),
        targets: const {'kcal_target': 2200, 'protein_target': 160},
        goal: 'Recomposition',
        days: [
          day('2026-10-02', kg: 80.2, kcal: 2100, counted: true),
          day('2026-10-03', kcal: 900, counted: false),
          day('2026-10-06', kg: 80.0, kcal: 2300, counted: true),
          AnalysisDay('2026-10-07'),
        ],
        lifts: const [],
        measures: const [],
        foods: foods,
      );

  test('header, columns and honest gaps', () {
    final md = build();
    expect(md, contains('"—" means not measured'));
    expect(md, contains('Goal: Recomposition'));
    expect(md, contains('calories 2200 kcal'));
    expect(md, contains('| 2026-10-03 | — |'));
    // A day with nothing recorded is left out, not printed as zeros.
    expect(md, isNot(contains('2026-10-07 |')));
  });

  test('weekly averages use counted days only', () {
    final md = build();
    // Week of 2026-09-28 holds the 2nd (counted 2100) and 3rd (not counted).
    expect(md, contains('| 2026-09-28 | 80.2 | 2100 | 150 | 1 |'));
  });

  test('food items only when given', () {
    expect(build(), isNot(contains('## Food log')));
    final md = build(foods: {
      '2026-10-02': [
        const FoodEntry(
          id: 'a',
          date: '2026-10-02',
          meal: 'lunch',
          label: 'Rice',
          kcal: 300,
          atTs: 0,
          confirmed: true,
        ),
      ],
    });
    expect(md, contains('- lunch: Rice — 300 kcal'));
  });

  test('food items stop after three months', () {
    expect(AnalysisRange.threeMonths.listsFoods, isTrue);
    expect(AnalysisRange.sixMonths.listsFoods, isFalse);
    expect(AnalysisRange.lifetime.listsFoods, isFalse);
  });
}
