// Food root/history and library label contracts, authored SQLite only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class FoodRepo extends LocalRepositoryImpl {
  FoodRepo() : super(getProfileMap: () => {});
  @override
  Future<num?> getMeasuredDaySteps(String day) async => 6000;
}

Future<void> io(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

String ago(int n) {
  final now = DateTime.now();
  return dayLabelOf(DateTime(now.year, now.month, now.day - n));
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('nutrition-root');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<AppState> seed() async {
    final app = AppState.forTesting()
      ..user = {
        'age': 30,
        'sex': 'f',
        'height_cm': 170.0,
        'weight_kg': 70.0,
        'kcal_target': 2000,
        'protein_target': 100,
      }
      ..repo = FoodRepo();
    final db = await LocalDb.instance;
    for (var i = 0; i < 30; i++) {
      final day = ago(i);
      await NutritionDb.put(
        db,
        FoodEntry(
          id: 'synthetic-$i',
          date: day,
          meal: 'lunch',
          label: 'Synthetic meal',
          kcal: 1800,
          proteinG: 110,
          atTs: localDayStartSec(day)! + 43200,
        ),
      );
      await NutritionDb.setDayMark(db, day, 'complete');
      await BodyLogDb.putWeight(day, 70 + i * .01, 'kg', historyOnly: true);
    }
    for (final (key, label) in [
      ('alpha', 'Synthetic alpha'),
      ('beta', 'Synthetic beta'),
    ])
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(
          key: 'my:$key',
          label: label,
          refGrams: 100,
          unit: 'g',
          kcal: 100,
          protein: 0,
          category: key,
        ),
      );
    return app;
  }

  testWidgets(
    'COV-44 Food history combines only counted closed days and retains chart selection',
    (t) async {
      final app = await t.runAsync(seed);
      addTearDown(app!.dispose);
      await localizedPage(
        t,
        const Scaffold(body: NutritionScreen()),
        app: app,
        settle: false,
      );
      await io(t);
      await t.tap(find.text('History'));
      await io(t);
      final text = (await readPage(t)).join(' ');
      expect(text, contains('This week'));
      expect(text, contains('AVG EATEN'));
      expect(
        text,
        contains('Today and detectably incomplete logs are excluded.'),
      );
      await reveal(t, find.byType(Scrubber).first);
      t.widget<Scrubber>(find.byType(Scrubber).first).onChanged(0);
      await t.pumpAndSettle();
      expect(
        t.widget<ChartFrame>(find.byType(ChartFrame).first).readout,
        isNotNull,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  for (final remove in [false, true]) {
    testWidgets(
      'COV-44 Food library ${remove ? 'removes' : 'merges'} labels without deleting foods',
      (t) async {
        final app = await t.runAsync(seed);
        addTearDown(app!.dispose);
        await localizedPage(
          t,
          const Scaffold(body: NutritionScreen()),
          app: app,
          settle: false,
        );
        await io(t);
        await t.tap(find.text('Foods'));
        await io(t);
        final text = (await readPage(t)).join(' ');
        expect(text, contains('Synthetic alpha'));
        expect(text, contains('Synthetic beta'));
        final manage = find.text('Manage labels');
        await reveal(t, manage);
        await t.tap(manage);
        await t.pumpAndSettle();
        await t.tap(find.byTooltip(remove ? 'Remove alpha' : 'Rename alpha'));
        await t.pumpAndSettle();
        if (remove) {
          await t.tap(find.text('Remove'));
        } else {
          await t.enterText(find.byType(TextField).last, 'beta');
          await t.tap(find.text('Save').last);
        }
        await io(t);
        final defs = await t.runAsync(
          () async => MyFoods.all(await LocalDb.instance),
        );
        expect(defs, hasLength(2));
        expect(
          defs!.singleWhere((d) => d['key'] == 'my:alpha')['category'],
          remove ? '' : 'beta',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
  for (final refused in [false, true]) {
    testWidgets(
      'COV-44 Food weigh-in validates input and preserves the first reading $refused',
      (t) async {
        final app = await t.runAsync(seed);
        addTearDown(app!.dispose);
        await localizedPage(
          t,
          const Scaffold(body: NutritionScreen()),
          app: app,
          settle: false,
        );
        await io(t);
        await t.tap(find.text('History'));
        await io(t);
        final log = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Log weight',
        );
        await reveal(t, log);
        await t.tap(log);
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).last, '0');
        await t.tap(find.text('Save').last);
        await t.pumpAndSettle();
        expect(find.textContaining('Enter a weight from'), findsOneWidget);
        final db = (await t.runAsync(() => LocalDb.instance))!;
        if (refused)
          await t.runAsync(
            () => db.execute(
              "CREATE TRIGGER synthetic_weight_refusal BEFORE INSERT ON body_weight_reading BEGIN SELECT RAISE(ABORT,'synthetic weight refusal'); END",
            ),
          );
        await t.enterText(find.byType(TextField).last, '71.3');
        await t.tap(find.text('Save').last);
        await io(t);
        if (refused) {
          expect(
            find.text('Weight was not saved. Please try again.'),
            findsOneWidget,
          );
          expect(
            await t.runAsync(() => BodyLogDb.readingsOn(todayLabel())),
            hasLength(1),
          );
          await t.runAsync(
            () => db.execute('DROP TRIGGER synthetic_weight_refusal'),
          );
          await reveal(t, log);
          await t.tap(log);
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField).last, '71.3');
          await t.tap(find.text('Save').last);
          await io(t);
        }
        final readings = (await t.runAsync(
          () => BodyLogDb.readingsOn(todayLabel()),
        ))!;
        expect(readings, hasLength(2));
        expect(readings.map((w) => w.kg), contains(71.3));
        expect(
          (await t.runAsync(() => BodyLogDb.weightOn(todayLabel())))!.kg,
          70,
        );
        expect(app.user!['weight_kg'], 70);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
  for (final compact in [false, true]) {
    for (final known in [false, true]) {
      testWidgets(
        'COV-44 maintenance card retains lifting and unknown overlap disclosures $compact $known',
        (t) async {
          final upkeep = DayUpkeep(
            const Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70),
            steps: known ? 6000 : null,
            eaten: 1800,
            walkingMeters: known ? 4000 : null,
            overlapUnknown: !known,
            lifting: (kcal: 100, sessions: 1, approximate: !known),
            digestion: 100,
            date: '2021-04-06',
          );
          await localizedPage(
            t,
            Scaffold(
              body: SingleChildScrollView(
                child: MaintenanceCard(upkeep, compact: compact),
              ),
            ),
          );
          final surface = find
              .byWidgetPredicate((w) => w is Surface && w.onTap != null)
              .first;
          await t.tap(surface);
          await t.pumpAndSettle();
          final text = (await readPage(t)).join(' ');
          expect(text, contains('With lifting'));
          expect(text, contains('100'));
          if (!known) expect(text, contains('Steps unknown'));
        },
      );
    }
  }
}
