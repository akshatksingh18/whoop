// The Today row and the recovery notice both open their normal user surfaces.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'coverage_session_destination_boundaries_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('today-body-recovery-navigation', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final recorded in [false, true]) {
    testWidgets(
      'Today Body row opens history with a weight present $recorded',
      (t) async {
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        final day = todayLabel();
        if (recorded) await BodyLogDb.putWeight(day, 71, 'kg');
        await localizedPage(t, const Scaffold(body: TodayBodyRow()), app: app);
        await io(t);
        final label = find.text(recorded ? 'Weighed in' : 'Weigh in').first;
        final before = await t.runAsync(BodyLogDb.weights);
        final routeOpener = t.state(find.byType(TodayBodyRow));
        await t.tap(label);
        await io(t);
        expect(find.widgetWithText(NavBar, 'Body'), findsOneWidget);
        expect(find.byType(BodyEntryScreen), findsNothing);
        expect(find.text('Weight'), findsWidgets);
        await t.tap(
          find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Back',
          ),
        );
        await io(t);
        expect(t.state(find.byType(TodayBodyRow)), same(routeOpener));
        expect(label, findsOneWidget);
        expect(await t.runAsync(BodyLogDb.weights), before);
      },
    );
  }

  testWidgets('actual SQLite quarantine stays linked from Home and Your data', (
    t,
  ) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final bytes = List<int>.generate(8192, (i) => (i * 37 + 11) & 255);
    await t.runAsync(() async {
      await LocalDb.close();
      await File(LocalDb.dbName).writeAsBytes(bytes, flush: true);
      await LocalDb.instance;
    });
    addTearDown(() => LocalDb.lastRebuild = null);
    final receipt = app.dbRebuild!;
    final quarantine = File(receipt.quarantinePath);
    expect(await t.runAsync(quarantine.readAsBytes), bytes);
    expect(receipt.salvaged.values.where((n) => n > 0), isEmpty);

    const openData = 'Open Your data test page';
    await localizedPage(
      t,
      Scaffold(
        body: const HomeScreen(data: HomeData()),
        floatingActionButton: Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.of(
              c,
            ).push<void>(MaterialPageRoute(builder: (_) => const DataScreen())),
            child: const Text(openData),
          ),
        ),
      ),
      app: app,
    );
    final warning = find.byWidgetPredicate(
      (w) =>
          w is StatusCard &&
          w.what == 'Your database was rebuilt to start the app',
    );
    void verifyNotice() {
      expect(warning, findsOneWidget);
      final card = t.widget<StatusCard>(warning);
      expect(card.why, contains('Nothing could be read back.'));
      expect(card.why, contains(receipt.quarantinePath));
    }

    verifyNotice();
    await t.tap(find.text(openData));
    await io(t);
    verifyNotice();
    final import = find.widgetWithText(SetRow, 'Import a file');
    await reveal(t, import);
    expect(t.widget<SetRow>(import).onTap, isNotNull);
    expect(await t.runAsync(quarantine.readAsBytes), bytes);
    expect(await t.runAsync(LocalDb.schemaHealth), containsPair('ok', true));
    expect(t.takeException(), isNull);
  });
}
