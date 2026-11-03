// Real outbound stream commands with only the GATT transport substituted.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as proto;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final family in [proto.BandProfile.gen4, proto.BandProfile.gen5]) {
    final label = family == proto.BandProfile.gen4 ? 'gen4' : 'gen5';
    for (final refusal in ['refused', 'throws']) {
      test(
        '$label live arming $refusal remains retryable instead of advertising an enabled stream',
        () async {
          final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
          var fail = true;
          final writes = <List<int>>[];
          engine.debugInstallFakeLink(
            band: family,
            onWrite: (frame) async {
              final inner = proto.parseFrame(frame, profile: family)!.inner;
              writes.add(inner);
              if (fail && inner[2] == proto.Cmd.toggleRealtimeHr) {
                if (refusal == 'throws')
                  throw StateError('synthetic transport refusal');
                return false;
              }
              return true;
            },
          );
          try {
            await engine.enableLiveStreams();
            expect(engine.liveEnabled, isFalse);
            expect(engine.liveHrOnly, isFalse);
            fail = false;
            await engine.enableLiveStreams();
            expect(engine.liveEnabled, isTrue);
            expect(engine.liveHrOnly, isTrue);
            expect(
              writes.where(
                (x) => x[2] == proto.Cmd.toggleRealtimeHr && x[3] == 1,
              ),
              hasLength(2),
            );
            await engine.disableLiveStreams();
            expect(engine.liveEnabled, isFalse);
            expect(engine.liveHrOnly, isFalse);
            expect(writes.last[2], proto.Cmd.toggleRealtimeHr);
            expect(writes.last[3], 0);
          } finally {
            await engine.disconnect();
          }
        },
      );
    }
    test(
      '$label disabling clears the displayed live reading and reconnect starts unarmed',
      () async {
        var notices = 0;
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {
            notices++;
          },
        );
        engine.debugInstallFakeLink(band: family, onWrite: (_) async => true);
        await engine.enableHrOnlyLive();
        engine.state.liveHr = 65;
        await engine.disableLiveStreams();
        expect(engine.state.liveHr, isNull);
        expect(notices, greaterThan(0));
        await engine.disconnect();
        engine.debugInstallFakeLink(band: family, onWrite: (_) async => true);
        expect(engine.liveEnabled, isFalse);
        expect(engine.liveHrOnly, isFalse);
        await engine.disconnect();
      },
    );
  }
  test('an absent link cannot become live just by asking', () async {
    final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
    await engine.enableLiveStreams();
    expect(engine.liveEnabled, isFalse);
    expect(engine.state.liveHr, isNull);
    await engine.disconnect();
  });
}
