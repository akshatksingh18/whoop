// Shipped activity summaries and setup contracts under the real delegates.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/activity/setup.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_activity_summary_views_test.dart' as samples show result;
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
