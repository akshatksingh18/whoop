// Existing iOS bridge defaults must remain harmless on the non-iOS CI host.
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('whoop/ble_restore');
  test(
    'default iOS bridge calls keep non-iOS ownership intact and send no IPC',
    () async {
      expect(
        Platform.isIOS,
        false,
        reason: 'This checks the Linux/desktop bridge default contract',
      );
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
        c,
      ) async {
        calls.add(c);
        return 'background';
      });
      final before = IosBleRestore.foregroundActive;
      try {
        IosBleRestore.foregroundActive = true;
        await IosBleRestore.init();
        await IosBleRestore.announceReady();
        await IosBleRestore.setOwnsBand(false);
        await IosBleRestore.provisioned('authored-default-band');
        await IosBleRestore.arm('authored-default-band');
        await IosBleRestore.armRecoveryNow('authored-default-band');
        await IosBleRestore.disarm();
        expect(await IosBleRestore.appState(), isNull);
        expect(IosBleRestore.foregroundActive, true);
        expect(
          calls,
          isEmpty,
          reason:
              'Default guards must not touch native ownership on other hosts',
        );
      } finally {
        IosBleRestore.foregroundActive = before;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
      }
    },
  );
}
