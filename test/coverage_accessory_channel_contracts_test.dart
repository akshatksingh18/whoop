// Real Dart channel serialization/refusal contracts. This does not simulate
// Apple's picker, permissions, radio, OS relaunch or installed-phone acceptance.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/accessory_setup.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/accessory_setup');
  final calls = <MethodCall>[];
  Object? reply;
  var refuse = false;
  setUp(() {
    calls.clear();
    reply = null;
    refuse = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (refuse) throw PlatformException(code: 'authored-accessory-refusal');
      return reply;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  void exact(String method) {
    expect(calls.map((c) => c.method), [method]);
    expect(calls.single.arguments, isNull);
  }

  for (final mode in [
    'supported',
    'unsupported',
    'absent',
    'mistyped',
    'refused',
  ]) {
    test(
      'ASK support $mode retains conservative capability selection',
      () async {
        reply = switch (mode) {
          'supported' => true,
          'unsupported' => false,
          'mistyped' => 'true',
          _ => null,
        };
        refuse = mode == 'refused';
        expect(
          await AccessorySetup.isSupported(isIOS: true),
          mode == 'supported',
        );
        exact('isSupported');
      },
    );
  }
  for (final mode in ['present', 'absent', 'mistyped', 'refused']) {
    test('ASK provisioned ID $mode does not invent an identity', () async {
      const id = '00000000-0000-4000-8000-000000000074';
      reply = switch (mode) {
        'present' => id,
        'mistyped' => 74,
        _ => null,
      };
      refuse = mode == 'refused';
      expect(
        await AccessorySetup.provisionedId(isIOS: true),
        mode == 'present' ? id : null,
      );
      exact('provisionedId');
    });
  }
  for (final refusal in [false, true]) {
    test('ASK deprovision refusal=$refusal remains best effort', () async {
      refuse = refusal;
      await AccessorySetup.removeAll(isIOS: true);
      exact('removeAll');
      // The next provisioning query is independent of a failed removal.
      refuse = false;
      reply = null;
      expect(await AccessorySetup.provisionedId(isIOS: true), isNull);
      expect(calls.map((c) => c.method), ['removeAll', 'provisionedId']);
    });
  }
  for (final mode in ['present', 'empty', 'absent', 'mistyped', 'refused']) {
    test(
      'ASK picker $mode distinguishes identity, cancellation and native refusal',
      () async {
        const id = '00000000-0000-4000-8000-000000000074';
        reply = switch (mode) {
          'present' => id,
          'empty' => '',
          'mistyped' => 74,
          _ => null,
        };
        refuse = mode == 'refused';
        if (mode == 'present') {
          expect(await AccessorySetup.showPicker(), id);
        } else if (mode == 'refused') {
          await expectLater(
            AccessorySetup.showPicker(),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'authored-accessory-refusal',
              ),
            ),
          );
        } else if (mode == 'mistyped') {
          await expectLater(
            AccessorySetup.showPicker(),
            throwsA(isA<TypeError>()),
          );
        } else {
          await expectLater(
            AccessorySetup.showPicker(),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                'Exception: Pairing cancelled.',
              ),
            ),
          );
        }
        exact('showPicker');
      },
    );
  }
  test(
    'ASK unsupported host makes no native requests, even when native would refuse',
    () async {
      refuse = true;
      expect(await AccessorySetup.isSupported(isIOS: false), false);
      expect(await AccessorySetup.provisionedId(isIOS: false), isNull);
      await AccessorySetup.removeAll(isIOS: false);
      expect(calls, isEmpty);
    },
  );
}
