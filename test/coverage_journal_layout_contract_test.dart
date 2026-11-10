// Approved complete-phone review: wrapping and viewed-date title only.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart';
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Future<void> captureDialog(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('UI_CAPTURE')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(auditCaptureKey),
  );
  boundary.markNeedsPaint();
  await t.pump();
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await Directory(
      const String.fromEnvironment(
        'UI_CAPTURE_OUTPUT_DIR',
        defaultValue: 'build/ui_capture',
      ),
    ).create(recursive: true);
    await File(
      '${dir.path}/journal_${name}_dialog.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('journal-layout-contract');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final historical in [false, true]) {
    for (final scale in [1.0, 2.0, 3.1]) {
      testWidgets(
        'phone Journal wraps and preserves ${historical ? 'historical' : 'today'} title/date at ${scale}x',
        (t) async {
          final date = historical ? '2021-04-06' : todayLabel();
          await t.runAsync(
            () => LocalDb.putJournalMetrics(date, {
              'weight_kg': const JournalMetricValue(70),
              'caffeine': const JournalMetricValue(0, atMinuteOfDay: 0),
            }),
          );
          final before = await t.runAsync(
            () async => (await LocalDb.instance).query('journal_metric'),
          );
          final app = AppState.forTesting();
          app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
          final units = UnitsController.withUnits();
          addTearDown(app.dispose);
          addTearDown(units.dispose);
          await localizedPage(
            t,
            Scaffold(body: JournalCompose(date: date)),
            app: app,
            units: units,
            scale: scale,
            settle: false,
            capture: true,
          );
          t.view.physicalSize = const Size(430, 932);
          await io(t);
          await reveal(t, find.text('Track something else'));
          expect(find.text('Track something else'), findsOneWidget);
          expect(t.takeException(), isNull);
          final tag = '${historical ? 'history' : 'today'}_${scale}x';
          await captureAuditScroll(
            t,
            tag,
            prefix: 'journal',
            scrollable: find.byType(Scrollable).first,
          );
          final enter = find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Enter weight',
          );
          await reveal(t, enter);
          await t.tap(enter);
          await t.pumpAndSettle();
          final dialog = find.byType(AlertDialog);
          expect(
            find.descendant(
              of: dialog,
              matching: find.text(historical ? 'Weight' : 'Weight today'),
            ),
            findsOneWidget,
          );
          for (final action in ['Clear', 'Cancel', 'Save']) {
            expect(
              find.descendant(of: dialog, matching: find.text(action)),
              findsOneWidget,
            );
          }
          await captureDialog(t, tag);
          await t.enterText(
            find.descendant(of: dialog, matching: find.byType(TextField)),
            '72',
          );
          await t.tap(find.widgetWithText(TextButton, 'Cancel'));
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(t.takeException(), isNull);
          final after = await t.runAsync(
            () async => (await LocalDb.instance).query('journal_metric'),
          );
          expect(after, before);
        },
      );
    }
  }
}
