// An embedded historical strain trace identifies its own recorded date.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/day_strain.dart';

import '../screens/body_history_actions_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('embedded-strain-date-ownership');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final historical in [false, true]) {
    testWidgets(
      'embedded strain keeps the actual trace date: historical $historical',
      (t) async {
        final day = historical ? '2021-04-06' : todayLabel();
        final start = localDayStartSec(day)!;
        final repo = LocalRepositoryImpl(getProfileMap: () => {});
        final app = AppState.forTesting()..repo = repo;
        addTearDown(app.dispose);
        final db = (await t.runAsync(() async {
          await DayResultStore.put(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({
              'scalars': {'strain': 5.2},
              'series': {
                'strain_curve': [
                  {'t': start + 3600, 'v': 2.1},
                  {'t': start + 7200, 'v': 5.2},
                ],
              },
            }),
            windowJson: '{}',
            series: {'strain': 5.2},
          );
          return LocalDb.instance;
        }))!;
        final before = await t.runAsync(() => db.query('day_result'));
        final data = (await t.runAsync(
          () => DayStrainData.load(repo, want: day),
        ))!;
        expect(dayLabelOf(data.day!), day);

        await localizedPage(
          t,
          DayStrainDetail(embedded: true, day: day),
          app: app,
          settle: false,
        );
        await flush(t);
        expect(find.text('5.2'), findsWidgets);
        expect(
          find.text('APRIL 6'),
          historical ? findsOneWidget : findsNothing,
        );
        expect(await t.runAsync(() => db.query('day_result')), before);
      },
    );
  }
}
