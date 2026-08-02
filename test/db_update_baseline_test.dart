// LocalDb.updateBaseline — the cross-isolate synchronization primitive behind
// the rolling sleep-profile fold, exercised against the REAL LocalDb over
// sqflite_ffi.
//
// Why this has its own suite: a Dart `static` mutex cannot serialize the fold,
// because derivation also runs in a background isolate (`derivationDispatcher`
// is a vm:entry-point WorkManager entry that builds its own DerivationEngine),
// and a static has one copy per isolate. The read-modify-write therefore has to
// be atomic in the DATABASE. `sleep_profile_policy_test.dart` covers the pure
// decision contract; these cover the storage contract it depends on.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
  @override
  Future<String?> getLibraryPath() async => root;
  @override
  Future<String?> getDownloadsPath() async => root;
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('openstrap_ub_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    LocalDb.dbName = 'openstrap_update_baseline_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('transform receives null when the key is absent, and can create it',
      () async {
    String? seen = 'not-called';
    var called = false;
    await LocalDb.updateBaseline('ub_absent', (current) {
      called = true;
      seen = current;
      return '{"v":1}';
    });
    expect(called, isTrue);
    expect(seen, isNull, reason: 'no row yet ⇒ transform sees null');
    final row = await LocalDb.baseline('ub_absent');
    expect(row?['payload_json'], '{"v":1}');
  });

  test('a null return leaves the existing row byte-identical', () async {
    await LocalDb.putBaseline('ub_untouched', '{"v":"original"}');
    final before = await LocalDb.baseline('ub_untouched');

    var sawCurrent = '';
    await LocalDb.updateBaseline('ub_untouched', (current) {
      sawCurrent = current ?? '<null>';
      return null; // decline
    });

    expect(sawCurrent, '{"v":"original"}');
    final after = await LocalDb.baseline('ub_untouched');
    expect(after?['payload_json'], before?['payload_json']);
    expect(after?['updated_at'], before?['updated_at'],
        reason: 'a declined update must not even bump updated_at');
  });

  test('a non-null return replaces the payload and advances updated_at',
      () async {
    await LocalDb.putBaseline('ub_replace', '{"n":1}');
    final before = await LocalDb.baseline('ub_replace');
    final beforeAt = before!['updated_at'] as int;

    // updated_at is millisecond-resolution wall clock; without a gap the
    // rewrite can land in the same millisecond and the assertion below would
    // be testing the clock, not the write.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await LocalDb.updateBaseline('ub_replace', (current) {
      final n = (jsonDecode(current!) as Map)['n'] as int;
      return jsonEncode({'n': n + 1});
    });

    final after = await LocalDb.baseline('ub_replace');
    expect(jsonDecode(after!['payload_json'] as String), {'n': 2});
    expect(after['updated_at'] as int, greaterThan(beforeAt));
  });

  test('sequential accumulate: every update observes the previous commit',
      () async {
    await LocalDb.updateBaseline('ub_accum', (_) => jsonEncode({'n': 0}));
    for (var i = 0; i < 25; i++) {
      await LocalDb.updateBaseline('ub_accum', (current) {
        final n = (jsonDecode(current!) as Map)['n'] as int;
        return jsonEncode({'n': n + 1});
      });
    }
    final row = await LocalDb.baseline('ub_accum');
    expect((jsonDecode(row!['payload_json'] as String) as Map)['n'], 25);
  });

  test('concurrent accumulate: no increment is lost to a read-modify-write race',
      () async {
    // The whole reason this method exists. Fired without awaiting between
    // them, these interleave; a plain read + putBaseline pair loses writes.
    await LocalDb.updateBaseline('ub_race', (_) => jsonEncode({'n': 0}));
    const lanes = 20;
    await Future.wait([
      for (var i = 0; i < lanes; i++)
        LocalDb.updateBaseline('ub_race', (current) {
          final n = (jsonDecode(current!) as Map)['n'] as int;
          return jsonEncode({'n': n + 1});
        })
    ]);
    final row = await LocalDb.baseline('ub_race');
    expect((jsonDecode(row!['payload_json'] as String) as Map)['n'], lanes,
        reason: 'each lane must observe every earlier commit');
  });

  test('concurrent set-union: no member is dropped', () async {
    // Closer to the real payload shape — folded_days is a set that must only
    // ever grow, and a lost write drops a day_id as well as a count.
    await LocalDb.updateBaseline(
        'ub_set', (_) => jsonEncode({'days': <String>[]}));
    final days = [for (var d = 10; d < 30; d++) '2026-07-$d'];
    await Future.wait([
      for (final day in days)
        LocalDb.updateBaseline('ub_set', (current) {
          final cur = ((jsonDecode(current!) as Map)['days'] as List)
              .cast<String>()
              .toSet();
          if (cur.contains(day)) return null;
          return jsonEncode({
            'days': (cur..add(day)).toList()..sort(),
          });
        })
    ]);
    final row = await LocalDb.baseline('ub_set');
    final stored =
        ((jsonDecode(row!['payload_json'] as String) as Map)['days'] as List)
            .cast<String>();
    expect(stored, days..sort());
  });

  test('a throwing transform rolls back and leaves the row intact', () async {
    await LocalDb.putBaseline('ub_throw', '{"v":"keep"}');
    await expectLater(
      LocalDb.updateBaseline('ub_throw', (_) => throw StateError('boom')),
      throwsStateError,
    );
    final row = await LocalDb.baseline('ub_throw');
    expect(row?['payload_json'], '{"v":"keep"}');

    // and the connection is still usable — a failed fold must not wedge the DB
    await LocalDb.updateBaseline('ub_throw', (_) => '{"v":"next"}');
    expect((await LocalDb.baseline('ub_throw'))?['payload_json'],
        '{"v":"next"}');
  });
}
