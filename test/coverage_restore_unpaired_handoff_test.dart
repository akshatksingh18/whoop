// Actual registered Dart wake -> real headless unpaired flow -> completion.
// No radio or OS relaunch is simulated;native completion replies are authored.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/headless_gate.dart';
import 'package:whoop_companion/sync/sync_policy.dart';
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/ble_restore'),
      codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  var refuse = false;
  Future<Object?> wake() async {
    final response = Completer<ByteData?>();
    binding.channelBuffers.push(
      channel.name,
      codec.encodeMethodCall(const MethodCall('wake')),
      response.complete,
    );
    return codec.decodeEnvelope((await response.future)!);
  }

  setUpAll(() async {
    await coverageStore('restore-unpaired-handoff');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (refuse) throw PlatformException(code: 'authored-sync-done-refusal');
      return null;
    });
    await IosBleRestore.init(isIOS: true);
    await IosBleRestore.announceReady(isIOS: true);
  });
  setUp(() async {
    await resetCoverageStore();
    BandOwnership.resetForTest();
    HeadlessSyncGate.resetForTest();
    IosBleRestore.foregroundActive = false;
    IosBleRestore.onWake = null;
    calls.clear();
    refuse = false;
  });
  tearDown(() async {
    IosBleRestore.onWake = null;
    IosBleRestore.foregroundActive = false;
    expect(HeadlessSyncGate.busy, false);
    expect(BandOwnership.owner, isNull);
    await FileLog.write('Authored unpaired wake cleanup');
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await LocalDb.close();
  });
  for (final owner in ['absent', 'declines', 'throws']) {
    for (final refusal in [false, true]) {
      test(
        'unpaired restore owner=$owner native completion refusal=$refusal preserves history and permits the next wake',
        () async {
          await LocalDb.putDayResult(
            dayId: '2021-04-06',
            algoVersion: kAlgoVersion,
            payloadJson: '{"scalars":{"rhr":57}}',
            windowJson: '{}',
            rhr: 57,
            series: {'rhr': 57},
          );
          await LocalDb.setCursor('strap_trim', '7401020304050607');
          final db = await LocalDb.instance;
          final rows = await db.query('day_result'),
              series = await db.query('metric_series');
          var offers = 0;
          if (owner != 'absent') {
            IosBleRestore.onWake = () async {
              offers++;
              if (owner == 'throws') {
                throw StateError('authored live owner failure');
              }
              return RestoreWakeOutcome.notHandled;
            };
          }
          refuse = refusal;
          final earliest = DateTime.now().millisecondsSinceEpoch;
          expect(await wake(), isNull);
          expect(calls.map((c) => c.method), ['syncDone']);
          expect(calls.single.arguments, isNull);
          expect(offers, owner == 'absent' ? 0 : 1);
          expect(HeadlessSyncGate.busy, false);
          expect(HeadlessSyncGate.totalSkips, 0);
          expect(BandOwnership.owner, isNull);
          final health = await LocalDb.syncHealth();
          expect(health.wakeSource, 'ble_restore');
          expect(
            health.wakeAt,
            inInclusiveRange(earliest, DateTime.now().millisecondsSinceEpoch),
          );
          expect(await db.query('day_result'), rows);
          expect(await db.query('metric_series'), series);
          expect(await LocalDb.getCursor('strap_trim'), '7401020304050607');
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(await db.query('raw_archive'), isEmpty);
          // A refused completion does not wedge Dart ownership or consume a
          // duplicate trim token. A later normal wake can complete independently.
          calls.clear();
          refuse = false;
          expect(await wake(), isNull);
          expect(calls.map((c) => c.method), ['syncDone']);
          expect(offers, owner == 'absent' ? 0 : 2);
          expect(await db.query('day_result'), rows);
          expect(await LocalDb.getCursor('strap_trim'), '7401020304050607');
        },
      );
    }
  }
}
