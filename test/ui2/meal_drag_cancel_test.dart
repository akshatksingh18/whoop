// Actual pointer cancellation must stop page-edge scrolling and keep saved food.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/grammar.dart' show DragEdgeScroll;
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'screens/food_calendar_recovery_test.dart' show flush;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('meal-drag-cancel');
  });
  setUp(() async {
    await resetCoverageStore();
    final db = await LocalDb.instance;
    final ids = <String>[];
    for (var i = 0; i < 16; i++) {
      final id = 'authored-drag-${i.toString().padLeft(2, '0')}';
      ids.add(id);
      await NutritionDb.put(
        db,
        FoodEntry(
          id: id,
          date: '2021-04-06',
          meal: 'lunch',
          label: 'Authored food $i',
          kcal: i == 15 ? null : 10,
          proteinG: 0,
          atTs: 1617714000 + i,
          loggedAt: 1617804000 + i,
          group: i < 8 ? 'Authored A' : 'Authored B',
        ),
      );
    }
    await NutritionDb.arrangeEntries(db, const [], ids);
  });
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    for (final index in [0, 4]) {
      testWidgets(
        'cancel a real meal drag from row $index at ${scale}x stops edge scrolling without saving a reorder',
        (t) async {
          await localizedPage(
            t,
            const MealPage(date: '2021-04-06', meal: 'lunch'),
            scale: scale,
          );
          t.view.physicalSize = const Size(430, 932);
          await flush(t);
          final row = find.byKey(
            ValueKey('authored-drag-${index.toString().padLeft(2, '0')}'),
          );
          await reveal(t, row);
          final page = t
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          final db = await LocalDb.instance;
          final before = await db.query('food_entry', orderBy: 'id');
          final position = page.pixels;
          final gesture = await t.startGesture(t.getCenter(row));
          var cancelled = false;
          try {
            await t.pump(const Duration(milliseconds: 650));
            expect(
              t.widget<DragEdgeScroll>(find.byType(DragEdgeScroll)).dragging,
              true,
            );
            await gesture.moveTo(const Offset(215, 910));
            for (var frame = 0; frame < 8; frame++) {
              await t.pump(const Duration(milliseconds: 25));
            }
            expect(page.pixels, greaterThan(position));
            await gesture.cancel();
            cancelled = true;
            await t.pumpAndSettle();
            final stopped = page.pixels;
            await t.pump(const Duration(seconds: 1));
            await t.pumpAndSettle();
            expect(page.pixels, closeTo(stopped, .01));
            expect(await db.query('food_entry', orderBy: 'id'), before);
            expect(
              t.widget<MealPage>(find.byType(MealPage)).date,
              '2021-04-06',
            );
            expect(find.byType(AlertDialog), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            if (!cancelled) await gesture.cancel();
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}
