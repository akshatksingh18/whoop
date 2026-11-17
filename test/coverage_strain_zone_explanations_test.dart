// Rendered explanation/interaction contracts, not new zone or strain methods.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/hr_max.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/day_strain.dart';
import 'package:whoop_companion/ui2/activity/zones.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_zones_test.dart' show measured;
import 'support/test_local_repository.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

class ZoneReader extends TestLocalRepository {
  int reads = 0;
  @override
  Future<Map<String, dynamic>> getZones() async {
    reads++;
    return measured();
  }
}

void main() {
  setUpAll(loadAuditFonts);
  Future<void> open(
    WidgetTester t,
    Widget child,
    bool localized, {
    AppState? app,
  }) async {
    if (localized || app != null) {
      await localizedPage(t, child, app: app);
    } else {
      t.view.physicalSize = const Size(430, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(theme: buildTheme(Brightness.light), home: child),
      );
      await t.pumpAndSettle();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
      });
    }
    expect(t.takeException(), isNull);
  }

  for (final localized in [false, true]) {
    for (final source in ['tanaka', 'observed', 'karvonen']) {
      testWidgets(
        '$source anchors name measured versus estimated input localized=$localized',
        (t) async {
          final set = trainingZones(
            age: 30,
            deviceFamily: 'whoop4',
            observedCeilingBpm: source == 'tanaka' ? null : 187,
            restingHrHistory: source == 'karvonen'
                ? List<double>.filled(28, 50)
                : List<double>.filled(4, 50),
          )!;
          expect(set.source, source);
          final data = ZonesData(
            source: set.source,
            age: 30,
            maxHr: set.maxHr.round(),
            ceilingBpm: source == 'tanaka' ? null : 187,
            ceilingDate: source == 'tanaka' ? null : '2021-04-06',
            ceilingSession: source == 'tanaka' ? null : 'run',
            restingHr: source == 'karvonen' ? 50 : null,
            restingDays: source == 'karvonen' ? 28 : 4,
            zones: [
              for (final z in set.zones)
                (
                  zone: z.number,
                  name: 'Zone ${z.number}',
                  lo: z.lower.round(),
                  hi: z.upper.round(),
                ),
            ],
          );
          await open(t, ZonesDetail(data: data), localized);
          final all = (await readPage(t)).join(' ');
          expect(all, contains('187'));
          expect(all, contains('Zone 1'));
          expect(
            all,
            contains(
              source == 'tanaka'
                  ? 'estimated from your age'
                  : source == 'observed'
                  ? 'highest heart rate we have seen'
                  : 'two numbers the band measured',
            ),
          );
          if (source == 'tanaka') {
            expect(all, contains('Until one is measured'));
            expect(all, isNot(contains('HIGHEST WE HAVE SEEN')));
          }
          if (source == 'observed') expect(all, contains('you have 4'));
          if (source == 'karvonen') expect(all, contains('28'));
          expect(all, contains('Not shown yet'));
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is ChartFrame && w.title == 'SESSION MINUTES, LAST 28 DAYS',
            ),
            findsNothing,
          );
        },
      );
    }
    testWidgets(
      'an unmeasured ceiling keeps its own refusal and does not prescribe an effort localized=$localized',
      (t) async {
        await open(
          t,
          const ZonesDetail(
            data: ZonesData(
              age: 30,
              ceilingNote: 'unknown_device_family:id=none',
              note: 'unknown_device_family:id=none',
            ),
          ),
          localized,
        );
        final all = (await readPage(t)).join(' ');
        expect(all, contains('No measured ceiling yet'));
        expect(
          all,
          isNot(contains('Wear the band for your normal hard sessions')),
        );
        expect(all, isNot(contains('Until one is measured, the zones below')));
      },
    );
    for (final shape in ['pyramidal', 'polarised', 'middle-heavy']) {
      testWidgets(
        '$shape distribution describes recorded minutes without a target localized=$localized',
        (t) async {
          final payload = measured();
          final distribution =
              (payload['distribution'] as Map<String, dynamic>);
          distribution['shape'] = shape;
          await open(t, ZonesDetail(data: ZonesData.parse(payload)), localized);
          final all = (await readPage(t)).join(' ');
          expect(all, contains('description, not a target'));
          expect(all, contains('12 recorded sessions'));
          final chart = find.byWidgetPredicate(
            (w) =>
                w is ChartFrame && w.title == 'SESSION MINUTES, LAST 28 DAYS',
          );
          expect(chart, findsOneWidget);
          final footnote = t.widget<ChartFrame>(chart).footnote!;
          expect(
            footnote,
            contains(
              shape == 'pyramidal'
                  ? 'pyramid'
                  : shape == 'polarised'
                  ? 'little in between'
                  : 'middle rather than',
            ),
          );
          expect(footnote, isNot(contains('80/20')));
        },
      );
    }
    testWidgets(
      'zero recorded zone minutes do not manufacture a distribution localized=$localized',
      (t) async {
        final payload = measured();
        (payload['distribution'] as Map<String, dynamic>)['minutes'] = [
          0,
          0,
          0,
          0,
          0,
        ];
        await open(t, ZonesDetail(data: ZonesData.parse(payload)), localized);
        final all = (await readPage(t)).join(' ');
        expect(all, contains('182'));
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is ChartFrame && w.title == 'SESSION MINUTES, LAST 28 DAYS',
          ),
          findsNothing,
        );
        expect(all, isNot(contains('0 min easy')));
      },
    );
    testWidgets(
      'historical strain scrubber distinguishes a recorded minute from a gap localized=$localized',
      (t) async {
        final curve = List<double?>.filled(1440, null)
          ..[0] = 1.2
          ..[1439] = 7.1;
        final data = DayStrainData(
          day: DateTime(2021, 4, 6),
          curve: curve,
          strain: 7.1,
          maxHrUsed: 187,
          rhr: 50,
          coveragePct: 50,
          wornMin: 720,
        );
        await open(t, DayStrainDetail(data: data), localized);
        final scrub = find.byType(Scrubber);
        for (final (fraction, expected) in [
          (0.0, '1.2'),
          (.5, 'not recorded'),
          (1.0, '7.1'),
        ]) {
          t.widget<Scrubber>(scrub).onChanged(fraction);
          await t.pumpAndSettle();
          final chart = find.byWidgetPredicate(
            (w) => w is ChartFrame && w.title == 'Through the day',
          );
          expect(t.widget<ChartFrame>(chart).readout, contains(expected));
        }
        final method = find.text("How it's worked out");
        await reveal(t, method);
        await t.tap(method);
        await t.pumpAndSettle();
        final all = (await readPage(t)).join(' ');
        expect(all, contains('50 bpm last night'));
        expect(all, contains('187 bpm'));
        expect(all, contains('50%'));
        expect(all, contains('not comparable'));
      },
    );
  }
  testWidgets(
    'the saved-day zone action opens the existing measured-zone reader',
    (t) async {
      final reader = ZoneReader();
      final app = AppState.forTesting()..repo = reader;
      addTearDown(app.dispose);
      await open(
        t,
        DayStrainDetail(
          data: DayStrainData(
            day: DateTime(2021, 4, 6),
            strain: 7,
            zoneMin: const [10, 20, 3, 4, 5],
          ),
        ),
        true,
        app: app,
      );
      final section = find.byWidgetPredicate(
        (w) => w is Section && w.action == 'How these are set',
      );
      await reveal(t, section);
      t.widget<Section>(section).onAction!();
      await t.pumpAndSettle();
      expect(find.byType(ZonesDetail), findsOneWidget);
      expect(reader.reads, 1);
      expect(find.text('182'), findsOneWidget);
    },
  );
}
