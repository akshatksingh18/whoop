// The real weekly reader/SQLite and active card, with an explicit test clock.
// Only chart input is scripted; periods, units and missing-data rendering are real.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/week_card.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class CalendarReader extends LocalRepositoryImpl {
  CalendarReader() : super(getProfileMap: () => {});
  final chartReads = <String, int>{};
  bool priorMissing = false, empty = false, chartsRefused = false;
  @override
  Future<Map<String, dynamic>> getChart(
    String key, {
    int? from,
    int? to,
  }) async {
    chartReads.update(key, (n) => n + 1, ifAbsent: () => 1);
    if (chartsRefused) throw StateError('authored optional chart refusal');
    if (empty) return {'points': []};
    final values = <String, List<num>>{
      'sleep': [420, 450, 400],
      'recovery': [60, 65, 77],
      'strain': [10, 8.5, 11],
      'steps': [5000, 6000, 9000],
    }[key]!;
    return {
      'points': [
        for (var i = 0; i < 3; i++)
          if (!(priorMissing && i == 0))
            {
              't':
                  localDayStartSec(
                    '2021-04-${[5, 12, 19][i].toString().padLeft(2, '0')}',
                  )! +
                  43200,
              'v': values[i],
            },
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CalendarReader reader;
  late AppState app;
  late UnitsController units;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('week-calendar-contract');
  });
  setUp(() async {
    await resetCoverageStore();
    reader = CalendarReader();
    app = AppState.forTesting()..repo = reader;
    units = UnitsController.withUnits();
  });
  tearDown(() {
    app.dispose();
    units.dispose();
  });
  tearDownAll(LocalDb.close);

  Future<void> loaded(WidgetTester t, int before) async {
    for (var i = 0; i < 150 && WeekCard.debugLoads <= before; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(WeekCard.debugLoads, greaterThan(before));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<String> open(WidgetTester t, DateTime now) async {
    final before = WeekCard.debugLoads;
    await localizedPage(
      t,
      Scaffold(
        body: SingleChildScrollView(child: WeekCard(clock: () => now)),
      ),
      app: app,
      units: units,
      settle: false,
    );
    await loaded(t, before);
    return (await readPage(t)).join(' ');
  }

  Future<void> noCalculatedWrites(WidgetTester t) async {
    expect(
      await t.runAsync(
        () async => (await LocalDb.instance).query('day_result'),
      ),
      isEmpty,
    );
  }

  testWidgets(
    'Monday compares only the last two closed weeks, not the current week',
    (t) async {
      final text = await open(t, DateTime(2021, 4, 19, 12));
      expect(text, contains('Last week'));
      for (final title in ['RECOVERY', 'SLEEP', 'STRAIN', 'STEPS']) {
        expect(text, contains(title));
      }
      expect(text, contains('65 · +5'));
      expect(text, contains('8.5 · −1.5'));
      expect(text, isNot(contains('77 ·')));
      expect(reader.chartReads.values, everyElement(2));
      await noCalculatedWrites(t);
    },
  );

  testWidgets(
    'missing comparison evidence keeps the observed week without a fabricated delta',
    (t) async {
      reader.priorMissing = true;
      final text = await open(t, DateTime(2021, 4, 19, 12));
      expect(text, contains('RECOVERY'));
      expect(text, contains('65'));
      expect(text, isNot(contains('65 ·')));
      expect(text, isNot(contains('8.5 ·')));
      await noCalculatedWrites(t);
    },
  );

  for (final unit in ['kg', 'lb']) {
    testWidgets(
      'closed-week weight $unit ignores a newer outside-week reading',
      (t) async {
        units.dispose();
        units = UnitsController.withUnits(weight: unit);
        await t.runAsync(() async {
          await BodyLogDb.putWeight('2021-04-12', 70, 'kg', historyOnly: true);
          await BodyLogDb.putWeight('2021-04-18', 71, 'kg', historyOnly: true);
          await BodyLogDb.putWeight('2021-04-19', 150, 'kg', historyOnly: true);
        });
        final before = await t.runAsync(
          () async => (await LocalDb.instance).query('body_weight'),
        );
        final text = await open(t, DateTime(2021, 4, 19, 12));
        expect(text, contains('WEIGHT'));
        expect(text, contains(unit == 'kg' ? '+1.0 kg' : '+2.2 lb'));
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('body_weight'),
          ),
          before,
        );
        await noCalculatedWrites(t);
      },
    );
  }

  testWidgets('Tuesday shows this week without last-week comparison labels', (
    t,
  ) async {
    final text = await open(t, DateTime(2021, 4, 20, 12));
    expect(text, contains('This week'));
    expect(text, isNot(contains('Last week')));
    expect(text, contains('SLEEP'));
    expect(text, isNot(contains('RECOVERY')));
    expect(text, isNot(contains('WEIGHT')));
    expect(reader.chartReads.values, everyElement(1));
    await noCalculatedWrites(t);
  });

  testWidgets(
    'a committed revision clears unavailable averages instead of retaining old values',
    (t) async {
      expect(await open(t, DateTime(2021, 4, 19, 12)), contains('65 · +5'));
      final before = WeekCard.debugLoads;
      reader.empty = true;
      app.bumpInsights();
      await loaded(t, before);
      final text = (await readPage(t)).join(' ');
      for (final title in ['RECOVERY', 'SLEEP', 'STRAIN', 'STEPS']) {
        expect(text, isNot(contains(title)));
      }
      expect(text, isNot(contains('65 · +5')));
      await noCalculatedWrites(t);
    },
  );

  testWidgets(
    'optional chart refusal withholds averages without inventing zero or a failed mandatory read',
    (t) async {
      reader.chartsRefused = true;
      final text = await open(t, DateTime(2021, 4, 19, 12));
      expect(text, contains('Last week'));
      expect(text, isNot(contains('Week summary unavailable')));
      for (final title in ['RECOVERY', 'SLEEP', 'STRAIN', 'STEPS']) {
        expect(text, isNot(contains(title)));
      }
      await noCalculatedWrites(t);
    },
  );
}
