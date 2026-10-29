// Non-closed SQLite errors must remain visible even on best-effort event
// ingestion. Retry preserves any first write and fills the missing mirror.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('event-write-refusal'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final refusedTable in ['events', 'band_events']) {
    test(
      'a refused $refusedTable insert is reported and retries without erasing prior event evidence',
      () async {
        final db = await LocalDb.instance;
        const ts = 1617700000;
        // Authored unsupported event bodies: insertEvent retains these verbatim
        // even when the protocol has no decoded payload for them.
        await LocalDb.insertEvent(255, ts, 'aabb');
        await db.execute(
          "CREATE TRIGGER authored_event_refusal BEFORE INSERT ON $refusedTable BEGIN SELECT RAISE(ABORT, 'authored write refusal'); END",
        );
        try {
          await expectLater(
            LocalDb.insertEvent(254, ts + 1, 'ccdd'),
            throwsA(isA<DatabaseException>()),
          );
          expect(db.isOpen, true);
          expect(
            (await db.query(
              'events',
              where: 'hex = ?',
              whereArgs: ['aabb'],
            )).single['ts'],
            ts,
          );
          expect(
            (await db.query(
              'band_events',
              where: 'hex = ?',
              whereArgs: ['aabb'],
            )).single['ts'],
            ts,
          );
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
            hasLength(refusedTable == 'events' ? 0 : 1),
          );
        } finally {
          await db.execute('DROP TRIGGER authored_event_refusal');
        }
        await LocalDb.insertEvent(254, ts + 1, 'ccdd');
        await LocalDb.insertEvent(254, ts + 1, 'ccdd');
        for (final table in ['events', 'band_events']) {
          final rows = await db.query(table, orderBy: 'ts');
          expect(rows, hasLength(2));
          expect(rows.map((r) => r['hex']), ['aabb', 'ccdd']);
          expect(rows.map((r) => r['ts']), [ts, ts + 1]);
          expect(rows.map((r) => r['event_id']), [255, 254]);
        }
      },
    );
  }
}
