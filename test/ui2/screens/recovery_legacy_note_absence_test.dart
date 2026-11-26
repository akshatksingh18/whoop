// A retained diagnostic can have observations while the score is unknown.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';

import 'body_history_actions_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('recovery-legacy-note-absence');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';

  for (final (note, scale) in <(String?, double)>[(null, 1), ('', 3.1)]) {
    testWidgets(
      'retained diagnostic with note ${note == null ? 'missing' : 'empty'} stays unscored at ${scale}x',
      (t) async {
        final repo = LocalRepositoryImpl(getProfileMap: () => {});
        final app = AppState.forTesting()..repo = repo;
        addTearDown(app.dispose);
        final diag = <String, dynamic>{
          'note': ?note,
          for (final key in ['hrv', 'rhr', 'sleep', 'resp', 'temp'])
            key: {'value': true, 'baseline_n': 4},
        };
        final db = (await t.runAsync(() async {
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: 99,
            payloadJson: jsonEncode({'readiness_absent_diag': diag}),
            windowJson: '{}',
            series: {},
          );
          return LocalDb.instance;
        }))!;
        final before = await t.runAsync(() => db.query('day_result'));
        final data = (await t.runAsync(
          () => ReadinessData.load(repo, day: day),
        ))!;
        expect(data.readiness.value, isNull);
        expect(data.absentDiag, diag);

        await localizedPage(
          t,
          const ReadinessDetail(day: day),
          app: app,
          scale: scale,
          settle: false,
        );
        await flush(t);
        final page = (await readPage(t)).join(' ');
        expect(
          page,
          contains(
            'Everything above was present, and the comparison against your own history still could not be made.',
          ),
        );
        expect(page, contains('Resting HR'));
        expect(page, contains('4 nights of your own history'));
        expect(await t.runAsync(() => db.query('day_result')), before);
        expect(await t.runAsync(() => db.query('metric_series')), isEmpty);
      },
    );
  }
}
