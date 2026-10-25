// Recorded detail -> each reachable summary tab, with synthetic inputs only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

final start = DateTime(2026, 1, 6, 8);
ActivityResult result(String name, {bool populated = true}) => ActivityResult(
  activityByName(name)!,
  start: start,
  duration: const Duration(minutes: 12),
  private: name == 'Yoga',
  avgHr: populated ? 125 : null,
  maxHr: populated ? 151 : null,
  hrr60: populated ? 18 : null,
  calories: populated ? 95 : null,
  strain: populated ? 4.5 : null,
  hr: populated ? const [112, 125, null, 151, 128] : const [],
  traceCoveragePct: populated ? 80 : null,
  zoneMinutes: populated ? const [3, 4, 2, 1, 0] : const [],
  zoneSource: populated ? 'observed' : null,
  zoneMaxHr: populated ? 190 : null,
  route: populated && name == 'Running'
      ? const [Offset(.1, .2), Offset(.4, .3), Offset(.7, .8)]
      : const [],
  routePace: populated && name == 'Running' ? const [.1, .7, .3] : null,
  distanceKm: populated && (name == 'Running' || name == 'Hiking') ? 2.4 : null,
  elevationM: populated && name == 'Hiking'
      ? const [101, 109, 107, 119]
      : const [],
  gainM: populated && name == 'Hiking' ? 20 : null,
  lossM: populated && name == 'Hiking' ? 2 : null,
  splits: populated && (name == 'Running' || name == 'Hiking')
      ? const [
          KmSplit(1, 300, avgHr: 120),
          KmSplit(1, 330),
          KmSplit(.4, 144, avgHr: 140),
        ]
      : const [],
  lapSecs: populated && name == 'Swimming' ? const [38, 44, 41] : const [],
  poolLengthM: populated && name == 'Swimming' ? 25 : null,
  stroke: populated && name == 'Swimming' ? 'Free' : null,
  rounds: populated && name == 'HIIT'
      ? const [IntervalRound(45, 30, avgHr: 145), IntervalRound(50, 25)]
      : const [],
  poses: populated && name == 'Yoga' ? const ['Mountain', 'Plank'] : const [],
  breathsPerMin: populated && name == 'Yoga' ? 6.2 : null,
  gameScore: populated && name == 'Tennis' ? const [(6, 4), (3, 6)] : const [],
);

Future<Set<String>> scrollAll(WidgetTester t) async {
  final seen = <String>{};
  void read() => seen.addAll(
    t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
  );
  final state = t.state<ScrollableState>(find.byType(Scrollable).last);
  final p = state.position;
  p.jumpTo(0);
  await t.pumpAndSettle();
  read();
  while (p.extentAfter > .5) {
    p.jumpTo((p.pixels + 400).clamp(0, p.maxScrollExtent));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    read();
  }
  return seen;
}

