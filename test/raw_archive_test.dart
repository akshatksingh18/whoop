// Firmware-resilience: undecodable historical records must be ARCHIVED durably
// (never pruned) in the SAME transaction as the raw records + trim cursor, so
// they are set aside BEFORE the caller writes the batch-ACK that lets the band
// trim its flash (safe-trim invariant). Runs the REAL LocalDb over an in-memory
// sqlite via sqflite_common_ffi.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_archive_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('commitSyncBatch co-commits archive + raw + trim cursor atomically', () async {
    final raw = RawRecord(
      counter: 1001,
      packetType: 0x2F,
      hex: '2f18aabbccdd',
      capturedAt: 1750000000000,
      recTs: 1750000000,
    );
    // Fully-decoded sample rides the batch (the durable substrate is the
    // decoded store; commitSyncBatch persists decoded rows, not raw hex).
    final sample = Sample(
      tsEpoch: 1750000000,
      counter: 1001,
      hr: 62,
      ax: 0.1,
      ay: 0.2,
      az: 0.9,
      spo2RedRaw: 100,
      spo2IrRaw: 200,
      skinTempRaw: 300,
    );
    final archive = ArchiveRecord(
      counter: 2002,
      hex: '2f63deadbeef', // an unknown record version
      packetType: 0x2F,
      capturedAt: 1750000000500,
      reason: 'undecodable_rec_v99',
    );

    await LocalDb.commitSyncBatch(
      [raw],
      <Sample?>[sample],
      trimToken: 'aabbccddeeff0011',
      archives: [archive],
    );

    // Archive landed (durable, keyed by counter with reason breakdown).
    final stats = await LocalDb.rawArchiveStats();
    expect(stats['count'], 1);
    expect((stats['by_reason'] as Map)['undecodable_rec_v99'], 1);

    // Decoded record landed in the SAME commit.
    final counts = await LocalDb.counts();
    expect((counts['decoded_onehz'] ?? 0) >= 1, isTrue);

    // Trim cursor advanced in the SAME commit (what the ACK echoes verbatim).
    expect(await LocalDb.getCursor('strap_trim'), 'aabbccddeeff0011');
    expect(await LocalDb.getCursorInt('counter_hw'), 1001);
  });

  test('identical re-flood dedups on frame hex (missed-ACK redelivery)', () async {
    final archive = ArchiveRecord(
      counter: 2002, // same counter AND same bytes as above
      hex: '2f63deadbeef',
      packetType: 0x2F,
      capturedAt: 1750000099999,
      reason: 'undecodable_rec_v99',
    );
    await LocalDb.commitSyncBatch(
      const <RawRecord>[],
      const <Sample?>[],
      trimToken: 'aabbccddeeff0022',
      archives: [archive],
    );
    // Still one archived row — same bytes, so the redelivery deduped.
    final stats = await LocalDb.rawArchiveStats();
    expect(stats['count'], 1);
    // …but the trim cursor still advanced (this chunk was ACK-safe).
    expect(await LocalDb.getCursor('strap_trim'), 'aabbccddeeff0022');
  });

  test('archiveRawRecord fallback path also persists', () async {
    await LocalDb.archiveRawRecord(ArchiveRecord(
      counter: 3003,
      hex: '2f70cafebabe',
      packetType: 0x2F,
      capturedAt: 1750000100000,
      reason: 'undecodable_rec_v112',
    ));
    final stats = await LocalDb.rawArchiveStats();
    expect(stats['count'], 2);
    expect((stats['by_reason'] as Map)['undecodable_rec_v112'], 1);
  });

  test('two DISTINCT frames sharing a reused counter BOTH survive', () async {
    // The strap resets its record counter to ~0 on reboot, so a post-reboot
    // frame can reuse a pre-reboot counter while carrying different bytes.
    // Under the old `counter INTEGER PRIMARY KEY` + IGNORE, the second frame
    // was silently DROPPED — permanent loss in the table that exists precisely
    // to never lose a frame. Content-keyed, both must survive.
    final before = (await LocalDb.rawArchiveStats())['count'] as int;
    const reusedCounter = 4004;
    await LocalDb.archiveRawRecord(ArchiveRecord(
      counter: reusedCounter,
      hex: '2f63aaaaaaaa', // pre-reboot frame
      packetType: 0x2F,
      capturedAt: 1750000200000,
      reason: 'undecodable_pre_reboot',
    ));
    await LocalDb.archiveRawRecord(ArchiveRecord(
      counter: reusedCounter, // SAME counter, DIFFERENT bytes
      hex: '2f63bbbbbbbb', // post-reboot frame
      packetType: 0x2F,
      capturedAt: 1750000300000,
      reason: 'undecodable_post_reboot',
    ));
    final after = (await LocalDb.rawArchiveStats())['count'] as int;
    // Pre-fix: +1 (second dropped by counter-PK IGNORE). Post-fix: +2.
    expect(after - before, 2);
  });
}
