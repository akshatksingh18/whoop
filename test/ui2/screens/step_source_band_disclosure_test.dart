// Paired-band metadata leaves the approved phone-only step policy intact.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_companion/ui2/screens/day_steps.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'body_history_actions_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('step-source-band-disclosure');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final (family, label) in <(String?, String)>[
    (null, 'Your band'),
    ('gen4', 'WHOOP 4'),
    ('gen5', 'WHOOP 5'),
  ]) {
    testWidgets(
      'saved step windows remain phone-only alongside the $label label',
      (t) async {
        const day = '2021-04-06';
        final start = localDayStartSec(day)! + 10 * 3600;
        final app = AppState.forTesting()
          ..paired = PairedDevice(
            'authored-mixed-steps-band',
            null,
            generation: family,
          )
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        app.device.generation = family;
        addTearDown(app.dispose);
        final db = (await t.runAsync(() async {
          await LocalDb.addLiveCoverage(start, start + 1800, 300, day);
          await LocalDb.replacePhoneCoverageForDay(day, [
            (startTs: start + 3600, endTs: start + 5400, steps: 450),
          ]);
          return LocalDb.instance;
        }))!;
        final before = await t.runAsync(
          () => db.query('live_coverage', orderBy: 'start_ts'),
        );
        await localizedPage(
          t,
          const DayStepsDetail(day: day),
          app: app,
          settle: false,
        );
        await flush(t);
        final chart = find.byType(ChartFrame);
        await reveal(t, chart);
        expect(bandLabel(t.element(chart)), label);
        expect(t.widget<ChartFrame>(chart).legend, isEmpty);
        expect(find.text('450'), findsOneWidget);
        expect(find.text('Your phone'), findsOneWidget);
        expect(find.text('750'), findsNothing);
        expect(find.text('300'), findsNothing);
        expect(
          await t.runAsync(
            () => db.query('live_coverage', orderBy: 'start_ts'),
          ),
          before,
        );
        expect(app.paired?.generation, family);
      },
    );
  }
}
