// Build 86 background repair: a stop really stops calculation. Backgrounding
// (or iOS expiring a wake) kills the in-flight compute isolate instead of
// letting it run on into a CPU-limit kill, and the scheduler hands a stopped
// job back to the queue rather than marking it failed or done.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/derive_scheduler.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int _spin() {
  var x = 0;
  final until = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(until)) {
    x++;
  }
  return x;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_background_stop_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('a stop kills a running compute isolate at once', () async {
    final watch = Stopwatch()..start();
    final work = runCancellableIsolate<int>(
      _spin,
      const Duration(minutes: 1),
      label: 'spin',
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    DeriveStop.request('test');
    await expectLater(work, throwsA(isA<DeriveCancelled>()));
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('check() throws only for a stop after the given generation', () {
    final gen = DeriveStop.generation;
    expect(() => DeriveStop.check(gen), returnsNormally);
    DeriveStop.request('later');
    expect(() => DeriveStop.check(gen), throwsA(isA<DeriveCancelled>()));
  });

  test('a stopped job is requeued, not failed or completed', () async {
    var runs = 0;
    final first = Completer<void>();
    late DeriveScheduler s;
    s = DeriveScheduler(
      run: ({required DeriveJobKind kind}) async {
        runs++;
        if (runs == 1) {
          if (!first.isCompleted) first.complete();
          throw const DeriveCancelled('backgrounded');
        }
      },
      log: (_) {},
      onChanged: () {},
      lightSettle: const Duration(milliseconds: 10),
      heavySettle: const Duration(milliseconds: 10),
    );
    addTearDown(s.dispose);
    await s.init();
    await s.markStoredData();
    await first.future;
    // The stopped job is back in the queue and runs again by itself.
    final until = DateTime.now().add(const Duration(seconds: 5));
    while (runs < 2 && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(runs, 2, reason: 'requeued work drains on the next opportunity');
    final failed = await LocalDb.computeJobs(state: 'failed', limit: 10);
    expect(failed, isEmpty);
  });
}
