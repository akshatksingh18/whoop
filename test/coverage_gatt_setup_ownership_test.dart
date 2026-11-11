// Real engine/peripheral setup and ownership;authored OS replies,not radio proof.
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'support/coverage_store.dart';

class _Drain extends BleEngine {
  _Drain(List<String> logs)
    : super(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: logs.add,
        isBackgroundDrainer: true,
      );
  bool refuseAfterCleanup = false;
  @override
  Future<void> disconnect() async {
    await super.disconnect();
    if (refuseAfterCleanup) {
      throw StateError('authored owner completion refusal');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await coverageStore('gatt-setup-ownership');
  });
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
    peripheral.mode = 'ready';
    peripheral.replyToCommand = null;
  });
  tearDownAll(LocalDb.close);
  BleEngine band(List<String> logs, {bool background = false}) => BleEngine(
    onRecord: (_, _) async {},
    onState: (_) {},
    log: logs.add,
    isBackgroundDrainer: background,
  );
  for (final zero in [false, true]) {
    test(
      'COV-64 correlated clock zero fallback=$zero preserves the connection and original history',
      () async {
        final logs = <String>[];
        final engine = band(logs);
        peripheral.engine = engine;
        final requests = <int>[];
        peripheral.replyToCommand = (_, inner) {
          final op = inner[2];
          if (op == p.Cmd.getClock) requests.add(inner[1]);
          engine.debugAbsorbDecoded(
            p.Decoded('cmd_response', {
              'opcode': op,
              'req_seq': zero && op == p.Cmd.getClock ? 0 : inner[1],
              'cmd_status': 1,
              if (op == p.Cmd.getClock)
                'clock_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            }),
          );
        };
        final db = await LocalDb.instance;
        final cursor = await db.query('sync_cursor');
        try {
          expect(
            await engine.connectToRemoteId(Peripheral.id.str),
            true,
            reason: logs.join('\n'),
          );
          expect(requests, isNotEmpty);
          expect(requests.every((s) => s != 0), true);
          expect(
            logs.any(
              (s) => s.contains(
                'GET_CLOCK reply matched via the seq-zero fallback',
              ),
            ),
            zero,
          );
          expect(engine.isConnected, true);
          expect(engine.holdsBandLink, true);
          expect(await db.query('sync_cursor'), cursor);
          expect(await db.query('decoded_onehz'), isEmpty);
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
  for (final drop in [false, true]) {
    test(
      'COV-64 native setup drop=$drop retains a single claim and allows a clean reconnect',
      () async {
        final logs = <String>[];
        final engine = band(logs);
        peripheral.engine = engine;
        var dropped = false;
        engine.debugOnPriorityRequest = () {
          if (drop && !dropped) {
            dropped = true;
            peripheral.link(false);
          }
        };
        try {
          expect(
            await engine.connectToRemoteId(Peripheral.id.str),
            !drop,
            reason: logs.join('\n'),
          );
          expect(engine.isConnected, !drop);
          if (drop) {
            expect(engine.holdsBandLink, false);
            // OS link-down can settle before the later setup diagnostic.
            // The contract is no commands/no retained claim and a retry,
            // regardless of which teardown continuation reports it.
            expect(
              peripheral.trace.where((s) => s.startsWith('write:')),
              isEmpty,
            );
            expect(dropped, true);
            engine.debugOnPriorityRequest = null;
            expect(await engine.connectToRemoteId(Peripheral.id.str), true);
            expect(engine.holdsBandLink, true);
          }
          expect(
            await (await LocalDb.instance).query('decoded_onehz'),
            isEmpty,
          );
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
  for (final refused in [false, true]) {
    test(
      'COV-64 foreground takeover after owner cleanup refusal=$refused never grants a third drainer',
      () async {
        final logs = <String>[];
        final incumbent = _Drain(logs);
        final foreground = band(logs),
            challenger = band(logs, background: true);
        peripheral.engine = incumbent;
        try {
          expect(await incumbent.connectToRemoteId(Peripheral.id.str), true);
          incumbent.refuseAfterCleanup = refused;
          peripheral.engine = foreground;
          expect(
            await foreground.connectToRemoteId(Peripheral.id.str),
            true,
            reason: logs.join('\n'),
          );
          expect(incumbent.holdsBandLink, false);
          expect(incumbent.isConnected, false);
          expect(foreground.holdsBandLink, true);
          expect(
            logs.any((s) => s.contains('preempted engine teardown failed')),
            refused,
          );
          final trace = [...peripheral.trace];
          expect(await challenger.connectToRemoteId(Peripheral.id.str), false);
          expect(peripheral.trace, trace);
          expect(foreground.isConnected, true);
          expect(challenger.holdsBandLink, false);
        } finally {
          incumbent.refuseAfterCleanup = false;
          await challenger.disconnect();
          await foreground.disconnect();
          await incumbent.disconnect();
        }
      },
    );
  }
  test(
    'COV-64 bootstrap and init-drain refuse a missing owner without touching the peripheral',
    () async {
      final logs = <String>[];
      final engine = band(logs);
      peripheral.engine = engine;
      try {
        expect(await engine.debugBootstrapAfterRegistration(), false);
        expect(await engine.debugStartInitDrain(), false);
        expect(peripheral.trace, isEmpty);
        expect(engine.holdsBandLink, false);
        expect(await (await LocalDb.instance).query('sync_cursor'), isEmpty);
      } finally {
        await engine.disconnect();
      }
    },
  );
}
