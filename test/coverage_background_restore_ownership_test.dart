// Real AppState -> restoration bridge; authored peripheral and native replies.
// This checks Dart ownership contracts, not iOS relaunch/physical delivery.
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'coverage_connection_lifecycle_test.dart' show LifecycleBand;
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/ble_restore');
  late LifecycleBand band;
  late AppState app;
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall)? native;
  setUpAll(() async {
    await coverageStore('background-restore-ownership');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return await native?.call(call);
    });
  });
  setUp(() async {
    await resetCoverageStore();
    calls.clear();
    native = null;
    IosBleRestore.foregroundActive = false;
    band = LifecycleBand();
    app = AppState.forTesting(engine: band)
      ..paired = PairedDevice('authored-band-a', null, generation: 'gen4');
  });
  tearDown(() async {
    app.dispose();
    IosBleRestore.foregroundActive = false;
    await FileLog.write('Authored background restoration barrier');
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await LocalDb.close();
  });
  for (final connected in [false, true]) {
    for (final paired in [false, true]) {
      for (final refused in [false, true]) {
        test(
          'COV-62 background connected=$connected paired=$paired native refusal=$refused preserves ownership',
          () async {
            band.connected = connected;
            if (!paired) app.paired = null;
            if (paired && !connected) IosBleRestore.foregroundActive = true;
            native = (_) async {
              if (refused) {
                throw PlatformException(code: 'authored restore refusal');
              }
              return null;
            };
            final before = await (await LocalDb.instance).query('sync_cursor');
            await app.pauseForBackground(isIOS: true);
            expect(band.connected, connected);
            expect(
              band.calls,
              isEmpty,
              reason: 'Backgrounding must not tear down or reconnect this link',
            );
            final expected = connected
                ? 'setOwnsBand'
                : paired
                ? 'armRecoveryNow'
                : null;
            expect(
              calls.map((c) => c.method),
              expected == null ? [] : [expected],
            );
            if (expected != null) {
              expect(
                calls.single.arguments,
                connected ? true : 'authored-band-a',
              );
            }
            expect(IosBleRestore.foregroundActive, connected);
            expect(
              calls.where((c) => c.method == 'arm' || c.arguments == false),
              isEmpty,
              reason:
                  'Recovery uses one atomic native handoff, never a release/arm gap',
            );
            expect(await (await LocalDb.instance).query('sync_cursor'), before);
            expect(await (await LocalDb.instance).query('day_result'), isEmpty);
            expect(app.derivePending, false);
          },
        );
      }
    }
  }
  for (final connected in [false, true]) {
    for (final host in ['other host', 'default host']) {
      test(
        'COV-62 $host connected=$connected does not force iOS restoration',
        () async {
          band.connected = connected;
          if (host == 'default host') {
            await app.pauseForBackground();
          } else {
            await app.pauseForBackground(isIOS: false);
          }
          final ios = host == 'default host' && Platform.isIOS;
          expect(
            calls.map((c) => c.method),
            ios ? [connected ? 'setOwnsBand' : 'armRecoveryNow'] : [],
          );
          expect(IosBleRestore.foregroundActive, ios && connected);
          expect(band.connected, connected);
          expect(band.calls, isEmpty);
        },
      );
    }
  }
  for (final connected in [false, true]) {
    test(
      'COV-62 held background handoff connected=$connected keeps its accepted owner',
      () async {
        band.connected = connected;
        final entered = Completer<void>(), release = Completer<Object?>();
        native = (_) {
          entered.complete();
          return release.future;
        };
        var finished = false;
        final pending = app
            .pauseForBackground(isIOS: true)
            .then((_) => finished = true);
        try {
          await entered.future;
          expect(finished, false);
          expect(IosBleRestore.foregroundActive, connected);
          expect(calls.single.arguments, connected ? true : 'authored-band-a');
          app.paired = PairedDevice(
            'authored-band-b',
            null,
            generation: 'gen5',
          );
          expect(calls, hasLength(1));
        } finally {
          release.complete(null);
          await pending;
        }
        expect(finished, true);
        native = null;
        await app.pauseForBackground(isIOS: true);
        expect(calls, hasLength(2));
        expect(calls.last.arguments, connected ? true : 'authored-band-b');
        expect(band.calls, isEmpty);
        expect(await LocalDb.getCursor('strap_trim'), isNull);
      },
    );
  }
}
