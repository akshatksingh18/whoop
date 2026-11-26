// Real retained days -> default-day Naps entry;no fabricated repository answers.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/naps.dart';
import 'body_history_actions_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('today-nap-entry-handoff', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'undated nap entry reads today instead of the most recent retained day at ${scale}x',
      (t) async {
        final today = todayLabel();
        final parsed = DateTime.parse(today);
        final older = dayLabelOf(
          DateTime(parsed.year, parsed.month, parsed.day - 2),
        );
        for (final day in [older, today]) {
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({
              'naps': {'value': <Object>[]},
            }),
            windowJson: '{}',
          );
        }
        final db = await LocalDb.instance;
        final stored = await db.query('day_result', orderBy: 'day_id');
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        addTearDown(app.dispose);
        final data = (await t.runAsync(() => NapsData.load(app.repo!)))!;
        expect(data.day, today);
        expect(data.days, containsAll([today, older]));
        expect(data.judged, true);
        expect(data.naps, isEmpty);
        await localizedPage(t, const NapsScreen(), app: app, scale: scale);
        await flush(t);
        expect(find.text('No naps on this day'), findsOneWidget);
        expect(find.text('No nap reading for this day'), findsNothing);
        expect(find.text('Log a nap'), findsOneWidget);
        expect(
          await t.runAsync(() => db.query('day_result', orderBy: 'day_id')),
          stored,
        );
        expect(await t.runAsync(() => db.query('sleep_nap')), isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}
