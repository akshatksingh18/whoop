// Scripted lowest-level writes only; no peripheral, radio or persistent setting changes.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final refuseFirst in [false, true]) {
      test(
        'COV-45 ${band.type.name} wake-window writes retry, deduplicate and exit $refuseFirst',
        () async {
          final frames = <Uint8List>[];
          final logs = <String>[];
          var refuse = refuseFirst;
          final engine = BleEngine(
            onRecord: (_, _) async {},
            onState: (_) {},
            log: logs.add,
          );
          engine.debugInstallFakeLink(
            band: band,
            onWrite: (frame) async {
              frames.add(frame);
              return !refuse;
            },
          );
          final wake = DateTime(2021, 4, 6, 7);
          try {
            await engine.applyHighFreqWakeWindow(
              enabled: true,
              targetWake: wake,
              reason: 'synthetic',
            );
            if (refuseFirst) {
              expect(logs.any((s) => s.contains('mode NOT claimed')), true);
              refuse = false;
              await engine.applyHighFreqWakeWindow(
                enabled: true,
                targetWake: wake,
                reason: 'synthetic',
              );
            }
            final accepted = frames.length;
            await engine.applyHighFreqWakeWindow(
              enabled: true,
              targetWake: wake,
              reason: 'synthetic',
            );
            expect(frames, hasLength(accepted));
            await engine.applyHighFreqWakeWindow(
              enabled: false,
              targetWake: wake,
              reason: 'synthetic',
            );
            expect(p.parseFrame(frames.last, profile: band)!.inner[2], 0x61);
            final afterExit = frames.length;
            await engine.applyHighFreqWakeWindow(
              enabled: false,
              targetWake: null,
            );
            expect(frames, hasLength(afterExit));
            await engine.applyHighFreqWakeWindow(
              enabled: true,
              targetWake: wake,
            );
            expect(p.parseFrame(frames.last, profile: band)!.inner[2], 0x60);
            expect(
              frames.every(
                (f) => p.parseFrame(f, profile: band)?.inner[0] == 0x23,
              ),
              true,
            );
          } finally {
            await engine.disconnect();
          }
        },
      );
    }
    for (final name in [
      'Synthetic owner',
      'A\u0001BéC',
      '1234567890123456789012345',
      '',
    ]) {
      test(
        'COV-45 ${band.type.name} advertising name has a bounded ASCII wire body $name',
        () async {
          final frames = <Uint8List>[];
          final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
          engine.debugInstallFakeLink(
            band: band,
            onWrite: (frame) async {
              frames.add(frame);
              return true;
            },
          );
          try {
            await engine.setStrapName(name);
            final inner = p.parseFrame(frames.single, profile: band)!.inner;
            final expected = switch (name) {
              'Synthetic owner' => 'Synthetic owner',
              '' => '',
              'A\u0001BéC' => 'ABC',
              _ => '12345678901234567890',
            };
            expect(inner.sublist(3), [
              1,
              expected.length,
              ...expected.codeUnits,
              0,
              0,
              0,
              0,
              // Wire framing pads the complete type/sequence/opcode/body to /4.
              ...List.filled((4 - (9 + expected.length) % 4) % 4, 0),
            ]);
            expect(inner[2], band.isGen5 ? 0x8c : 0x4d);
            expect(engine.pendingCommandCount, 0);
          } finally {
            await engine.disconnect();
          }
        },
      );
    }
    for (final optIn in [false, true]) {
      test(
        'COV-45 ${band.type.name} INIT persistent flags require the explicit test opt-in $optIn',
        () async {
          final frames = <Uint8List>[];
          final engine = BleEngine(
            onRecord: (_, _) async {},
            onState: (_) {},
            gen5DeepBuffersEnabled: () => optIn,
          );
          engine.debugInstallFakeLink(
            band: band,
            onWrite: (frame) async {
              frames.add(frame);
              return true;
            },
          );
          try {
            expect(await engine.sendInit(drain: false), true);
            final inners = frames
                .map((f) => p.parseFrame(f, profile: band)!.inner)
                .toList();
            final configs = inners.where((f) => f[2] == 120).toList();
            expect(configs.isNotEmpty, band.isGen5 && optIn);
            expect(inners.any((f) => f[2] == 0x16), false);
            if (configs.isNotEmpty) {
              expect(
                configs.every((f) => f.length == configs.first.length),
                true,
              );
              expect(
                configs.map((f) => f[1]).toSet(),
                hasLength(configs.length),
              );
            }
          } finally {
            await engine.disconnect();
          }
        },
      );
    }
  }
}
