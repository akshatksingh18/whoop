// Retained gallery controls and real preview routes. Authored previews never
// become saved workouts or sensor rows; no peripheral/share screen is opened.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/activity/picker.dart';
import 'package:whoop_companion/ui2/activity/setup.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/profile/gallery.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('gallery-owned-controls');
  });
  setUp(() async {
    await resetCoverageStore();
    LiveDraft.clear();
    await LiveDraft.retrySave();
  });
  tearDown(() async {
    LiveDraft.clear();
    await LiveDraft.retrySave();
  });
  tearDownAll(LocalDb.close);
  testWidgets(
    'component text scale and palette change the preview while its controls remain usable at the app scale',
    (t) async {
      await localizedPage(t, const GalleryScreen());
      await t.tap(find.text('Components'));
      await t.pumpAndSettle();
      expect(find.text('Food details'), findsOneWidget);
      for (final (label, scale) in [
        ('1.4×', 1.4),
        ('2.0×', 2.0),
        ('3.1×', 3.1),
        ('1.0×', 1.0),
      ]) {
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        final content = t.element(find.text('Food details'));
        expect(
          MediaQuery.textScalerOf(content).scale(10),
          closeTo(scale * 10, 1e-9),
        );
        expect(
          MediaQuery.textScalerOf(t.element(find.text(label))).scale(10),
          10,
        );
      }
      for (final (label, brightness) in [
        ('Dark', Brightness.dark),
        ('Light', Brightness.light),
        ('System', Brightness.light),
      ]) {
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        expect(
          Theme.of(t.element(find.text('Food details'))).brightness,
          brightness,
        );
      }
      await t.tap(find.text('Flows'));
      await t.pumpAndSettle();
      expect(find.text('Running'), findsWidgets);
      expect(find.text('Food details'), findsNothing);
    },
  );
  for (final activity in ['Running', 'Rowing']) {
    testWidgets(
      '$activity preview opens each real stage with a disclosure and banks no invented session',
      (t) async {
        await localizedPage(t, const GalleryScreen());
        Finder row(String title) =>
            find.byWidgetPredicate((w) => w is SetRow && w.title == title);
        await reveal(t, row(activity));
        await t.tap(row(activity));
        await t.pumpAndSettle();
        expect(
          find.text(
            activity == 'Running'
                ? 'A hand-written fixture'
                : 'These numbers are invented',
          ),
          findsOneWidget,
        );
        for (final (label, type) in [
          ('Pick', ActivityPicker),
          ('Set up', ActivitySetup),
          ('Live', LiveShell),
          ('Summary', ActivitySummary),
        ]) {
          await reveal(t, row(label));
          await t.tap(row(label));
          await t.pumpAndSettle();
          expect(find.byType(type), findsOneWidget);
          final db = (await t.runAsync(() => LocalDb.instance))!;
          expect(await t.runAsync(() => db.query('sessions')), isEmpty);
          expect(await t.runAsync(() => db.query('decoded_onehz')), isEmpty);
          Navigator.of(t.element(find.byType(type))).pop();
          await t.pumpAndSettle();
          expect(row('Summary'), findsOneWidget);
        }
        Navigator.of(t.element(row('Summary'))).pop();
        await t.pumpAndSettle();
        expect(find.byType(GalleryScreen), findsOneWidget);
        expect(row(activity), findsOneWidget);
      },
    );
  }
}
