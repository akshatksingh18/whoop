// Creating a split after a transient initial read failure
// must not replace split definitions the screen never managed to load.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/ui2/activity/lift_log_ui.dart';
import 'coverage_deep_lift_test.dart' show field, action, ioFrame;
import 'support/audit_visual.dart' show loadAuditFonts, captureAuditScroll;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var renamed = false;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('split-load-recovery');
  });
  setUp(() async {
    await resetCoverageStore();
    renamed = false;
    await LiftLogDb.saveSplits([
      LiftSplit(id: 'authored-original', name: 'Retained authored split'),
    ]);
  });
  tearDown(() async {
    if (renamed) {
      await (await LocalDb.instance).execute(
        'ALTER TABLE authored_unavailable_baselines RENAME TO baselines',
      );
    }
  });
  tearDownAll(LocalDb.close);

  for (final linked in [false, true]) {
    testWidgets(
      'new split after refused initial read preserves unviewed definitions linked=$linked',
      (t) async {
        final controller = linked
            ? LiftLogController('authored-session')
            : null;
        addTearDown(() => controller?.dispose());
        if (controller != null) await controller.load();
        final db = await LocalDb.instance;
        await db.execute(
          'ALTER TABLE baselines RENAME TO authored_unavailable_baselines',
        );
        renamed = true;
        await localizedPage(
          t,
          LiftSplitsScreen(controller: controller),
          capture: true,
        );
        await ioFrame(t);
        expect(
          find.text('Your splits could not load. Go back and try again.'),
          findsOneWidget,
        );
        await captureAuditScroll(
          t,
          'failed_read_$linked',
          prefix: 'cov48-split-load-after',
        );
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_unavailable_baselines RENAME TO baselines',
          ),
        );
        renamed = false;
        await t.tap(find.text('New split'));
        await ioFrame(t);
        await t.enterText(field('Name'), 'Second authored split');
        await t.tap(find.text('Save').last);
        await ioFrame(t);
        await captureAuditScroll(
          t,
          'saved_after_recovery_$linked',
          prefix: 'cov48-split-load-after',
        );
        final saved = (await t.runAsync(LiftLogDb.splits))!;
        expect(saved.map((s) => s.name), [
          'Retained authored split',
          'Second authored split',
        ]);
        expect(saved.first.id, 'authored-original');
      },
    );
  }
  for (final linked in [false, true]) {
    testWidgets(
      'still refused split read linked=$linked cannot open a replacement draft',
      (t) async {
        final controller = linked
            ? LiftLogController('authored-session')
            : null;
        addTearDown(() => controller?.dispose());
        if (controller != null) {
          await controller.load();
        }
        final db = await LocalDb.instance;
        final original = await db.query('baselines', orderBy: 'key');
        await db.execute(
          'ALTER TABLE baselines RENAME TO authored_unavailable_baselines',
        );
        renamed = true;
        await localizedPage(
          t,
          LiftSplitsScreen(controller: controller),
          capture: true,
        );
        await ioFrame(t);
        await t.tap(find.text('New split'));
        await ioFrame(t);
        expect(field('Name'), findsNothing);
        expect(
          find.text('Your splits could not load. Go back and try again.'),
          findsOneWidget,
        );
        expect(
          await t.runAsync(
            () => db.query('authored_unavailable_baselines', orderBy: 'key'),
          ),
          original,
        );
        await captureAuditScroll(
          t,
          'still_refused_$linked',
          prefix: 'cov48-split-load-after',
        );
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_unavailable_baselines RENAME TO baselines',
          ),
        );
        renamed = false;
        await t.tap(find.text('New split'));
        await ioFrame(t);
        await t.enterText(field('Name'), 'Cancelled draft');
        Navigator.of(t.element(field('Name'))).pop();
        await ioFrame(t);
        expect(
          (await t.runAsync(LiftLogDb.splits))!.single.id,
          'authored-original',
        );
      },
    );
    testWidgets(
      'unread refreshed split list linked=$linked rejects a stale deletion then retries',
      (t) async {
        final controller = linked
            ? LiftLogController('authored-session')
            : null;
        addTearDown(() => controller?.dispose());
        if (controller != null) {
          await controller.load();
        }
        await localizedPage(t, LiftSplitsScreen(controller: controller));
        await ioFrame(t);
        final navigator = Navigator.of(
          t.element(find.byType(LiftSplitsScreen)),
        );
        await t.tap(find.text('Retained authored split'));
        await ioFrame(t);
        final db = await LocalDb.instance;
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE baselines RENAME TO authored_unavailable_baselines',
          ),
        );
        renamed = true;
        navigator.pop();
        await ioFrame(t);
        expect(
          find.text('Your splits could not load. Go back and try again.'),
          findsOneWidget,
        );
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_unavailable_baselines RENAME TO baselines',
          ),
        );
        renamed = false;
        for (var attempt = 0; attempt < 2; attempt++) {
          await t.tap(action('Delete Retained authored split'));
          await t.pumpAndSettle();
          await t.tap(find.text('Delete').last);
          await ioFrame(t);
          final stored = (await t.runAsync(LiftLogDb.splits))!;
          if (attempt == 0) {
            expect(stored.single.id, 'authored-original');
            expect(find.text('Retained authored split'), findsOneWidget);
          } else {
            expect(stored, isEmpty);
          }
        }
      },
    );
    testWidgets(
      'recovered full split list linked=$linked keeps every definition and its limit',
      (t) async {
        final originals = [
          for (var i = 0; i < LiftSplit.maxSplits; i++)
            LiftSplit(id: 'authored-$i', name: 'Authored split $i'),
        ];
        await LiftLogDb.saveSplits(originals);
        final controller = linked
            ? LiftLogController('authored-session')
            : null;
        addTearDown(() => controller?.dispose());
        if (controller != null) {
          await controller.load();
        }
        final db = await LocalDb.instance;
        await db.execute(
          'ALTER TABLE baselines RENAME TO authored_unavailable_baselines',
        );
        renamed = true;
        await localizedPage(t, LiftSplitsScreen(controller: controller));
        await ioFrame(t);
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_unavailable_baselines RENAME TO baselines',
          ),
        );
        renamed = false;
        await t.tap(find.text('New split'));
        await ioFrame(t);
        expect(field('Name'), findsNothing);
        expect(find.text('New split'), findsNothing);
        expect(
          (await t.runAsync(LiftLogDb.splits))!.map((s) => s.id),
          originals.map((s) => s.id),
        );
      },
    );
  }
}
