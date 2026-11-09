// The router's real setup wrapper, with only its final profile write held/refused.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/onboarding/profile_setup.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class ProfileWriter extends AppState {
  ProfileWriter() : super.forTesting();
  final writes = <Map<String, dynamic>>[];
  Completer<void>? gate;
  bool refuse = false;
  @override
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> fields,
  ) async {
    writes.add(Map.of(fields));
    await gate?.future;
    if (refuse) throw StateError('authored profile write refused');
    return user = {...?user, ...fields};
  }
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('profile-gate-handoff');
  });
  setUp(resetCoverageStore);
  late ProfileWriter app;
  setUp(() => app = ProfileWriter());
  tearDown(() => app.dispose());
  Future<void> press(WidgetTester t) async {
    await reveal(t, find.byType(BigButton));
    await t.tap(find.byType(BigButton));
    await t.pumpAndSettle();
  }

  for (final imperial in [false, true]) {
    testWidgets(
      'setup wrapper preserves unchanged metric precision imperial=$imperial',
      (t) async {
        app.user = {
          'sex': 'f',
          'age': 30,
          'height_cm': 170.123,
          'weight_kg': 70.123,
        };
        var done = 0;
        final units = UnitsController.seed(
          imperial ? UnitSystem.imperial : UnitSystem.metric,
        );
        addTearDown(units.dispose);
        await localizedPage(
          t,
          ProfileSetupScreen(onDone: () => done++),
          app: app,
          units: units,
        );
        await press(t);
        expect(app.writes, [app.user]);
        expect(done, 1);
        expect(app.writes.single['height_cm'], 170.123);
        expect(app.writes.single['weight_kg'], 70.123);
      },
    );
  }

  for (final (choice, code) in [
    ('Female', 'f'),
    ('Male', 'm'),
    ('Prefer not to say', 'other'),
  ]) {
    testWidgets(
      'setup gate accepts a deliberate partial $code profile without invented measurements',
      (t) async {
        var done = 0;
        final units = UnitsController.withUnits();
        addTearDown(units.dispose);
        await localizedPage(
          t,
          ProfileSetupScreen(onDone: () => done++),
          app: app,
          units: units,
        );
        expect(t.widget<BigButton>(find.byType(BigButton)).onTap, isNull);
        await t.tap(find.text(choice));
        await t.pumpAndSettle();
        if (code == 'other') {
          expect(
            (await readPage(t)).join(' '),
            contains('mean of the two published'),
          );
        }
        await press(t);
        expect(app.writes, [
          {'sex': code},
        ]);
        expect(app.user, {'sex': code});
        expect(done, 1);
      },
    );
  }

  testWidgets(
    'profile gate waits for one accepted write and retains the draft after refusal',
    (t) async {
      app.user = {'sex': 'f', 'age': 30};
      final gate = Completer<void>();
      app.gate = gate;
      app.refuse = true;
      final units = UnitsController.withUnits();
      addTearDown(units.dispose);
      var done = 0;
      await localizedPage(
        t,
        ProfileSetupScreen(onDone: () => done++),
        app: app,
        units: units,
      );
      await t.enterText(find.byType(TextField).at(1), '173.5');
      await press(t);
      await press(t);
      expect(app.writes, hasLength(1));
      expect(done, 0);
      expect(app.user, {'sex': 'f', 'age': 30});
      gate.complete();
      await t.pumpAndSettle();
      expect(
        find.text(
          'Profile could not save. Check age, height and weight, then retry.',
        ),
        findsOneWidget,
      );
      expect(done, 0);
      expect(
        t.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '173.5',
      );
      app.refuse = false;
      app.gate = null;
      await press(t);
      expect(app.writes, hasLength(2));
      expect(app.writes[0], app.writes[1]);
      expect(app.user!['height_cm'], 173.5);
      expect(done, 1);
    },
  );
}
