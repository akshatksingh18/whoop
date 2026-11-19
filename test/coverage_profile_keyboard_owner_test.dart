// IME Done closes the keyboard. Profile data only changes on explicit Save.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/profile/settings.dart';

import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

void main() {
  setUpAll(loadAuditFonts);
  for (final (scale, weightUnit) in [(1.0, 'kg'), (3.1, 'lb')]) {
    testWidgets('profile Done retains the pending age at scale $scale', (
      t,
    ) async {
      final units = UnitsController.withUnits(weight: weightUnit);
      addTearDown(units.dispose);
      final writes = <Map<String, dynamic>>[];
      final original = {
        'name': 'Authored profile',
        'sex': 'f',
        'age': 30,
        'height_cm': 170.0,
        'weight_kg': 72.34,
      };
      await localizedPage(
        t,
        EditProfileView(
          initial: original,
          units: units,
          onSave: (value) async => writes.add(Map.of(value)),
        ),
        scale: scale,
      );
      final ageController = t
          .widgetList<TextField>(find.byType(TextField))
          .singleWhere((field) => field.controller?.text == '30')
          .controller;
      final age = find.byWidgetPredicate(
        (w) => w is TextField && identical(w.controller, ageController),
      );
      await reveal(t, age);
      await t.enterText(age, '34');
      final editing = find.descendant(
        of: age,
        matching: find.byType(EditableText),
      );
      expect(t.widget<EditableText>(editing).focusNode.hasFocus, isTrue);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(t.widget<EditableText>(editing).focusNode.hasFocus, isFalse);
      expect(t.widget<TextField>(age).controller!.text, '34');
      expect(writes, isEmpty);

      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(writes, [
        {...original, 'age': 34},
      ]);
      expect(original['age'], 30);
      expect(t.takeException(), isNull);
    });
  }
}
