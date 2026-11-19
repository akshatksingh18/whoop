// Native phone sync -> actual source list -> phone detail,with retained measured data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/platform/phone_pedometer.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('phone-source-detail-route', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final measured in [0, 5]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'native phone source measured=$measured at ${scale}x keeps its actual detail and saved coverage',
        (t) async {
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            phoneStepsChannel,
            (call) async {
              if (call.method == 'authorized') return true;
              if (call.method == 'stepsInInterval') return measured;
              return null;
            },
          );
          final app = AppState.forTesting()..phoneStepsEnabled = true;
          try {
            expect(await t.runAsync(() => app.syncPhoneSteps(days: 1)), 1);
            final db = (await t.runAsync(() => LocalDb.instance))!;
            final saved = (await t.runAsync(() => db.query('live_coverage')))!;
            expect(saved, isNotEmpty);
            expect(app.phoneStepsLastSyncedDays, 1);
            final source = liveSources(app).single;
            expect(source.isBand, false);
            expect(source.tier, SourceTier.phone);
            expect(source.connected, measured > 0);
            await localizedPage(t, const MyDevices(), app: app, scale: scale);
            final row = find.byType(SourceRow);
            expect(row, findsOneWidget);
            await reveal(t, row);
            await t.tap(row);
            await t.pumpAndSettle();
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            expect(find.byType(DeviceDetail), findsOneWidget);
            final tier = find.byType(TierRow);
            await reveal(t, tier);
            expect(t.widget<TierRow>(tier).tier, SourceTier.phone);
            expect(t.widget<TierRow>(tier).filled, true);
            expect(
              find.text(
                'The phone’s own motion coprocessor. Steps and nothing else.',
              ),
              findsOneWidget,
            );
            expect(find.textContaining('Steps only'), findsOneWidget);
            expect(find.text('Forget band'), findsNothing);
            expect(app.isPaired, false);
            expect(app.engine.isConnected, false);
            expect(await t.runAsync(() => db.query('live_coverage')), saved);
            final back = find.byWidgetPredicate(
              (w) => w is Pressable && w.semanticLabel == 'Back',
            );
            await reveal(t, back);
            await t.tap(back);
            await t.pumpAndSettle();
            expect(find.byType(MyDevices), findsOneWidget);
            expect(find.byType(DeviceDetail), findsNothing);
            expect(await t.runAsync(() => db.query('live_coverage')), saved);
            expect(await t.runAsync(() => db.query('decoded_onehz')), isEmpty);
          } finally {
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              phoneStepsChannel,
              null,
            );
            app.dispose();
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
          }
        },
      );
    }
  }
}
