// A real calculation-anchor refusal follows an accepted weight reading.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/profile_history.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'coverage_body_entry_decisions_test.dart' show input;
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-profile-partial-write', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  testWidgets(
    'profile refusal keeps the saved reading and retries only the profile',
    (t) async {
      final app = AppState.forTesting()..user = {'weight_kg': 70.0, 'age': 29};
      addTearDown(app.dispose);
      final day = todayLabel();
      final db = (await t.runAsync(() async {
        final db = await LocalDb.instance;
        await db.execute("""
          CREATE TRIGGER authored_profile_refusal BEFORE INSERT ON baselines
          WHEN NEW.key = '${CalculationStore.prefix}${ProfileHistory.key}'
          BEGIN SELECT RAISE(ABORT, 'authored profile refusal'); END
        """);
        return db;
      }))!;
      await localizedPage(
        t,
        const BodyEntryScreen(unit: 'kg'),
        app: app,
        push: true,
      );
      await t.enterText(input('Weight (kg)'), '71.5');
      Future<void> save() async {
        final control = find.widgetWithText(BigButton, 'Save');
        await reveal(t, control);
        await t.tap(control);
        await flush(t);
      }

      await save();

      expect(
        find.textContaining(
          'your current weight for calculations did not save',
        ),
        findsOneWidget,
      );
      expect(app.user, {'weight_kg': 70.0, 'age': 29});
      final first = (await t.runAsync(() => BodyLogDb.readingsOn(day)))!.single;
      expect(first.kg, 71.5);
      expect(
        await t.runAsync<String?>(
          () => CalculationStore.read(ProfileHistory.key),
        ),
        isNull,
      );

      await t.runAsync(
        () => db.execute('DROP TRIGGER authored_profile_refusal'),
      );
      await save();
      expect(find.byType(BodyEntryScreen), findsNothing);
      expect(app.user, {'weight_kg': 71.5, 'age': 29});
      final after = (await t.runAsync(() => BodyLogDb.readingsOn(day)))!.single;
      expect(after.id, first.id);
      expect(after.kg, first.kg);
      final history = ProfileHistory.decode(
        await t.runAsync<String?>(
          () => CalculationStore.read(ProfileHistory.key),
        ),
      );
      expect(history[day]['weight_kg'], 71.5);
    },
  );
}
