// Real foreground callback/SQLite refusal, with earlier event evidence retained.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('live-event-refusal'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final table in ['events', 'band_events']) {
    test(
      'live $table refusal is reported without an escaped error, then retries without duplicates',
      () async {
        final db = await LocalDb.instance;
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        await LocalDb.insertEvent(255, 1617700000, 'aabb');
        await db.execute(
          "CREATE TRIGGER authored_live_refusal BEFORE INSERT ON $table BEGIN SELECT RAISE(ABORT, 'authored $table refusal'); END",
        );
        final escaped = <Object>[];
        try {
          await runZonedGuarded(
            () async {
              app.engine.onEvent!(254, 1617700001, 'ccdd');
              for (
                var i = 0;
                i < 50 &&
                    !app.logLines.any(
                      (l) => l.contains('[event] persistence failed'),
                    );
                i++
              ) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
            },
            (error, stack) {
              escaped.add(error);
            },
          );
          expect(escaped, isEmpty);
          expect(
            app.logLines.where((l) => l.contains('[event] persistence failed')),
            hasLength(1),
          );
          expect(app.logLines.first, contains('authored $table refusal'));
          expect(db.isOpen, true);
          for (final target in ['events', 'band_events']) {
            expect(
              (await db.query(
                target,
                where: 'hex = ?',
                whereArgs: ['aabb'],
              )).single['ts'],
              1617700000,
            );
          }
          expect(
            await db.query(
              'band_events',
              where: 'hex = ?',
              whereArgs: ['ccdd'],
            ),
            isEmpty,
          );
          expect(
            await db.query('events', where: 'hex = ?', whereArgs: ['ccdd']),
            hasLength(table == 'events' ? 0 : 1),
          );
        } finally {
          await db.execute('DROP TRIGGER authored_live_refusal');
        }
        for (var retry = 0; retry < 2; retry++) {
          app.engine.onEvent!(254, 1617700001, 'ccdd');
          for (
            var i = 0;
            i < 50 && (await db.query('band_events')).length < 2;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
        for (final target in ['events', 'band_events']) {
          final rows = await db.query(target, orderBy: 'ts');
          expect(rows.map((r) => r['hex']), ['aabb', 'ccdd']);
          expect(rows.map((r) => r['event_id']), [255, 254]);
        }
        expect(
          app.logLines.where((l) => l.contains('[event] persistence failed')),
          hasLength(1),
        );
      },
    );
  }
}
