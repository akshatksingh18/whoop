// Real Dart handler/payloads with explicit host inputs. Native scheduling,
// Bluetooth restoration and physical phone acceptance remain separate.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/ble_restore');
  final calls = <MethodCall>[];
  var refuse = false;
  setUp(() {
    calls.clear();
    refuse = false;
    IosBleRestore.foregroundActive = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (refuse) throw PlatformException(code: 'authored-restore-refusal');
      return call.method == 'appState' ? 'background' : null;
    });
  });
  tearDown(() {
    IosBleRestore.foregroundActive = false;
    IosBleRestore.onWake = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test(
    'Restore init registers the real handler; ready announces once and cancels fallback',
    () async {
      await IosBleRestore.init(isIOS: true);
      try {
        const codec = StandardMethodCodec();
        final reply = Completer<ByteData?>();
        binding.channelBuffers.push(
          channel.name,
          codec.encodeMethodCall(
            const MethodCall('unrecognized-authored-call'),
          ),
          reply.complete,
        );
        expect(codec.decodeEnvelope((await reply.future)!), isNull);
        expect(calls, isEmpty);
        await IosBleRestore.announceReady(isIOS: true);
        await IosBleRestore.announceReady(isIOS: true);
        expect(calls.map((c) => c.method), ['ready']);
        expect(calls.single.arguments, isNull);
      } finally {
        await IosBleRestore.announceReady(isIOS: true);
      }
    },
  );
  final commands = <(String, Object?, Future<void> Function())>[
    ('setOwnsBand', true, () => IosBleRestore.setOwnsBand(true, isIOS: true)),
    ('setOwnsBand', false, () => IosBleRestore.setOwnsBand(false, isIOS: true)),
    (
      'provisioned',
      'authored-peripheral',
      () => IosBleRestore.provisioned('authored-peripheral', isIOS: true),
    ),
    (
      'arm',
      'authored-peripheral',
      () => IosBleRestore.arm('authored-peripheral', isIOS: true),
    ),
    (
      'armRecoveryNow',
      'authored-peripheral',
      () => IosBleRestore.armRecoveryNow('authored-peripheral', isIOS: true),
    ),
    ('disarm', null, () => IosBleRestore.disarm(isIOS: true)),
  ];
  for (final (method, payload, send) in commands) {
    for (final refusal in [false, true]) {
      test(
        'Restore $method($payload) ${refusal ? 'refusal' : 'acknowledgement'} retains its exact one-call contract',
        () async {
          IosBleRestore.foregroundActive = true;
          refuse = refusal;
          await send();
          expect(calls.map((c) => c.method), [method]);
          expect(calls.single.arguments, payload);
          expect(IosBleRestore.foregroundActive, method != 'armRecoveryNow');
        },
      );
    }
  }
  for (final refusal in [false, true]) {
    test(
      'Restore appState ${refusal ? 'refusal stays unknown' : 'returns the native state'}',
      () async {
        refuse = refusal;
        expect(
          await IosBleRestore.appState(isIOS: true),
          refusal ? null : 'background',
        );
        expect(calls.map((c) => c.method), ['appState']);
        expect(calls.single.arguments, isNull);
      },
    );
  }
  test(
    'Restore explicit unsupported host never calls native or releases foreground ownership',
    () async {
      IosBleRestore.foregroundActive = true;
      await IosBleRestore.init(isIOS: false);
      await IosBleRestore.announceReady(isIOS: false);
      await IosBleRestore.setOwnsBand(false, isIOS: false);
      await IosBleRestore.provisioned('authored-peripheral', isIOS: false);
      await IosBleRestore.arm('authored-peripheral', isIOS: false);
      await IosBleRestore.armRecoveryNow('authored-peripheral', isIOS: false);
      await IosBleRestore.disarm(isIOS: false);
      expect(await IosBleRestore.appState(isIOS: false), isNull);
      expect(calls, isEmpty);
      expect(IosBleRestore.foregroundActive, true);
    },
  );
}
