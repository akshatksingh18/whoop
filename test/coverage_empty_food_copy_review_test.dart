import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart' show BigButton, Pressable;

import 'coverage_nutrition_root_test.dart' show ago, io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('empty-food-copy-review', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final sourceHasFood in [false, true]) {
    testWidgets(
      'copy review does not write with an empty selection: source populated $sourceHasFood',
      (tester) async {
        final source = ago(2), target = ago(1);
        final db = await LocalDb.instance;
        await NutritionDb.put(
          db,
          FoodEntry(
            id: 'authored-target',
            date: target,
            meal: 'lunch',
            label: 'Authored target meal',
            kcal: 300,
            atTs: localDayStartSec(target)! + 12 * 3600,
          ),
        );
        if (sourceHasFood) {
          await NutritionDb.put(
            db,
            FoodEntry(
              id: 'authored-source',
              date: source,
              meal: 'snacks',
              label: 'Authored source meal',
              atTs: localDayStartSec(source)! + 12 * 3600,
            ),
          );
        }
        final existing = await db.query('food_entry', orderBy: 'id');
        var changed = 0;
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        await localizedPage(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: NutritionDayView(date: target, onChanged: () => changed++),
            ),
          ),
          app: app,
          settle: false,
        );
        await io(tester);
        final copy = find.text('Copy a day');
        await reveal(tester, copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        tester
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .onDateChanged(DateTime.parse(source));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK').last);
        await io(tester);

        if (sourceHasFood) {
          final choice = find.byWidgetPredicate(
            (widget) =>
                widget is Pressable &&
                widget.semanticLabel == 'Authored source meal, selected',
          );
          await reveal(tester, choice);
          await tester.tap(choice);
          await io(tester);
        } else {
          expect(find.text('Nothing to copy'), findsOneWidget);
          expect(find.text('No food is logged on that day.'), findsOneWidget);
        }
        expect(find.text('Nothing selected'), findsOneWidget);
        final button = find.byType(BigButton).last;
        expect(tester.widget<BigButton>(button).onTap, isNull);
        await reveal(tester, button);
        await tester.tap(button, warnIfMissed: false);
        await io(tester);
        expect(find.text('Nothing selected'), findsOneWidget);
        Navigator.of(tester.element(button)).pop();
        await io(tester);
        expect(
          tester.widget<NutritionDayView>(find.byType(NutritionDayView)).date,
          target,
        );
        expect(await db.query('food_entry', orderBy: 'id'), existing);
        expect(changed, 0);
      },
    );
  }
}
