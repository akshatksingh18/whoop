// An accepted reading survives a refused tape write and nonduplicating retry.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'coverage_body_entry_decisions_test.dart' show input;
import 'coverage_body_history_actions_test.dart' show App;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-tape-partial-write');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final historical in [false, true]) {
    testWidgets(
      'tape refusal preserves one accepted weight on historical day $historical',
      (t) async {
        final app = App()..user = {'weight_kg': 70.0};
        addTearDown(app.dispose);
        final day = historical ? '2021-04-06' : todayLabel();
        final db = await LocalDb.instance;
        await db.execute('''
        CREATE TRIGGER authored_tape_refusal BEFORE INSERT ON body_measure
        BEGIN SELECT RAISE(ABORT, 'authored tape refusal'); END
      ''');
        addTearDown(
          () => db.execute('DROP TRIGGER IF EXISTS authored_tape_refusal'),
        );
        await localizedPage(
          t,
          BodyEntryScreen(unit: 'kg', date: day, showTape: true),
          app: app,
          push: true,
        );
        await t.enterText(input('Weight (kg)'), '71.5');
        await t.enterText(input('Waist (navel)'), '33');
        Future<void> save() => invokeControl(
          t,
          t.widget<BigButton>(find.widgetWithText(BigButton, 'Save')).onTap,
        );
        await save();
        expect(find.byType(BodyEntryScreen), findsOneWidget);
        expect(find.textContaining('tape did not save'), findsOneWidget);
        expect(find.textContaining('The weight was saved'), findsOneWidget);
        final first = (await t.runAsync(
          () => BodyLogDb.readingsOn(day),
        ))!.single;
        expect(first.kg, 71.5);
        expect(await t.runAsync(BodyLogDb.measures), isEmpty);
        expect(app.profileWrites, hasLength(historical ? 0 : 1));

        await t.runAsync(
          () => db.execute('DROP TRIGGER authored_tape_refusal'),
        );
        await save();
        expect(find.byType(BodyEntryScreen), findsNothing);
        final readings = (await t.runAsync(() => BodyLogDb.readingsOn(day)))!;
        expect(readings.single.id, first.id);
        expect(readings.single.kg, 71.5);
        final tape = (await t.runAsync(BodyLogDb.measures))!.single;
        expect(tape.date, day);
        expect(tape.inches['waistNavel'], 33);
        expect(app.profileWrites, hasLength(historical ? 0 : 1));
      },
    );
  }
}
