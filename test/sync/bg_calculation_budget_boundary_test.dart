// Actual background-budget timer while native preferences are pending.
// Virtual time only;no sleep staging,radio or changed calculation policy.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/headless_gate.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'package:whoop_companion/sync/wake_timing.dart';
import 'history_watchdog_budget_test.dart' show historyIO, driveHistory;
import '../support/refusing_prefs_store.dart';
import '../support/coverage_store.dart';

class _HeldProfile extends RefusingPrefsStore {
  bool started = false;
  final reply = Completer<Map<String, Object>>();
  @override
  Future<Map<String, Object>> getAll() {
    started = true;
    return reply.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = SharedPreferencesStorePlatform.instance;
  final oldForeground = IosBleRestore.foregroundActive;
  final oldPull = IosBgTask.foregroundPull;
  setUpAll(() => coverageStore('bg-calculation-budget', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    HeadlessSyncGate.resetForTest();
    BandOwnership.resetForTest();
  });
  tearDown(() async {
    IosBleRestore.foregroundActive = oldForeground;
    IosBgTask.foregroundPull = oldPull;
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
    BandOwnership.resetForTest();
  });
  tearDownAll(LocalDb.close);
  for (final light in [true, false]) {
    testWidgets(
      '${light ? 'refresh' : 'processing'} real calculation budget expires during pending profile read and preserves queued data',
      (t) async {
        final db = (await t.runAsync(() => LocalDb.instance))!;
        await t.runAsync(() => LocalDb.setCursor('authored-retained', 'keep'));
        final cursors = await t.runAsync(() => db.query('sync_cursor'));
        final lease = await BandOwnership.acquireForeground();
        addTearDown(() => BandOwnership.release(lease));
        IosBleRestore.foregroundActive = true;
        var pulls = 0;
        IosBgTask.foregroundPull = () async {
          pulls++;
        };
        final store = _HeldProfile()
          ..values['flutter.authored-unrelated'] = 'keep';
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesStorePlatform.instance = store;
        final stages = <String>[];
        final before = DeriveStop.generation;
        var completed = false;
        final call = MethodCall('run', light ? const {'mode': 'sync'} : null);
        final work = WakeTiming.run(light ? 'bg_refresh' : 'bg_task', () async {
          final result = await IosBgTask.handleCall(call);
          completed = true;
          return result;
        }, log: stages.add);
        try {
          await historyIO(t, () => store.started);
          expect(pulls, 1);
          expect(HeadlessSyncGate.busy, true);
          final budget = light
              ? const Duration(seconds: 15)
              : const Duration(minutes: 4);
          // historyIO already advances a few milliseconds while observing the
          // native read. Check well inside the budget,then cross the real timer.
          final half = Duration(milliseconds: budget.inMilliseconds ~/ 2);
          await t.pump(half);
          expect(DeriveStop.generation, before);
          expect(completed, false);
          await t.pump(half + const Duration(milliseconds: 10));
          expect(DeriveStop.generation, before + 1);
          expect(
            stages.where((s) => s.contains('stage=calculation_budget_expiry')),
            hasLength(1),
          );
          expect(
            completed,
            false,
            reason: 'The pending native read still owns its reply',
          );
          store.reply.complete(Map.of(store.values));
          expect(await driveHistory(t, work), true);
          expect(HeadlessSyncGate.busy, false);
          expect(BandOwnership.owner, BandOwnerKind.foreground);
          expect(stages.any((s) => s.contains('stage=calculation_end')), true);
          expect(await t.runAsync(() => db.query('day_result')), isEmpty);
          expect(await t.runAsync(() => db.query('metric_series')), isEmpty);
          expect(await t.runAsync(() => db.query('sync_cursor')), cursors);
          expect(store.values, {'flutter.authored-unrelated': 'keep'});
          expect(t.takeException(), isNull);
        } finally {
          // A failed assertion must not leave the held wake or timer alive.
          if (!completed) {
            DeriveStop.request('authored_budget_fixture_cleanup');
            if (!store.reply.isCompleted) {
              store.reply.complete(Map.of(store.values));
            }
            await driveHistory(t, work);
          }
        }
      },
    );
  }
}
