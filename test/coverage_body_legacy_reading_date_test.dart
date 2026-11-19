// Older weight exports can supply the civil date without a reliable clock.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/progress_routes.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';

import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-legacy-reading-date', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final hasClock in [false, true]) {
    testWidgets(
      'restored legacy weigh-in with clock $hasClock retains its original date and value',
      (t) async {
        const day = '2021-04-06';
        final clock = DateTime(2021, 4, 6, 9, 15);
        final timestamp = hasClock ? clock.millisecondsSinceEpoch ~/ 1000 : 0;
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        final units = UnitsController.seed(UnitSystem.metric);
        addTearDown(app.dispose);
        addTearDown(units.dispose);
        final (source, bytes) = (await t.runAsync(() async {
          final dir = await File(LocalDb.dbName).parent.createTemp('authored-');
          final file = File('${dir.path}/legacy.db');
          final old = await openDatabase(file.path);
          try {
            await old.execute(
              'CREATE TABLE body_weight (date TEXT PRIMARY KEY, kg REAL NOT NULL, at_ts INTEGER NOT NULL)',
            );
            await old.insert('body_weight', {
              'date': day,
              'kg': 72.0,
              'at_ts': timestamp,
            });
          } finally {
            await old.close();
          }
          final bytes = await file.readAsBytes();
          await LocalDb.importFromDbFile(file.path);
          await LocalDb.importFromDbFile(file.path);
          return (file, bytes);
        }))!;
        final stored = (await t.runAsync(
          () => BodyLogDb.readingsOn(day),
        ))!.single;
        expect(stored.date, day);
        expect(stored.atTs, timestamp);
        expect(stored.kg, 72);

        await localizedPage(
          t,
          progressDetailPage(ProgressDest.weight, range: ProgressRange.all),
          app: app,
          units: units,
          settle: false,
        );
        await flush(t);
        final label = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label?.startsWith('Latest reading:') ?? false),
        );
        await reveal(t, label);
        final labels = t
            .widgetList<Text>(
              find.descendant(of: label, matching: find.byType(Text)),
            )
            .map((item) => item.data ?? '')
            .where((text) => text.startsWith('Apr 6'));
        if (hasClock) {
          expect(
            labels.any(
              (text) => text.startsWith('Apr 6,') && text.contains('9:15'),
            ),
            isTrue,
          );
        } else {
          expect(labels.single, 'Apr 6, 2021');
        }
        expect(
          (await t.runAsync(() => BodyLogDb.readingsOn(day)))!.single,
          stored,
        );
        expect(await t.runAsync(source.readAsBytes), bytes);
      },
    );
  }
}
