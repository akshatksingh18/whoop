// The current compact HR stream crosses the real frame router, remaining ephemeral.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/ble/ble_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final ts in [0, 1617714000]) {
      test(
        '${band.type.name} compact live HR carries unknown/real device time=$ts without history writes',
        () async {
          var stored = 0, commits = 0, derived = 0, writes = 0, stateCalls = 0;
          final engine = BleEngine(
            onRecord: (_, _) async {
              stored++;
            },
            onState: (_) => stateCalls++,
            log: (_) {},
            onDataStored: () => derived++,
          );
          engine.debugInstallFakeLink(
            band: band,
            onWrite: (_) async {
              writes++;
              return true;
            },
            onCommit: (_, _, _, {archives, deviceFamily}) async {
              commits++;
            },
          );
          try {
            await engine.enableLiveStreams();
            expect(engine.liveEnabled, true);
            final beforeWrites = writes;
            expect(beforeWrites, greaterThan(0));
            final body = Uint8List(20)..[0] = p.PacketType.realtimeData;
            ByteData.sublistView(body).setUint32(2, ts, Endian.little);
            body[8] = 66;
            body[9] = 1;
            ByteData.sublistView(body).setUint16(10, 909, Endian.little);
            body[18] = 1;
            final frame = p.parseFrame(
              p.buildFrame(body, profile: band),
              profile: band,
            )!;
            final before = engine.offloadSnapshot;
            engine.debugReceiveFrame(frame);
            expect(engine.state.liveHr, 66);
            expect(engine.state.liveHrAt, isNotNull);
            expect(stateCalls, greaterThan(0));
            expect(engine.offloadActive, false);
            expect(engine.offloadSnapshot, before);
            expect(stored, 0);
            expect(commits, 0);
            expect(derived, 0);
            expect(writes, beforeWrites);
            expect(
              engine.liveEnabled,
              true,
              reason: 'Receiving a frame must not issue a stream command',
            );
          } finally {
            await engine.disconnect();
          }
        },
      );
    }
  }
}
