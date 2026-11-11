// Actual motion IPC/cache boundary: an expired absence is durable; a recent
// refusal remains retryable and must not be confused with measured zero.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/motion_window.dart';
import 'coverage_motion_retention_test.dart' show key;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/phone_steps');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() => coverageStore('motion-expired-absence'));
  setUp(() async {
    await resetCoverageStore();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  tearDownAll(LocalDb.close);
  for (final expired in [false, true]) {
    test(
      '${expired ? 'expired' : 'recent'} native absence preserves history '
      'and ${expired ? 'is remembered' : 'can recover to measured zero'}',
      () async {
        final from = DateTime.now().subtract(Duration(days: expired ? 8 : 3));
        final to = from.add(const Duration(minutes: 2));
        final cache = key('authored-session', from, to);
        await LocalDb.setCursor('authored-history', 'retained');
        Object reply = -1;
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          expect(call.method, 'motionWindow');
          expect(call.arguments, {
            'fromMs': from.millisecondsSinceEpoch,
            'toMs': to.millisecondsSinceEpoch,
            'chunkSec': 60,
          });
          return reply;
        });
        expect(await motionWindow('authored-session', from, to), isNull);
        expect(await CalculationStore.read(cache), expired ? 'none' : null);
        reply = {
          'chunkSec': 60,
          'steps': [0, 0],
          'meters': [0.0, 0.0],
        };
        final retried = await motionWindow('authored-session', from, to);
        if (expired) {
          expect(retried, isNull);
          expect(calls, hasLength(1));
          expect(await CalculationStore.read(cache), 'none');
        } else {
          expect(retried!.totalSteps, 0);
          expect(retried.totalMeters, 0);
          expect(retried.seconds, [60, 60]);
          expect(calls, hasLength(2));
          expect(await CalculationStore.read(cache), isNotNull);
        }
        expect(await LocalDb.getCursor('authored-history'), 'retained');
        expect(await (await LocalDb.instance).query('day_result'), isEmpty);
      },
    );
  }
}