Future<void> open(
  WidgetTester t,
  ActivityResult r, {
  double scale = 1,
  UnitsController? units,
}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider.value(
      value: units ?? UnitsController.seed(UnitSystem.metric),
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ActivitySummary(r),
      ),
    ),
  );
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> tab(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label).first);
  await t.pumpAndSettle();
  await t.tap(find.text(label).first);
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAuditFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
  });

  for (final (name, defining) in [
    ('Running', 'ROUTE'),
    ('HIIT', 'INTERVAL LADDER'),
    ('Swimming', 'LAPS'),
    ('Hiking', 'ELEVATION'),
    ('Yoga', '2 poses'),
    ('Tennis', 'HEART RATE'),
    ('General workout', 'HEART RATE'),
  ]) {
    testWidgets('$name keeps its defining record and all reachable tabs', (
      t,
    ) async {
      final r = result(name);
      await open(t, r);
      final seen = await scrollAll(t);
      expect(seen, contains(defining));
      // The numeric table must retain measured maxima and recovery, not only the hero.
      expect(seen, contains('MAX HR'));
      expect(seen, contains('HR RECOVERY'));
      if (name == 'Yoga') expect(seen, contains('Private'));
      if (name == 'Tennis') {
        expect(seen, containsAll(['6 — 4', '3 — 6']));
      }
      if ([Arch.flow, Arch.match, Arch.basic].contains(r.arch)) {
        expect(find.text('Splits'), findsNothing);
      } else {
        await tab(t, 'Splits');
        await scrollAll(t);
        switch (r.arch) {
          case Arch.route || Arch.journey:
            // Trailing 0.4km in 144s is 6:00/km, not 2:24/km.
            expect(find.text('6:00'), findsOneWidget);
            expect(find.text('0.4'), findsOneWidget);
            expect(find.text('2:24'), findsNothing);
          case Arch.interval:
            expect(find.text('00:45'), findsOneWidget);
            expect(find.text('00:25'), findsOneWidget);
            expect(find.text('145'), findsOneWidget);
          case Arch.laps:
            expect(find.text('00:38'), findsOneWidget);
            expect(find.text('00:44'), findsOneWidget);
          default:
            fail('An unreachable splits tab was added');
        }
      }
      await tab(t, 'Graphs');
      expect(find.text('HEART RATE'), findsOneWidget);
      final frames = t.widgetList<ChartFrame>(find.byType(ChartFrame));
      expect(
        frames.any((f) => f.series.length == 5 && f.series[2] == null),
        isTrue,
        reason: 'Missing minute must remain a gap in the chart',
      );
      await scrollAll(t);
      await tab(t, 'Overview');
      expect(await scrollAll(t), contains(defining));
    });
  }

  for (final (name, missing) in [
    ('Running', 'No route for this session'),
    ('HIIT', 'No rounds recorded'),
    ('Swimming', 'No laps counted'),
    ('Hiking', 'No elevation profile'),
    ('Tennis', 'No heart rate for this session'),
    ('General workout', 'No heart rate for this session'),
  ]) {
    testWidgets('$name has honest empty details with no invented series', (
      t,
    ) async {
      await open(t, result(name, populated: false));
      expect(find.text(missing), findsOneWidget);
      await tab(t, 'Graphs');
      expect(find.text('No series to plot'), findsOneWidget);
      expect(find.text('Check band connection'), findsOneWidget);
      expect(find.byType(ChartFrame), findsNothing);
      if (find.text('Splits').evaluate().isNotEmpty) {
        await tab(t, 'Splits');
        expect(
          find.text(
            name == 'HIIT'
                ? 'No rounds recorded'
                : name == 'Swimming'
                ? 'No laps counted'
                : 'No splits for this session',
          ),
          findsOneWidget,
        );
      }
    });
  }

  for (final name in ['Sauna', 'Cold plunge']) {
    for (final hr in <List<double?>>[
      [],
      [111],
      [null, 111, null, 120],
    ]) {
      testWidgets(
        '$name explains ${hr.length} pulse slots without a false connection fix',
        (t) async {
          await open(t, result(name, populated: false).copyWith(hr: hr));
          await scrollAll(t);
          expect(find.text('Check band connection'), findsNothing);
          if (hr.length > 1) {
            expect(find.textContaining('2 of 4 minutes'), findsOneWidget);
          } else {
            expect(
              find.text(
                hr.isEmpty
                    ? 'No pulse reading for this ${name.toLowerCase()}'
                    : 'One minute of pulse, and no more',
              ),
              findsOneWidget,
            );
          }
          await tab(t, 'Graphs');
          expect(find.text('Check band connection'), findsNothing);
          if (hr.isEmpty)
            expect(
              find.text('Nothing to plot for this ${name.toLowerCase()}'),
              findsOneWidget,
            );
          if (hr.length == 1)
            expect(find.text('Too short to chart'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('a one-minute session is too short, not a disconnected band', (
    t,
  ) async {
    await open(
      t,
      result('General workout', populated: false).copyWith(hr: [123]),
    );
    expect(find.text('Too short to chart'), findsOneWidget);
    expect(find.text('Check band connection'), findsNothing);
    await tab(t, 'Graphs');
    expect(find.text('Too short to chart'), findsOneWidget);
  });

  testWidgets(
    'rounds without HR omit the HR column but preserve work and rest',
    (t) async {
      await open(
        t,
        result('HIIT').copyWith(rounds: [const IntervalRound(40, 20)]),
      );
      await tab(t, 'Splits');
      expect(find.text('AVG BPM'), findsNothing);
      expect(find.text('00:40'), findsOneWidget);
      expect(find.text('00:20'), findsOneWidget);
    },
  );

  for (final milesAvailable in [false, true]) {
    testWidgets(
      'miles selected with ${milesAvailable ? 'mile' : 'legacy km'} splits',
      (t) async {
        await open(
          t,
          result(
            'Running',
          ).copyWith(mileSplits: milesAvailable ? [const KmSplit(1, 510)] : []),
          units: UnitsController.seed(UnitSystem.imperial),
        );
        await tab(t, 'Splits');
        expect(find.text(milesAvailable ? 'MI' : 'KM'), findsOneWidget);
        expect(
          find.text('km splits (as recorded)'),
          milesAvailable ? findsNothing : findsOneWidget,
        );
        expect(find.text(milesAvailable ? '8:30' : '6:00'), findsOneWidget);
      },
    );
  }

  for (final scale in [2.0, 3.1]) {
    testWidgets('all General workout views remain readable at ${scale}x', (
      t,
    ) async {
      await open(t, result('General workout'), scale: scale);
      await scrollAll(t);
      await tab(t, 'Graphs');
      await scrollAll(t);
      expect(find.text('HEART RATE'), findsOneWidget);
    });
  }
}
