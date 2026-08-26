// THE INVARIANT the `source` column exists to have.
//
// A row in `decoded_onehz` / `decoded_rr` may become a NUMBER only if its
// source is admitted: NULL (the primary band) or one of `kDerivableSources`
// (an adapter the owner has personally confirmed — ASSUMPTIONS R6/E5). An
// unverified adapter's seconds bank, sync, back up and appear in diagnostics,
// and produce no metric at all.
//
// Same failure shape as `observation_isolation_test.dart`, and that file is the
// worked example this one copies: a violation here is SILENT. Nothing throws,
// no row looks wrong, a session HR just quietly becomes the average of a chest
// electrode and a wrist LED — a number that is neither sensor's, inside a
// long-horizon baseline, months before anyone notices.
//
// Three layers:
//
//  1. STRUCTURAL — nobody may hand-write the predicate. Every reader goes
//     through `derivableSourceSql()` or `kPrimaryBandSourceSql`, because the
//     two are byte-identical today and are NOT the same question. This is the
//     layer that catches the realistic violation: a new decoded read added six
//     months from now, copied from the one next to it.
//  2. DIFFERENTIAL — real unverified rows are written at the SAME seconds as
//     band rows with absurd values, and every admission read must come back
//     byte-identical. This is the layer that catches a reader that forgot the
//     gate entirely, which layer 1 cannot see.
//  3. THE MECHANISM ITSELF — that an empty admitted set really does render the
//     old predicate (which is what makes this whole change a no-op today), and
//     that a non-empty one really does widen it (which is what makes it worth
//     having).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// The ONLY places the predicate may be written out by hand.
///
/// `db.dart` defines both fragments; `health_export.dart` names
/// `kPrimaryBandSourceSql` in prose because its comment argues, at length, why
/// it is deliberately the narrow one. Adding a file here is the deliberate act
/// the invariant asks for — and if you are adding one because you wrote a new
/// decoded read, you wanted `derivableSourceSql()` instead.
const _mayWriteThePredicate = {
  'lib/data/db.dart',
  'lib/health/health_export.dart',
};

/// A hand-written admission predicate against the decoded store.
final _handWritten = RegExp(r'source\s+IS\s+(NOT\s+)?NULL', caseSensitive: false);

/// A line that is nothing but a comment cannot reach a table.
final _pureComment = RegExp(r'^\s*(///|//|\*|/\*)');

Sample _band(int ts, int counter) => Sample(
  tsEpoch: ts,
  counter: counter,
  hr: 60,
  rrIntervalsMs: const [1000],
  ax: 0.0,
  ay: 0.0,
  az: 1.0,
  spo2RedRaw: 1,
  spo2IrRaw: 2,
  skinTempRaw: 3,
);

RawRecord _raw(int ts, int counter) => RawRecord(
  counter: counter,
  packetType: 47,
  hex: 'beef$counter',
  capturedAt: ts * 1000,
  recTs: ts,
);

/// One second measured by an adapter nobody has verified, at a second the band
/// also measured, with values no real reader could absorb quietly: 199 bpm
/// against the band's 60, and a 400 ms beat against its 1000 ms.
Future<void> _poison(int ts, int counter) async {
  final db = await LocalDb.instance;
  await db.insert('decoded_onehz', {
    'device_id': 'unverified_unit_1',
    'ts_ms': ts * 1000,
    'rec_ts': ts,
    'counter': counter,
    'hr': 199,
    'ax': 0.0,
    'ay': 0.0,
    'az': 1.0,
    'source': 'unverified_test_adapter',
  });
  await db.insert('decoded_rr', {
    'device_id': 'unverified_unit_1',
    'ts_ms': ts * 1000,
    'rec_ts': ts,
    'beat_index': 0,
    'rr_ts_ms': ts * 1000,
    'rr_ms': 400,
    'source': 'unverified_test_adapter',
  });
}

