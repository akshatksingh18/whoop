// The shared lifecycle runner now also owns the existing private day-block
// stage. Keep its legacy diagnostic contract and plain typed result transport.
import 'dart:async';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';

class AuthoredDayResult {
  AuthoredDayResult(this.values, this.window);
  final Map<String, Object?> values;
  final (int, int) window;
}

void main() {
  test(
    'the shared worker transports a typed day result with null and zero intact',
    () async {
      final result = await runCancellableIsolate<AuthoredDayResult>(
        () => AuthoredDayResult(
          {
            'absent': null,
            'measured': 0,
            'trace': [1, null, 3],
          },
          (100, 200),
        ),
        const Duration(seconds: 5),
        label: 'day-blocks',
        timeoutLabel: 'day-blocks computation',
      );
      expect(result.values, {
        'absent': null,
        'measured': 0,
        'trace': [1, null, 3],
      });
      expect(result.window, (100, 200));
    },
  );

  test(
    'the day-stage error name remains independent of its legacy timeout name',
    () async {
      await expectLater(
        runCancellableIsolate<int>(
          () => throw StateError('authored day-stage refusal'),
          const Duration(seconds: 5),
          label: 'day-blocks',
          timeoutLabel: 'day-blocks computation',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'legacy diagnostic',
            'day-blocks isolate failed: Bad state: authored day-stage refusal',
          ),
        ),
      );
      expect(
        await runCancellableIsolate(() => 42, const Duration(seconds: 5)),
        42,
      );
    },
  );

  test(
    'the day-stage timeout retains its computation label and releases the runner',
    () async {
      const timeout = Duration(milliseconds: 100);
      await expectLater(
        runCancellableIsolate<int>(
          () async {
            final alive = ReceivePort();
            await Completer<void>().future;
            alive.close();
            return 0;
          },
          timeout,
          label: 'day-blocks',
          timeoutLabel: 'day-blocks computation',
        ),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.message,
            'legacy diagnostic',
            'day-blocks computation timed out after $timeout',
          ),
        ),
      );
      expect(
        await runCancellableIsolate(() => 43, const Duration(seconds: 5)),
        43,
      );
    },
  );
}
