// Authored profile drafts: validation, metric precision and retry under shipped copy.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/profile/settings.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

void main() {
  setUpAll(loadAuditFonts);
  const initial = {
    'name': 'Synthetic',
    'sex': 'f',
    'age': 30,
    'height_cm': 170.123,
    'weight_kg': 70.123,
  };
  Future<void> save(WidgetTester t) async => invokeControl(
    t,
    t
        .widget<Pressable>(
          find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Save',
          ),
        )
        .onTap,
  );
  for (final imperial in [false, true]) {
    testWidgets(
      'COV-44 profile unchanged display retains exact metric precision $imperial',
      (t) async {
        Map<String, dynamic>? out;
        await localizedPage(
          t,
          EditProfileView(
            initial: initial,
            units: UnitsController.withUnits(
              weight: imperial ? 'lb' : 'kg',
              height: imperial ? HeightUnit.ftIn : HeightUnit.cm,
            ),
            onSave: (v) async => out = v,
          ),
        );
        await save(t);
        expect(out, initial);
      },
    );
  }
  for (final bad in [
    (1, 'bad'),
    (1, '0'),
    (1, '121'),
    (1, '30.5'),
    (2, '29'),
    (2, '281'),
    (3, '0'),
    (3, '501'),
    (3, '70 kg'),
  ]) {
    testWidgets(
      'COV-44 invalid profile field ${bad.$1}:${bad.$2} cannot clear stored values',
      (t) async {
        var calls = 0;
        await localizedPage(
          t,
          EditProfileView(initial: initial, onSave: (v) async => calls++),
        );
        await t.enterText(find.byType(TextField).at(bad.$1), bad.$2);
        await save(t);
        expect(calls, 0);
        expect(
          t
              .widget<TextField>(find.byType(TextField).at(bad.$1))
              .controller!
              .text,
          bad.$2,
        );
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );
  }
  testWidgets(
    'COV-44 cleared profile fields are explicit nulls and sex choice is authoritative',
    (t) async {
      Map<String, dynamic>? out;
      await localizedPage(
        t,
        EditProfileView(initial: initial, onSave: (v) async => out = v),
      );
      for (var i = 0; i < 4; i++) {
        await t.enterText(find.byType(TextField).at(i), ' ');
      }
      await t.tap(find.text('Male'));
      await t.pumpAndSettle();
      await save(t);
      expect(out, {
        'name': null,
        'sex': 'm',
        'age': null,
        'height_cm': null,
        'weight_kg': null,
      });
    },
  );
  testWidgets(
    'COV-44 refused profile save keeps draft and retries once without loss',
    (t) async {
      var calls = 0;
      Map<String, dynamic>? out;
      await localizedPage(
        t,
        EditProfileView(
          initial: initial,
          onSave: (v) async {
            calls++;
            if (calls == 1) throw StateError('synthetic refusal');
            out = v;
          },
        ),
      );
      await t.enterText(find.byType(TextField).at(0), ' Edited synthetic ');
      await t.enterText(find.byType(TextField).at(2), '172');
      await t.enterText(find.byType(TextField).at(3), '71.25');
      await save(t);
      expect(calls, 1);
      expect(
        find.text('Profile could not save. Please retry.'),
        findsOneWidget,
      );
      await save(t);
      expect(calls, 2);
      expect(out!['name'], 'Edited synthetic');
      expect(out!['height_cm'], 172);
      expect(out!['weight_kg'], 71.25);
    },
  );
}