/// Every read whose rows are allowed to become a number, plus the two that mean
/// the primary band specifically — both must be unmoved, for different reasons.
/// Rendered to one string so a difference of any kind fails.
Future<String> _everyAdmissionRead(int lo, int hi) async {
  final out = StringBuffer();
  out.writeln('span=${await LocalDb.firstAndLastRecordTs()}');
  out.writeln('byDay=${await LocalDb.decodedRecTsMaxByDay()}');
  out.writeln(
    'batch=${await LocalDb.decodedOneHzBatchByRecTsRange(limit: 100, fromRecTs: lo, toRecTs: hi)}',
  );
  // The keyset-cursor branch is a SECOND copy of the predicate in the same
  // method, so it gets its own line.
  out.writeln(
    'batchAfter=${await LocalDb.decodedOneHzBatchByRecTsRange(limit: 100, fromRecTs: lo, toRecTs: hi, afterRecTs: lo, afterCounter: 0)}',
  );
  out.writeln(
    'rr=${await LocalDb.decodedRrByRecTsRange(fromRecTs: lo, toRecTs: hi)}',
  );
  out.writeln('history=${await LocalDb.dataHistoryDays()}');
  // Sample has no value-bearing toString, so render the two fields the poison
  // rows would move.
  out.writeln(
    'samples=${(await LocalDb.samplesInRange(lo, hi)).map((s) => '${s.tsEpoch}:${s.hr}').toList()}',
  );
  out.writeln('latest=${(await LocalDb.latestSample())?.hr}');
  out.writeln('hr=${await LocalDb.hrSamplesInRange(lo, hi)}');
  out.writeln('sessionStats=${await LocalDb.sessionHrStats(lo, hi)}');
  out.writeln('sessionHr=${await LocalDb.sessionHrSamplesBySession(lo, hi)}');
  out.writeln('dataEdge=${await LocalDb.lastDecodedRecTs()}');
  return out.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── LAYER 1 — structural ───────────────────────────────────────────────────
  test('nobody hand-writes the admission predicate', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final rel = p.relative(f.path);
      if (_mayWriteThePredicate.contains(rel)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_pureComment.hasMatch(lines[i])) continue;
        if (_handWritten.hasMatch(lines[i])) offenders.add('$rel:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'These write the admission predicate by hand. Use derivableSourceSql() '
          '(may this row become a number?) or kPrimaryBandSourceSql (is this the '
          'primary band specifically?). They render the same SQL today and they '
          'answer different questions, which is exactly why neither may be a '
          'literal: $offenders',
    );
  });

  test('the scanner would actually catch a violation', () {
    expect(_handWritten.hasMatch("'WHERE hr > 0 AND source IS NULL'"), isTrue);
    expect(_handWritten.hasMatch("'AND d.source IS NOT NULL'"), isTrue);
    expect(_pureComment.hasMatch('  // source IS NULL — the band'), isTrue);
    expect(_handWritten.hasMatch(r"'AND ${derivableSourceSql()}'"), isFalse);
  });

  test('both fragments really are named in the two files that may', () {
    expect(
      File('lib/health/health_export.dart').readAsStringSync(),
      contains(r'$kPrimaryBandSourceSql'),
      reason:
          'The HealthKit / Health Connect HR export is deliberately the NARROW '
          'predicate: a sample written into a system store carries no source '
          'seam and the user cannot unpick it later. If this is now wide, that '
          'decision was reversed by accident.',
    );
  });

  // ── LAYER 3 — the mechanism ────────────────────────────────────────────────
  group('the admitted-source set', () {
    test('renders the pre-existing predicate while it is empty', () {
      expect(kDerivableSources, isEmpty);
      expect(derivableSourceSql(), 'source IS NULL');
      expect(derivableSourceSql('d.source'), 'd.source IS NULL');
      expect(kPrimaryBandSourceSql, 'source IS NULL');
    });

    test('ids are SQL-safe, because the fragment interpolates them', () {
      for (final id in kDerivableSources) {
        expect(
          RegExp(r'^[a-z0-9_]+$').hasMatch(id),
          isTrue,
          reason: '`$id` is interpolated straight into rawQuery text',
        );
      }
    });

    test('a non-empty set widens, and never widens the band-only one', () {
      // The fragment is a pure function of the set, so the future shape is
      // checkable today without pretending an adapter is verified.
      String render(Set<String> ids, [String col = 'source']) => ids.isEmpty
          ? '$col IS NULL'
          : '($col IS NULL OR $col IN '
                "(${ids.map((s) => "'$s'").join(', ')}))";
      expect(render(const {}), derivableSourceSql());
      expect(
        render(const {'polar_h10'}),
        "(source IS NULL OR source IN ('polar_h10'))",
      );
      expect(
        render(const {'polar_h10', 'hrs_generic'}, 'd.source'),
        "(d.source IS NULL OR d.source IN ('polar_h10', 'hrs_generic'))",
      );
      // kPrimaryBandSourceSql is a const: it cannot widen, which is the point.
      expect(kPrimaryBandSourceSql, isNot(contains('IN')));
    });
  });

  // ── LAYER 2 — differential ─────────────────────────────────────────────────
  group('runtime', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider(
        (await Directory.systemTemp.createTemp('openstrap_admit_')).path,
      );
      LocalDb.dbName = 'openstrap_admission_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    tearDownAll(() async => LocalDb.close());

    test('an unverified adapter moves NO number, anywhere', () async {
      const lo = 1786690000;
      const hi = lo + 9;
      await LocalDb.commitSyncBatch(
        [for (var i = 0; i < 10; i++) _raw(lo + i, i + 1)],
        [for (var i = 0; i < 10; i++) _band(lo + i, i + 1)],
      );
      final db = await LocalDb.instance;
      await db.insert('sessions', {
        'id': 'w1',
        'start_ts': lo,
        'end_ts': hi,
        'type': 'run',
        'status': 'ended',
        'created_at': lo,
      });

      final before = await _everyAdmissionRead(lo, hi);
      // The band really is in there — otherwise this test passes on two empty
      // strings and proves nothing.
      expect(before, contains('hr: 60'));
      expect(before, contains('dataEdge=$hi'));

      for (var i = 0; i < 10; i++) {
        await _poison(lo + i, 90000 + i);
      }
      // The rows really did land: stored, not derived, is the contract.
      expect(
        ((await db.rawQuery(
                  'SELECT COUNT(*) c FROM decoded_onehz WHERE source IS NOT NULL',
                )).first['c']
                as num)
            .toInt(),
        10,
      );
      expect(
        ((await db.rawQuery(
                  'SELECT COUNT(*) c FROM decoded_rr WHERE source IS NOT NULL',
                )).first['c']
                as num)
            .toInt(),
        10,
      );

      expect(
        await _everyAdmissionRead(lo, hi),
        before,
        reason:
            'A read admitted an UNVERIFIED adapter\'s seconds. Nothing throws '
            'when this ships: a session HR silently becomes the average of two '
            'sensors that disagree systematically, and it lands in a baseline '
            'that outlives the band. Route the read through '
            'derivableSourceSql().',
      );
    });

    test('an admitted source WOULD be seen — the gate is not just a WHERE that '
        'excludes everything', () async {
      const lo = 1786690000;
      const hi = lo + 9;
      // Same shape as the poison rows, but source NULL: a second physical unit
      // under the primary band's own admission. If the readers were filtering
      // on something else (device_id, say), this would not move either, and the
      // test above would be proving nothing.
      final db = await LocalDb.instance;
      await db.insert('decoded_onehz', {
        'device_id': 'admitted_unit_2',
        'ts_ms': lo * 1000,
        'rec_ts': lo,
        'counter': 80001,
        'hr': 199,
        'source': null,
      });
      expect(
        (await LocalDb.hrSamplesInRange(lo, hi)).where((r) => r['hr'] == 199),
        isNotEmpty,
        reason: 'the admission gate filters on `source`, and nothing else',
      );
    });
  });
}
