// Approved name-dialog B: actual field copy, actions and layout; mock radio only.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'coverage_device_controls_test.dart' show DeviceApp, source;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeviceApp app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('name-guidance-layout');
  });
  setUp(() async {
    await resetCoverageStore();
    app = DeviceApp();
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);

  Finder field() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );
  Future<void> reopen(WidgetTester t) async {
    final row = find.byWidgetPredicate((w) => w is SetRow && w.title == 'Name');
    await reveal(t, row);
    await t.tap(row);
    await t.pumpAndSettle();
    expect(find.text('Name this band'), findsOneWidget);
    expect(field(), findsOneWidget);
    expect(t.widget<TextField>(field()).maxLength, 20);
  }

  Future<void> open(WidgetTester t, double width, double scale) async {
    await localizedPage(t, const DeviceDetail(source), app: app, scale: scale);
    t.view.physicalSize = Size(width, 932);
    await t.pumpAndSettle();
    await reopen(t);
  }

  void readable(WidgetTester t, {bool error = false}) {
    final decoration = t.widget<TextField>(field()).decoration!;
    final text = error ? decoration.errorText! : decoration.helperText!;
    expect(text, isNotEmpty);
    final copy = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );
    expect(copy, findsOneWidget);
    expect(
      t.renderObject<RenderParagraph>(copy).didExceedMaxLines,
      false,
      reason: 'the entire guidance or error must be readable',
    );
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);
  }

  Future<void> tap(WidgetTester t, String label) async {
    await t.tap(find.widgetWithText(TextButton, label));
    await t.pumpAndSettle();
  }

  Future<void> restoreKeyboard(WidgetTester t) async {
    t.view.viewInsets = FakeViewPadding();
    await t.pumpAndSettle();
  }

  for (final (width, scale, keyboard) in [
    (390.0, 1.0, 0.0),
    (320.0, 2.0, 0.0),
    (430.0, 3.1, 0.0),
    (390.0, 2.0, 300.0),
  ]) {
    for (final error in [false, true]) {
      testWidgets(
        'COV-48 name dialog ${error ? 'error' : 'helper'} at ${width.toInt()} ${scale}x keyboard$keyboard',
        (t) async {
          await open(t, width, scale);
          final initial = t.widget<TextField>(field()).controller!.text;
          if (keyboard > 0) {
            t.view.viewInsets = FakeViewPadding(bottom: keyboard);
            await t.pumpAndSettle();
          }
          if (error) {
            await t.enterText(field(), '*');
            await tap(t, 'Save');
            expect(app.names, isEmpty);
            readable(t, error: true);
            expect(t.widget<TextField>(field()).controller!.text, '*');
            await t.enterText(field(), '');
            await tap(t, 'Save');
            readable(t, error: true);
            expect(find.text('Give it a name'), findsOneWidget);
            expect(app.names, isEmpty);
            await t.enterText(field(), '  Studio band  ');
            await tap(t, 'Save');
            expect(find.byType(AlertDialog), findsNothing);
            expect(app.names, ['Studio band']);
            expect(find.text('Renamed to Studio band'), findsOneWidget);
          } else {
            readable(t);
            await t.enterText(field(), 'Unsent draft');
            await tap(t, 'Cancel');
            expect(find.byType(AlertDialog), findsNothing);
            expect(app.names, isEmpty);
            await restoreKeyboard(t);
            await reopen(t);
            expect(t.widget<TextField>(field()).controller!.text, initial);
            readable(t);
            await tap(t, 'Cancel');
          }
          await restoreKeyboard(t);
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'COV-48 name dialog B gives enlarged text more usable width',
    (t) async {
      Future<Rect> surface(double scale) async {
        await open(t, 390, scale);
        readable(t);
        final card = find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first;
        final result = t.getRect(card);
        await tap(t, 'Cancel');
        expect(app.names, isEmpty);
        return result;
      }

      final ordinary = await surface(1.3);
      await surface(1.31); // Intrinsic content need not fill all available width.
      final larger = await surface(2.0);
      expect(larger.width, greaterThan(ordinary.width));
      expect(larger.left, lessThan(ordinary.left));
    },
  );

  testWidgets(
    'COV-48 name dialog B keeps a refused command honest and permits explicit reopen retry',
    (t) async {
      await open(t, 430, 3.1);
      readable(t);
      app.refuse = true;
      await t.enterText(field(), 'Studio band');
      await tap(t, 'Save');
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.names, ['Studio band']);
      expect(find.textContaining('Could not rename the band:'), findsOneWidget);
      app.refuse = false;
      await reopen(t);
      readable(t);
      await t.enterText(field(), 'Studio band');
      await tap(t, 'Save');
      expect(app.names, ['Studio band', 'Studio band']);
      // The failure caption is still on screen; the success caption queues
      // behind its normal Material lifetime. Exercise both messages in order.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text('Renamed to Studio band'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
