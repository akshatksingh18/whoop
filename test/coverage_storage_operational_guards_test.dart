// Real SQLite operational guards, authored rows only. No destructive device IO.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as proto;
import 'coverage_ble_durable_boundary_test.dart' show record;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('storage-operational'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  test(
    'secondary offload refuses before changing primary cursors or data',
    () async {
      await LocalDb.setCursor('strap_trim', 'synthetic-primary-token');
      await expectLater(
        LocalDb.commitSyncBatch(
          [],
          [],
          deviceId: 'synthetic-secondary',
          trimToken: 'other',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('single global namespace'),
          ),
        ),
      );
      expect(await LocalDb.getCursor('strap_trim'), 'synthetic-primary-token');
      expect(await (await LocalDb.instance).query('decoded_onehz'), isEmpty);
    },
  );
  test(
    'extra cursors participate in the decoded transaction and retry atomically',
    () async {
      final db = await LocalDb.instance;
      final hex = record(
        proto.BandProfile.gen4,
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final raw = RawRecord(
        hex: hex,
        counter: 41,
        packetType: 47,
        capturedAt: 1760000001000,
        recTs: 1760000000,
      );
      final sample = proto.decodeRecord(hex);
      final row = sample == null
          ? null
          : Sample(tsEpoch: sample.ts, counter: 41, hr: sample.hr);
      await db.execute(
        "CREATE TRIGGER synthetic_extra_refusal BEFORE INSERT ON sync_cursor WHEN NEW.name='synthetic_extra' BEGIN SELECT RAISE(ABORT,'synthetic cursor refusal'); END",
      );
      try {
        await expectLater(
          LocalDb.commitSyncBatch(
            [raw],
            [row],
            trimToken: 'synthetic-token',
            extraCursors: {'synthetic_extra': 'kept'},
          ),
          throwsA(anything),
        );
        expect(await db.query('decoded_onehz'), isEmpty);
        expect(await LocalDb.getCursor('strap_trim'), isNull);
        expect(await LocalDb.getCursor('counter_hw'), isNull);
      } finally {
        await db.execute('DROP TRIGGER synthetic_extra_refusal');
      }
      await LocalDb.commitSyncBatch(
        [raw],
        [row],
        trimToken: 'synthetic-token',
        extraCursors: {'synthetic_extra': 'kept'},
      );
      expect(await LocalDb.getCursor('synthetic_extra'), 'kept');
      expect(await LocalDb.getCursor('strap_trim'), 'synthetic-token');
      expect(await db.query('decoded_onehz'), hasLength(1));
      expect(await LocalDb.recordedSecondsBetween(1760000000, 1760000001), 1);
      expect(
        await LocalDb.recordedSecondsBetween(1759999999, 1760000001),
        isNull,
      );
    },
  );
  test(
    'heavy jobs supersede queued light work while failed jobs remain diagnostic',
    () async {
      await LocalDb.enqueueDeriveJob(
        type: 'derive_light',
        reason: 'synthetic-light',
      );
      await LocalDb.enqueueDeriveJob(
        type: 'derive_heavy',
        reason: 'synthetic-heavy',
      );
      await LocalDb.enqueueDeriveJob(type: 'derive_heavy', reason: 'duplicate');
      final db = await LocalDb.instance;
      expect(await db.query('compute_jobs'), hasLength(1));
      final claimed = (await LocalDb.takeNextComputeJob())!;
      expect(claimed['type'], 'derive_heavy');
      await LocalDb.failComputeJob(
        claimed['id'] as String,
        'synthetic worker refusal',
      );
      final failed = (await db.query('compute_jobs')).single;
      expect(failed['state'], 'failed');
      expect(failed['reason'], 'synthetic worker refusal');
      expect(await LocalDb.takeNextComputeJob(), isNull);
      await LocalDb.enqueueDeriveJob(
        type: 'derive_light',
        reason: 'retry inputs',
      );
      expect((await LocalDb.takeNextComputeJob())!['type'], 'derive_light');
      expect(
        await db.query('compute_jobs', where: 'state=?', whereArgs: ['failed']),
        hasLength(1),
      );
    },
  );
  test(
    'sync health chooses the newest real computation and tolerates corrupt freshness',
    () async {
      await LocalDb.noteBackgroundWake('ble_restore');
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'capture',
        kind: 'diag',
        status: 'partial',
      );
      for (final values in [
        {'activity_computed_at': 100, 'overnight_computed_at': 200},
        {'activity_computed_at': 300, 'overnight_computed_at': 200},
        {'overnight_computed_at': 400},
      ]) {
        await LocalDb.putComputeFreshness('today', jsonEncode(values));
        final health = await LocalDb.syncHealth();
        expect(
          health.calculatedAt,
          values.values.reduce((a, b) => a > b ? a : b),
        );
        expect(health.wakeAt, isNotNull);
        expect(health.wakeSource, 'ble_restore');
        expect(health.transferAt, isNotNull);
        expect(health.transferStatus, 'partial');
      }
      await LocalDb.putComputeFreshness('today', 'broken');
      expect((await LocalDb.syncHealth()).calculatedAt, isNull);
    },
  );
  test(
    'archive thinning keeps sampled, unsampleable, recent and other-version evidence',
    () async {
      final db = await LocalDb.instance;
      final cases = [
        ('old-keep', 60, 1000, 'undecodable_rec_v20'),
        ('old-drop', 61, 1000, 'undecodable_rec_v20'),
        ('no-counter', null, 1000, 'undecodable_rec_v20'),
        ('edge', 61, 2000, 'undecodable_rec_v20'),
        ('other-version', 61, 1000, 'undecodable_rec_v25'),
      ];
      for (final c in cases) {
        await db.insert('raw_archive', {
          'hex': c.$1,
          'counter': c.$2,
          'captured_at': c.$3,
          'packet_type': 47,
          'reason': c.$4,
        });
      }
      expect(await LocalDb.thinRawArchiveBefore(2000), 1);
      expect(
        (await db.query('raw_archive')).map((r) => r['hex']),
        unorderedEquals(['old-keep', 'no-counter', 'edge', 'other-version']),
      );
      expect(await LocalDb.thinRawArchiveBefore(2000), 0);
    },
  );
  test(
    'vacuum threshold leaves live rows readable and empty export is refused',
    () async {
      final db = await LocalDb.instance;
      await LocalDb.setCursor('synthetic_saved', 'kept');
      expect(await LocalDb.freelistBytes(), greaterThanOrEqualTo(0));
      expect(await LocalDb.vacuumIfBloated(minFreeBytes: 1 << 30), 0);
      expect(
        await LocalDb.vacuumIfBloated(minFreeBytes: 0),
        greaterThanOrEqualTo(0),
      );
      expect(await LocalDb.getCursor('synthetic_saved'), 'kept');
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      await expectLater(LocalDb.exportDaysDb({}), throwsArgumentError);
    },
  );
}
