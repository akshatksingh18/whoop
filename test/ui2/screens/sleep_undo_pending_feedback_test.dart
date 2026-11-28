// Held correction IPC at the existing UI boundary;no calculation is substituted as measured data.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'sleep_localized_corrections_test.dart' show App, Reader, day;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

class _HeldApp extends App {
  _HeldApp(super.reader);
  Completer<void> release = Completer<void>();
  int entered = 0;
  @override
  Future<void> clearSleepOverride(String date) async {
    entered++;
    await release.future;
    return super.clearSleepOverride(date);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('sleep-undo-pending-feedback');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final refused in [false, true]) {
      testWidgets(
        'rejected-night Undo pending/refusal=$refused keeps one request and recovery actions at ${scale}x',
        (t) async {
          final reader = Reader()..night = {'sleep_source': 'rejected'};
          final app = _HeldApp(reader)..refuse = refused;
          final theme = ThemeController.seed(
            AppThemeChoice.light,
            Brightness.light,
          );
          addTearDown(() {
            if (!app.release.isCompleted) app.release.complete();
            app.dispose();
            theme.dispose();
          });
          final db = await LocalDb.instance;
          await MetricSeriesStore.putValue(day, 'steps', 1234);
          final before = await db.query('metric_series');
          await localizedPage(
            t,
            const SleepDetail(day: day),
            app: app,
            themeController: theme,
            scale: scale,
          );
          final undo = find.widgetWithText(
            TextButton,
            'Undo — go back to automatic',
          );
          await reveal(t, undo);
          await t.tap(undo);
          await t.pumpAndSettle();
          expect(app.entered, 1);
          expect(t.widget<TextButton>(undo).onPressed, isNull);
          expect(find.text('Re-analysing the night…'), findsOneWidget);
          expect(find.text('Marked as not sleep'), findsOneWidget);
          expect(find.text('Breathing pattern in sleep'), findsOneWidget);
          expect(app.calls, isEmpty);
          app.release.complete();
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await t.pumpAndSettle();
          if (refused) {
            expect(find.text('Nothing was saved. Try again.'), findsOneWidget);
            expect(t.widget<TextButton>(undo).onPressed, isNotNull);
            app.refuse = false;
            app.release = Completer<void>();
            await t.tap(undo);
            await t.pumpAndSettle();
            expect(t.widget<TextButton>(undo).onPressed, isNull);
            expect(app.entered, 2);
            app.release.complete();
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await t.pumpAndSettle();
          }
          expect(find.text('No night to show'), findsOneWidget);
          expect(find.text('Re-analysing the night…'), findsNothing);
          expect(find.text('Breathing pattern in sleep'), findsOneWidget);
          expect(app.calls, List.filled(refused ? 2 : 1, 'clear:$day'));
          expect(await t.runAsync(() => db.query('metric_series')), before);
          expect(await t.runAsync(() => db.query('sleep_override')), isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
