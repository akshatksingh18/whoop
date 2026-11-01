// Actual public controls with authored inner replies and a scripted write sink.
// These prove wire/refusal policy, not physical haptics or RTC acceptance.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final accepted in [false, true]) {
      test(
        'COV-48 ${band.type.name} alarm test pulse write accepted=$accepted',
        () async {
          final frames = <Uint8List>[];
          final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
          engine.debugInstallFakeLink(
            band: band,
            onWrite: (frame) async {
              frames.add(frame);
              return accepted;
            },
          );
          try {
            expect(await engine.runAlarm(), accepted);
            expect(frames, hasLength(1));
            final inner = p.parseFrame(frames.single, profile: band)!.inner;
            expect(
              inner[2],
              band.isGen5 ? p.Cmd.runHapticPatternMaverick : p.Cmd.runAlarm,
            );
            // Fixed documented pulse body, independent of the production builder.
            expect(
              inner.sublist(3),
              band.isGen5 ? [1, 47, 152, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0] : [1],
            );
            expect(engine.pendingCommandCount, 0);
            expect(engine.offloadActive, false);
            expect(await engine.disableAlarm(), accepted);
            final cancel = p.parseFrame(frames.last, profile: band)!.inner;
            expect(cancel[2], p.Cmd.disableAlarm);
            expect(cancel[3], band.isGen5 ? 2 : 1);
            if (band.isGen5) {
              expect(cancel[4], 255);
            }
          } finally {
            await engine.disconnect();
          }
        },
      );
    }
    test(
      'COV-48 ${band.type.name} actual clock replies bound correction retries and rearm after agreement',
      () async {
        final logs = <String>[], commands = <int>[];
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: logs.add,
        );
        engine.debugInstallFakeLink(
          band: band,
          onWrite: (frame) async {
            commands.add(p.parseFrame(frame, profile: band)!.inner[2]);
            return false;
          },
        );
        Future<void> reply(int epoch) async {
          final inner = Uint8List(9)
            ..[0] = p.PacketType.commandResponse
            ..[1] = 17
            ..[2] = p.Cmd.getClock
            ..[3] = 11
            ..[4] = 1;
          ByteData.sublistView(inner).setUint32(5, epoch, Endian.little);
          engine.debugProcessImmediateFrame(p.Frame(inner, true, true));
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }

        try {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          for (var i = 0; i < 5; i++) {
            await reply(now - 2 * 86400);
          }
          expect(commands.where((c) => c == p.Cmd.setClock), hasLength(3));
          expect(commands.where((c) => c == p.Cmd.getClock), hasLength(3));
          expect(
            logs.any(
              (s) => s.contains('Clock still off after 3 SET_CLOCK attempts'),
            ),
            true,
          );
          expect(engine.pendingCommandCount, 0);
          expect(engine.historyPausedForClock, false);
          await reply(now);
          expect(commands, hasLength(6));
          await reply(now - 2 * 86400);
          expect(commands.where((c) => c == p.Cmd.setClock), hasLength(4));
          expect(commands.where((c) => c == p.Cmd.getClock), hasLength(4));
          expect(engine.pendingCommandCount, 0);
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
}
