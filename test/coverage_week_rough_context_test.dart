// Recap and rough-night readers use only authored dates, signs and user choices.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/rough_night.dart';
import 'package:whoop_companion/ui2/screens/week_card.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const day = '2021-04-18';

class Reader extends LocalRepositoryImpl {
  Reader() : super(getProfileMap: () => {});
  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) async => {
    'sessions': [
      null,
      {},
      {'end_ts': 'unknown'},
      {'end_ts': DateTime(2021, 4, 18, 20, 30).millisecondsSinceEpoch ~/ 1000},
      {'end_ts': DateTime(2021, 4, 18, 19).millisecondsSinceEpoch ~/ 1000},
    ],
  };
  @override
  Future<Map<String, dynamic>> getInsights() async => {
    'recent': [
      {'date': day, 'illness': true},
    ],
  };
  @override
  Future<Map<String, dynamic>> getCycle() async => {
    'enabled': true,
    'phase': 'luteal',
  };
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async => {
    'points': [
      {'t': DateTime(2021, 4, 6, 12).millisecondsSinceEpoch ~/ 1000, 'v': 10},
      for (var i = 12; i <= 18; i++)
        {
          't': DateTime(2021, 4, i, 12).millisecondsSinceEpoch ~/ 1000,
          'v': metric == 'sleep' ? 420 : 60,
        },
    ],
  };
  @override
  Future<num?> getMeasuredDaySteps(String date) async => 5000;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('week-rough-context');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  test(
    'rough-night read names only known context and retains the explicit night',
    () async {
      final db = await LocalDb.instance;
      for (var i = 1; i <= 18; i++) {
        final d = dayLabelOf(DateTime(2021, 4, i));
        for (final e in {
          'rhr': i == 18 ? 90.0 : 60.0 + i % 3,
          'rmssd': i == 18 ? 20.0 : 65.0 + i % 3,
          'dip_pct': i == 18 ? 5.0 : 30.0 + i % 3,
        }.entries) {
          await db.insert('metric_series', {
            'date': d,
            'key': e.key,
            'value': e.value,
          });
        }
      }
      final n = (await loadRoughNight(Reader(), day))!;
      expect(n.day, day);
      expect(n.rough, isTrue);
      expect(n.signs, 3);
      expect(n.moved, hasLength(3));
      expect(n.knows.any((s) => s.contains('8:30 PM')), isTrue);
      expect(n.knows.any((s) => s.contains('illness')), isTrue);
      expect(n.knows.any((s) => s.contains('luteal')), isTrue);
      expect(n.illnessFlagged, isTrue);
    },
  );
  testWidgets(
    'attribution vocabulary stays hidden until opt-in and never-ask survives reopening',
    (t) async {
      const n = RoughNight(
        day: day,
        signs: 2,
        descriptor: 'A harder night — measured signs only',
        moved: ['resting heart rate', 'HRV'],
        knows: [],
      );
      await localizedPage(
        t,
        const Scaffold(
          body: SingleChildScrollView(child: RoughNightCard(night: n)),
        ),
      );
      expect(find.text('alcohol'), findsNothing);
      final invite = find.byType(BigButton);
      await invokeControl(t, t.widget<BigButton>(invite).onTap);
      expect(Prefs.getString(kRoughNightAsk, ''), 'on');
      expect(find.text('alcohol'), findsOneWidget);
      await reveal(t, find.text('Do not ask again'));
      await t.tap(find.text('Do not ask again'));
      await t.pumpAndSettle();
      expect(Prefs.getString(kRoughNightAsk, ''), 'never');
      expect(find.text('alcohol'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await localizedPage(t, const Scaffold(body: RoughNightCard(night: n)));
      expect(find.text('Tell it what happened'), findsNothing);
      expect(find.textContaining('Nothing to answer'), findsOneWidget);
    },
  );
  test(
    'completed prior week uses its own dates and measured weight change',
    () async {
      final db = await LocalDb.instance;
      for (var i = 12; i <= 18; i++) {
        final d = dayLabelOf(DateTime(2021, 4, i));
        await NutritionDb.put(
          db,
          FoodEntry(
            id: 'synthetic-week-$i',
            date: d,
            meal: 'lunch',
            label: 'Synthetic food',
            kcal: 1800,
            proteinG: 110,
          ),
        );
        await NutritionDb.setDayMark(db, d, 'complete');
        await BodyLogDb.putWeight(
          d,
          70 + (i - 12) * .1,
          'kg',
          historyOnly: false,
        );
      }
      final w = await WeekNumbers.load(
        Reader(),
        const Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70),
        {'protein_target': 120},
        at: DateTime(2021, 4, 19, 12),
        weeksBack: 1,
      );
      expect(w.daysLogged, 7);
      expect(w.proteinDays, 7);
      expect(w.avgProtein, 110);
      expect(w.avgSleepMin, 420);
      expect(w.avgRecovery, 60);
      expect(w.weightChangeKg, closeTo(.6, .00001));
      final before = await WeekNumbers.load(
        Reader(),
        const Profile(),
        {},
        at: DateTime(2021, 4, 19, 12),
        weeksBack: 1,
        withFood: false,
      );
      expect(before.daysLogged, 0);
      expect(before.deficit, isNull);
      expect(before.avgSleepMin, 420);
    },
  );
  for (final surplus in [false, true]) {
    testWidgets(
      'weekly ${surplus ? 'surplus' : 'deficit'} summary names energy and incomplete days',
      (t) async {
        final w = WeekNumbers(
          deficit: surplus ? -300 : 300,
          acsmDeficit: surplus ? -250 : 350,
          daysLogged: 5,
          daysExcluded: 2,
          proteinDays: 4,
          avgProtein: 110,
          proteinTarget: surplus ? null : 120,
          avgSleepMin: 420,
          avgRecovery: 65,
          avgStrain: 8,
          avgSteps: 5000,
          weightChangeKg: surplus ? .5 : -.5,
        );
        await localizedPage(
          t,
          Scaffold(
            body: SingleChildScrollView(child: WeekCard(data: w)),
          ),
        );
        final text = (await readPage(t)).join(' ');
        expect(text, contains(surplus ? 'BUDGET SURPLUS' : 'BUDGET DEFICIT'));
        expect(text, contains('300 kcal'));
        expect(text, contains('2 unfinished excluded'));
        expect(text, contains('protein on 4 days'));
        expect(text, contains('7h 00m'));
        expect(text, contains('SLEEP'));
      },
    );
  }
}
