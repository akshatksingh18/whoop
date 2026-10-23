// Native dispatch, ownership and empty-history behavior, without OS scheduling.
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/ble/ios_ble_restore.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/sync/band_ownership.dart';
import 'package:openstrap_edge/sync/file_log.dart';
import 'package:openstrap_edge/sync/headless_gate.dart';
import 'package:openstrap_edge/sync/ios_bg_task.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = (await Directory(
      'build/coverage-audit/bg-task',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BandOwnership.resetForTest();
    HeadlessSyncGate.resetForTest();
    IosBleRestore.foregroundActive = false;
    IosBgTask.foregroundPull = null;
    await LocalDb.wipeAll();
  });
  tearDown(() async {
    IosBleRestore.foregroundActive = false;
    IosBgTask.foregroundPull = null;
    await FileLog.write('Synthetic BG callback cleanup');
  });
  tearDownAll(LocalDb.close);

  test(
    'unknown callbacks do nothing; expiry stops compute and transfer',
    () async {
      final generation = DeriveStop.generation;
      expect(await IosBgTask.handleCall(const MethodCall('unknown')), isNull);
      expect(DeriveStop.generation, generation);
      final lease = BandOwnership.tryAcquireHeadless()!;
      String? reason;
      BandOwnership.registerHeadlessStop(lease, (r) => reason = r);
      await IosBgTask.handleCall(const MethodCall('expire'));
      expect(DeriveStop.generation, greaterThan(generation));
      expect(reason, 'ios_bg_task_expired');
      BandOwnership.release(lease);
    },
  );

  test(
    'a busy peer prevents both BG modes from starting a competing pull',
    () async {
      final held = Completer<void>();
      final peer = HeadlessSyncGate.tryRun('peer', () => held.future);
      IosBleRestore.foregroundActive = true;
      IosBgTask.foregroundPull = () async => fail('must skip');
      expect(
        await IosBgTask.handleCall(const MethodCall('run', {'mode': 'sync'})),
        isTrue,
      );
      expect(await IosBgTask.handleCall(const MethodCall('run')), isTrue);
      expect(HeadlessSyncGate.totalSkips, 2);
      held.complete();
      await peer;
    },
  );

  for (final light in [true, false]) {
    test(
      '${light ? 'refresh' : 'processing'} handles an unpaired empty history and releases ownership',
      () async {
        final args = light ? const {'mode': 'sync'} : null;
        expect(await IosBgTask.handleCall(MethodCall('run', args)), isTrue);
        expect(HeadlessSyncGate.busy, isFalse);
        expect(BandOwnership.owner, isNull);
        expect(await (await LocalDb.instance).query('day_result'), isEmpty);
      },
    );
  }

  test(
    'a failed foreground pull does not steal its lease or wedge future wakes',
    () async {
      final lease = await BandOwnership.acquireForeground();
      IosBleRestore.foregroundActive = true;
      var pulls = 0;
      IosBgTask.foregroundPull = () async {
        pulls++;
        throw StateError('synthetic pull');
      };
      expect(
        await IosBgTask.handleCall(const MethodCall('run', {'mode': 'sync'})),
        isTrue,
      );
      expect(pulls, 1);
      expect(BandOwnership.owner, BandOwnerKind.foreground);
      expect(HeadlessSyncGate.busy, isFalse);
      BandOwnership.release(lease);
    },
  );

  test('expiration during transfer cannot start a fresh calculation', () async {
    final entered = Completer<void>(), release = Completer<void>();
    IosBleRestore.foregroundActive = true;
    IosBgTask.foregroundPull = () async {
      entered.complete();
      await release.future;
    };
    await FileLog.write('SYNTHETIC_EXPIRY_BOUNDARY');
    final run = IosBgTask.handleCall(const MethodCall('run'));
    await entered.future;
    await IosBgTask.handleCall(const MethodCall('expire'));
    release.complete();
    expect(await run, isTrue);
    await FileLog.write('barrier');
    final log = (await File(
      (await FileLog.path())!,
    ).readAsString()).split('SYNTHETIC_EXPIRY_BOUNDARY').last;
    expect(log, isNot(contains('stage=calculation_start')));
    expect(log, isNot(contains('[derive]')));
    expect(HeadlessSyncGate.busy, isFalse);
  });
}
