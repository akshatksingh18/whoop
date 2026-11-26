// Already-enabled phone state at the AppState boundary,then real native sync/SQLite.
// The band transport refuses independently;no physical radio or derivation claim.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/platform/phone_pedometer.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import '../gps/connection_lifecycle_test.dart' show LifecycleBand;
import '../support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('foreground-phone-band-failure'));
  setUp(() async {
    await resetCoverageStore();
    BandOwnership.resetForTest();
  });
  tearDownAll(LocalDb.close);
  for (final measured in [0, 17]) {
    for (final throwsConnect in [false, true]) {
      test(
        'foreground phone $measured remains authoritative after band throws=$throwsConnect and End',
        () async {
          final entered = Completer<void>(), release = Completer<void>();
          var reads = 0;
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            phoneStepsChannel,
            (call) async {
              if (call.method == 'authorized') return true;
              if (call.method == 'stepsInInterval') {
                reads++;
                if (!entered.isCompleted) {
                  entered.complete();
                  await release.future;
                }
                return measured;
              }
              return null;
            },
          );
          final band = LifecycleBand()..delay = const Duration(minutes: 5);
          band.connecting = (_) async {
            if (throwsConnect) {
              throw StateError('authored foreground connect refusal');
            }
            return false;
          };
          await PairedDevice.save(
            'authored-phone-band',
            'Authored band',
            generation: 'gen4',
          );
          await Prefs.saveValues({
            'phone_steps': true,
            'authored-choice': 'retain',
          });
          final app = AppState.forTesting(engine: band)
            ..paired = await PairedDevice.load()
            ..phoneStepsEnabled = Prefs.getBool('phone_steps', false);
          final db = await LocalDb.instance;
          final identity = await db.query('device');
          Future<int>? sync;
          try {
            await app.openSession();
            await entered.future.timeout(const Duration(seconds: 2));
            sync = app.syncPhoneSteps(); // Join the actual foreground request.
            await app.endSession();
            expect(app.phoneStepsEnabled, true);
            expect(
              band.calls.where((s) => s.startsWith('connect:')),
              hasLength(1),
            );
            expect(band.calls, isNot(contains('sync')));
            release.complete();
            expect(await sync, PhonePedometer.routineSyncDays);
            final rows = await db.query('live_coverage');
            expect(rows, isNotEmpty);
            expect(
              rows.every((r) => r['source'] == LocalDb.kStepSourcePhone),
              true,
            );
            expect(
              rows.fold<num>(0, (n, r) => n + (r['steps'] as num)),
              measured * reads,
            );
            expect(app.phoneStepsLastTotal, measured * reads);
            expect(app.isConnected, false);
            expect(app.isPaired, true);
            expect(await db.query('device'), identity);
            expect(Prefs.getBool('phone_steps', false), true);
            expect(Prefs.getString('authored-choice', ''), 'retain');
            expect(await db.query('decoded_onehz'), isEmpty);
            expect(await db.query('day_result'), isEmpty);
            expect(await LocalDb.computeJobs(), isEmpty);
          } finally {
            if (!release.isCompleted) release.complete();
            await sync;
            app.dispose();
            await Future<void>.delayed(const Duration(milliseconds: 40));
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              phoneStepsChannel,
              null,
            );
            BandOwnership.resetForTest();
          }
        },
      );
    }
  }
}
