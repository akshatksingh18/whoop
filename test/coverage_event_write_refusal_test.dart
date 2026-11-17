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
  for (final kind in ['event', 'battery', 'claim']) {
    test(
      'COV-48 a real SQLite close racing $kind reopens once without losing evidence',
      () async {
        const ts = 1617700000;
        await LocalDb.insertEvent(255, ts, 'aabb');
        await LocalDb.insertBandBatterySample(
          ts: ts,
          batteryPct: 80,
          millivolts: 4100,
          source: 'authored',
        );
        expect(
          await LocalDb.claimNotifFired('authored-old', firedAtMs: ts * 1000),
          true,
        );
        final old = await LocalDb.instance;
        final pending = switch (kind) {
          'event' => LocalDb.insertEvent(
            254,
            ts + 1,
            'ccdd',
          ).then<Object?>((_) => null),
          'battery' => LocalDb.insertBandBatterySample(
            ts: ts + 1,
            batteryPct: 79,
            millivolts: 4090,
            source: 'authored',
          ).then<Object?>((_) => null),
          _ => LocalDb.claimNotifFired(
            'authored-new',
            firedAtMs: (ts + 1) * 1000,
          ),
        };
        // The guarded write has requested its real cached handle. Close it in
        // the same event-loop turn, before its awaited insert/transaction begins.
        await old.close();
        final result = await pending;
        expect(old.isOpen, false);
        final db = await LocalDb.instance;
        expect(identical(old, db), false);
        expect(db.isOpen, true);
        for (final table in ['events', 'band_events']) {
          final events = await db.query(table, orderBy: 'ts');
          expect(
            events.map((e) => e['hex']),
            kind == 'event' ? ['aabb', 'ccdd'] : ['aabb'],
          );
        }
        final batteries = await db.query('band_battery', orderBy: 'ts');
        expect(
          batteries.map((e) => e['battery_pct']),
          kind == 'battery' ? [80.0, 79.0] : [80.0],
        );
        expect(batteries.first['millivolts'], 4100);
        expect(await LocalDb.notifFiredExists('authored-old'), true);
        if (kind == 'claim') {
          expect(result, true);
          expect(await LocalDb.claimNotifFired('authored-new'), false);
          final rows = await db.query('notif_fired', orderBy: 'fired_at');
          expect(rows.map((r) => r['key']), ['authored-old', 'authored-new']);
          expect(rows.last['fired_at'], (ts + 1) * 1000);
        } else {
          expect(await LocalDb.notifFiredExists('authored-new'), false);
        }
      },
    );
  }
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
