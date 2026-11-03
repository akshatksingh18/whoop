// A failed refresh retains the last successful breakdown. The formula and
// typed food goal remain unchanged; units affect display only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/run_history.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const authoredProfile = Profile(
  ageYears: 30,
  sex: 'f',
  heightCm: 170,
  weightKg: 70,
);

class _Repo extends LocalRepositoryImpl {
  _Repo() : super(getProfileMap: () => authoredProfile.toMap());
  bool fail = true;
  @override
  Future<num?> getMeasuredDaySteps(String date) async {
    if (fail) throw StateError('Authored movement read refusal');
    return 9000;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('maintenance-read-recovery');
  });
  setUp(() async {
    await resetCoverageStore();
    runsChanged();
  });
  tearDownAll(LocalDb.close);
  testWidgets(
    'a refused breakdown refresh retains running evidence and pound display until a newer read succeeds',
    (t) async {
      final repo = _Repo();
      final app = AppState.forTesting()
        ..repo = repo
        ..user = {...authoredProfile.toMap(), 'kcal_target': 2000};
      final units = UnitsController.seed(UnitSystem.imperial);
      addTearDown(app.dispose);
      addTearDown(units.dispose);
      final initial = DayUpkeep(
        authoredProfile,
        steps: 4000,
        date: '2021-04-06',
        eaten: 200,
        digestion: 10,
        runs: (
          kcal: runFloorKcal(runMeters: 1000, walkMeters: 0, weightKg: 70)!,
          steps: 1000,
          count: 1,
          km: 1,
        ),
      );
      final before = initial.parts!;
      await localizedPage(
        t,
        Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showMaintenance(c, initial),
              child: const Text('Open retained breakdown'),
            ),
          ),
        ),
        app: app,
        units: units,
      );
      await t.tap(find.text('Open retained breakdown'));
      await flush(t);
      expect(
        find.text(
          'Update could not load. Showing the last successful calculation.',
        ),
        findsOneWidget,
      );
      await reveal(t, find.text("How it's worked out"));
      await t.tap(find.text("How it's worked out"));
      final text = (await readPage(t)).join(' ');
      expect(text, contains('Running:'));
      expect(text, contains('in 1 run'));
      expect(text, contains('154.3 lb'));
      expect(text, contains('3,000 steps'));
      expect(initial.parts, before);
      expect(app.user!['kcal_target'], 2000);
      repo.fail = false;
      app.bumpInsights();
      await flush(t);
      final updated = (await readPage(t)).join(' ');
      expect(updated, isNot(contains('Update could not load')));
      expect(updated, contains('9,000 steps'));
      expect(updated, isNot(contains('in 1 run')));
      expect(app.user!['kcal_target'], 2000);
    },
  );
}
