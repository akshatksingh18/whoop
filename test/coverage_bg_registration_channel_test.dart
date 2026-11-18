// Authored native messages enter the actual registration,codec and dispatcher.
// This verifies Dart wiring,not physical iOS wake delivery.
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/bg_task');
  const codec = StandardMethodCodec();
  setUp(() => channel.setMethodCallHandler(null));
  tearDown(() => channel.setMethodCallHandler(null));
  Future<ByteData?> send(String method) {
    final reply = Completer<ByteData?>();
    // ignore: deprecated_member_use
    binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method)),
      reply.complete,
    );
    return reply.future;
  }

  for (final host in [null, false, true]) {
    test(
      'background registration host=$host keeps native expiry and unknown-method ownership',
      () async {
        final before = DeriveStop.generation;
        if (host == null) {
          await IosBgTask.init();
        } else {
          await IosBgTask.init(isIOS: host);
        }
        final enabled = host ?? Platform.isIOS;
        final unknown = await send('authored-unknown-method');
        expect(DeriveStop.generation, before);
        if (enabled) {
          expect(unknown, isNotNull);
          expect(codec.decodeEnvelope(unknown!), isNull);
        } else {
          expect(unknown, isNull);
        }
        final expired = await send('expire');
        expect(DeriveStop.generation, enabled ? before + 1 : before);
        if (enabled) {
          expect(expired, isNotNull);
          expect(codec.decodeEnvelope(expired!), isNull);
          expect(DeriveStop.error.toString(), contains('ios_bg_task_expired'));
        } else {
          expect(expired, isNull);
        }
      },
    );
  }
}
