// Edit profile: decimal entry in either unit system, and leaving with unsaved
// edits asks first.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _frame(Widget child) =>
    MaterialApp(theme: buildTheme(Brightness.light), home: child);

const _initial = {
  'name': 'Sahil',
  'sex': 'm',
  'age': 34,
  'height_cm': 178.0,
  'weight_kg': 72.4,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Tall enough that the whole form is laid out at once. The default 800 pt
  /// viewport leaves the button below the fold, where a `ListView` has not
  /// built it yet — and a widget that does not exist cannot be tapped, which
  /// reads as a broken button rather than as a short window.
  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(1200, 3600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_frame(child));
    await t.pumpAndSettle();
  }

  for (final units in UnitSystem.values) {
    testWidgets('decimal keyboards and unchanged profile precision in $units', (
      t,
    ) async {
      Map<String, dynamic>? saved;
      final initial = {..._initial, 'height_cm': 186.69, 'weight_kg': 80.51};
      await pump(
        t,
        EditProfileView(
          initial: initial,
          units: UnitsController.seed(units),
          onSave: (m) async {
            saved = m;
          },
        ),
      );
      final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
      expect(
        fields[2].keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      expect(
        fields[3].keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(saved!['height_cm'], 186.69);
      expect(saved!['weight_kg'], 80.51);
      if (units == UnitSystem.metric) {
        await t.enterText(
          find.byWidgetPredicate(
            (w) =>
                w is TextField && identical(w.controller, fields[3].controller),
          ),
          '80.5',
        );
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(saved!['weight_kg'], 80.5);
      }
    });
  }

  // Build 93 (Codex full-flow audit F14): a typed edit asks before leaving,
  // and Save (which closes with maybePop) is never held by that question.
  testWidgets('an edited profile asks before leaving; Save still closes', (
    t,
  ) async {
    t.view.physicalSize = const Size(1200, 3600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: Text('Settings')),
      ),
    );
    void open() => nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (c) => EditProfileView(
          initial: _initial,
          onSave: (_) async {
            if (c.mounted) await Navigator.of(c).maybePop();
          },
        ),
      ),
    );
    open();
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Synthetic');
    await t.pump();
    await nav.currentState!.maybePop();
    await t.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(EditProfileView), findsNothing);
  });
}
