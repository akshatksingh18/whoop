// Component-level decisions on existing readings, with real synthetic SQLite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart'
    show WhoopTextField;
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_body_history_actions_test.dart' show App;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Finder input(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is WhoopTextField && w.label == label),
  matching: find.byType(TextField),
);

void main() {
  late App app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-entry-decisions');
  });
  setUp(() async {
    await resetCoverageStore();
    app = App()..user = {'weight_kg': 70.0};
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 70)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final historical in [false, true]) {
    for (final choice in ['Cancel', 'Add reading', 'Correct the first']) {
      testWidgets(
        'COV-47 existing weight $choice keeps first-reading authority $historical',
        (t) async {
          final day = historical ? '2021-04-06' : todayLabel();
          await BodyLogDb.putWeight(day, 70, 'kg', at: DateTime.parse(day));
          await localizedPage(
            t,
            BodyEntryScreen(unit: 'kg', date: day),
            app: app,
            push: true,
          );
          await t.enterText(input('Weight (kg)'), '71.25');
          final save = t.widget<BigButton>(find.byType(BigButton)).onTap!;
          Future<void>? pending;
          await t.runAsync(() async {
            pending = Future<void>.sync(save);
            await Future<void>.delayed(const Duration(milliseconds: 60));
          });
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await t.tap(find.text(choice).last);
          await t.runAsync(() => pending!);
          await flush(t);
          final readings = (await t.runAsync(() => BodyLogDb.readingsOn(day)))!;
          expect(readings, hasLength(choice == 'Add reading' ? 2 : 1));
          expect(
            (await t.runAsync(() => BodyLogDb.weightOn(day)))!.kg,
            choice == 'Correct the first' ? 71.25 : 70,
          );
          if (choice == 'Cancel') {
            expect(find.text('Nothing saved.'), findsOneWidget);
            expect(app.profileWrites, isEmpty);
            expect(
              t.widget<TextField>(input('Weight (kg)')).controller!.text,
              '71.25',
            );
          } else {
            expect(find.text('Closed test page'), findsOneWidget);
            expect(app.profileWrites, historical ? isEmpty : hasLength(1));
            if (!historical)
              expect(
                app.user!['weight_kg'],
                choice == 'Correct the first' ? 71.25 : 70,
              );
          }
        },
      );
    }
  }
  testWidgets(
    'COV-47 tape edit keeps newer unknown sites and its original provenance',
    (t) async {
      final measuredAt = DateTime(2021, 4, 6, 8);
      final measure = BodyMeasure(
        id: 'synthetic-tape',
        date: '2021-04-06',
        recordedAt: measuredAt,
        inches: {'waistNavel': 32, 'futureSite': 12.5},
      );
      await BodyLogDb.putMeasure(measure);
      await localizedPage(
        t,
        BodyEntryScreen(
          unit: 'kg',
          date: measure.date,
          measure: measure,
          showTape: true,
        ),
        app: app,
        push: true,
      );
      await t.enterText(input('Waist (navel)'), '33 33.5');
      await invokeControl(t, t.widget<BigButton>(find.byType(BigButton)).onTap);
      final saved = (await t.runAsync(BodyLogDb.measures))!.single;
      expect(saved.id, measure.id);
      expect(saved.date, measure.date);
      expect(saved.recordedAt, measuredAt);
      expect(saved.inches['futureSite'], 12.5);
      expect(saved.inches['waistNavel'], 33.25);
      expect(app.profileWrites, isEmpty);
    },
  );
  for (final embedded in [false, true]) {
    for (final weighed in [false, true]) {
      testWidgets(
        'COV-47 Today Body keeps measurement due and first weight $embedded $weighed',
        (t) async {
          await BodyLogDb.setMeasureWeekday(DateTime.now().weekday);
          if (weighed) await BodyLogDb.putWeight(todayLabel(), 70, 'kg');
          await localizedPage(
            t,
            Scaffold(body: TodayBodyRow(embedded: embedded)),
            app: app,
          );
          final text = t
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data ?? '')
              .join(' ');
          expect(
            text,
            contains(embedded ? 'Measurement day' : 'Measurement day:'),
          );
          expect(
            text,
            weighed
                ? contains('70')
                : contains(embedded ? 'Weigh in' : 'No weigh-ins'),
          );
          final take = find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Take measurements',
          );
          if (!embedded && weighed) {
            expect(take, findsOneWidget);
            await t.tap(take);
            await flush(t);
            expect(
              t.widget<BodyEntryScreen>(find.byType(BodyEntryScreen)).showTape,
              true,
            );
          }
        },
      );
    }
  }
}
