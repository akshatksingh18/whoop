// Real lifecycle policy; only host identity and native replies are supplied.
// Dart checks do not establish native relaunch/background-budget acceptance.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'coverage_connection_lifecycle_test.dart' show LifecycleBand;
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('whoop/ble_restore');
  final calls = <MethodCall>[];
  String? reply;
  var refuse = false;
  setUpAll(() async {
    await coverageStore('ios-app-policy', fresh: true);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
      call,
    ) async {
      calls.add(call);
      if (refuse) throw PlatformException(code: 'authored-state-refusal');
      return reply;
    });
  });
  setUp(() async {
    await resetCoverageStore();
    calls.clear();
    reply = null;
    refuse = false;
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
    await LocalDb.close();
  });
  for (final ios in [false, true]) {
    for (final outcome in ['background', 'active', 'absent', 'refused']) {
      test(
        'launch state ios=$ios reply=$outcome never guesses ownership',
        () async {
          reply = outcome == 'absent' || outcome == 'refused' ? null : outcome;
          refuse = outcome == 'refused';
          final app = AppState.forTesting(isIOS: ios);
          try {
            expect(
              await app.launchedInBackground(),
              ios && outcome == 'background',
            );
            expect(calls.map((c) => c.method), ios ? ['appState'] : []);
            var notices = 0;
            app.addListener(() => notices++);
            app.notifyListeners();
            app.notifyListeners();
            expect(
              notices,
              2,
              reason: 'A state query alone must not background the app',
            );
            expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          } finally {
            app.dispose();
          }
        },
      );
    }
    for (final finish in ['elapsed', 'foreground', 'disposed']) {
      testWidgets(
        'background notices ios=$ios close through $finish without stale callbacks',
        (t) async {
          final band = LifecycleBand();
          final app = AppState.forTesting(engine: band, isIOS: ios);
          var disposed = false, notices = 0;
          try {
            await app.pauseForBackground(isIOS: false);
            app.addListener(() => notices++);
            app.notifyListeners();
            app.notifyListeners();
            expect(notices, ios ? 0 : 2);
            await t.pump(const Duration(seconds: 29));
            expect(notices, ios ? 0 : 2);
            if (finish == 'disposed') {
              app.dispose();
              disposed = true;
              await t.pump(const Duration(minutes: 2));
              app.notifyListeners();
              expect(notices, ios ? 0 : 2);
            } else if (finish == 'foreground') {
              await t.runAsync(app.openSession);
              final before = notices;
              app.notifyListeners();
              expect(notices, before + 1);
              await t.pump(const Duration(seconds: 31));
              expect(
                notices,
                before + 1,
                reason: 'Foreground flush cancels the coalescing timer',
              );
            } else {
              await t.pump(const Duration(seconds: 1));
              expect(notices, ios ? 1 : 2);
              app.notifyListeners();
              await t.pump(const Duration(seconds: 30));
              expect(
                notices,
                ios ? 2 : 3,
                reason: 'A completed window permits the next notice',
              );
            }
            expect(
              await t.runAsync(
                () async => (await LocalDb.instance).query('day_result'),
              ),
              isEmpty,
            );
            expect(band.calls, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            if (!disposed) app.dispose();
          }
          final before = notices;
          await t.pump(const Duration(minutes: 2));
          expect(notices, before);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
