// Shipped activity summaries and setup contracts under the real delegates.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/activity/setup.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_activity_summary_views_test.dart'
    as samples
    show result, start;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('localized-activity');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final name in [
    'Running',
    'Walking',
    'Hiking',
    'HIIT',
    'Swimming',
    'Yoga',
    'Tennis',
    'General workout',
    'Sauna',
    'Cold plunge',
  ]) {
    for (final populated in [false, true]) {
      testWidgets(
        'COV-44 localized $name keeps every summary tab and missing trace $populated',
        (t) async {
          final r = samples.result(name, populated: populated);
          await localizedPage(t, ActivitySummary(r));
          final overview = await readPage(t);
          expect(overview.join(' '), contains(name));
          expect(overview.join(' '), isNot(contains('NaN')));
          if (name == 'Yoga') expect(overview, contains('Private'));
          Future<void> tab(String label) async {
            final f = find.text(label);
            await t.tap(f.first);
            await t.pumpAndSettle();
          }

          if (find.text('Splits').evaluate().isNotEmpty) {
            await tab('Splits');
            final text = (await readPage(t)).join(' ');
            if (!populated)
              expect(
                text,
                contains(
                  name == 'HIIT'
                      ? 'No rounds'
                      : name == 'Swimming'
                      ? 'No laps'
                      : 'No splits',
                ),
              );
          }
          await tab('Graphs');
          final graphs = (await readPage(t)).join(' ');
          if (populated) {
            final frames = t.widgetList<ChartFrame>(find.byType(ChartFrame));
            expect(frames.any((f) => f.series.contains(null)), true);
          } else {
            expect(
              graphs,
              contains(
                ['Sauna', 'Cold plunge'].contains(name)
                    ? 'Nothing to plot'
                    : 'No series to plot',
              ),
            );
          }
          await tab('Overview');
          expect((await readPage(t)).join(' '), contains(name));
        },
      );
    }
  }
  for (final sample in <(String, int?, int?, double?, String)>[
    ('Weight training', 42, null, null, 'Heart rate is shown, not counted'),
    ('HIIT', 42, null, null, 'No heart rate reached this session.'),
    ('HIIT', 42, 120, null, 'The lower of'),
    ('General workout', 42, 120, null, 'No MET is in this figure'),
    (
      'General workout',
      null,
      null,
      null,
      'No calorie figure for this session.',
    ),
    ('General workout', null, null, 4.5, 'Strain above is the effort'),
  ]) {
    testWidgets(
      'COV-48 localized ${sample.$1} energy basis preserves measured or absent inputs ${sample.$2}/${sample.$3}/${sample.$4}',
      (t) async {
        final r = ActivityResult(
          activityByName(sample.$1)!,
          start: samples.start,
          duration: const Duration(minutes: 12),
          calories: sample.$2,
          avgHr: sample.$3,
          strain: sample.$4,
          hr: sample.$3 == null ? const [] : [sample.$3!.toDouble()],
        );
        await localizedPage(t, ActivitySummary(r, weightKg: 70));
        final text = (await readPage(t)).join(' ');
        expect(text, contains(sample.$5));
        if (sample.$1 == 'Weight training') {
          expect(text, contains('Not added to maintenance.'));
        }
        if (sample.$3 == null) {
          if (sample.$1 == 'HIIT') {
            await t.tap(find.text('Graphs'));
            await t.pumpAndSettle();
            expect(
              (await readPage(t)).join(' '),
              contains('No series to plot'),
            );
          } else {
            expect(text, contains('No heart rate for this session'));
          }
        }
        expect(r.calories, sample.$2);
        expect(r.strain, sample.$4);
        expect(r.avgHr, sample.$3);
      },
    );
  }
  for (final system in UnitSystem.values) {
    testWidgets(
      'COV-48 phone-motion walk names its sensor and speed unit ${system.name}',
      (t) async {
        final units = UnitsController.seed(system);
        addTearDown(units.dispose);
        final r = ActivityResult(
          activityByName('Walking')!,
          start: samples.start,
          duration: const Duration(minutes: 12),
          distanceKm: .6,
          motionDistance: true,
          phoneSteps: 720,
          cadence: 60,
        );
        await localizedPage(t, ActivitySummary(r, weightKg: 70), units: units);
        final text = (await readPage(t)).join(' ');
        expect(text, contains('No map for this session'));
        expect(text, contains("from your phone's motion sensor"));
        expect(text, contains('Steps came from your phone'));
        expect(
          text,
          contains(system == UnitSystem.metric ? '3.0 km/h' : '1.9 mph'),
        );
        expect(r.route, isEmpty);
        expect(r.hr, isEmpty);
        expect(r.calories, isNull);
      },
    );
  }
  for (final name in ['Sauna', 'Cold plunge']) {
    testWidgets(
      'COV-48 $name retains one measured pulse minute without inventing a trace',
      (t) async {
        final r = ActivityResult(
          activityByName(name)!,
          start: samples.start,
          duration: const Duration(minutes: 1),
          hr: const [82],
          avgHr: 82,
        );
        await localizedPage(t, ActivitySummary(r));
        final text = (await readPage(t)).join(' ');
        expect(text, contains('One minute of pulse, and no more'));
        expect(
          text,
          contains(
            name == 'Sauna' ? 'Heat, sweat' : 'Cold closes the blood vessels',
          ),
        );
        expect(text, isNot(contains('No pulse reading')));
        expect(find.byType(ChartFrame), findsNothing);
        expect(r.hr, [82]);
      },
    );
  }
  for (final name in [
    'Running',
    'HIIT',
    'Yoga',
    'Swimming',
    'General workout',
  ]) {
    testWidgets(
      'COV-44 localized $name setup refuses a host failure without losing choice',
      (t) async {
        var calls = 0;
        bool? selected;
        final host = ActivityHost(
          bandConnected: false,
          onStart: (a, {bool private = false}) async {
            calls++;
            selected = private;
            throw StateError('synthetic start refusal');
          },
        );
        await localizedPage(
          t,
          ActivitySetup(activityByName(name)!, weightKg: 70, host: host),
        );
        final content = (await readPage(t)).join(' ');
        expect(content, contains('No band connected'));
        final start = find.byWidgetPredicate(
          (w) => w is BigButton && w.label == 'Start',
        );
        await reveal(t, start);
        await invokeControl(t, t.widget<BigButton>(start).onTap);
        expect(calls, 1);
        expect(selected, activityByName(name)!.private);
        expect(find.byType(ActivitySetup), findsOneWidget);
        expect((await readPage(t)).join(' '), contains('already running'));
      },
    );
  }
}
