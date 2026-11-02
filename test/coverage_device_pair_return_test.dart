// Existing Devices -> RePair route. Only the pairing outcome is substituted;
// no native permission, scan, peripheral or restoration claim is made.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/onboarding/pairing.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class PairOutcome extends AppState {
  PairOutcome() : super.forTesting();
  bool pairingAccepted = false;
  @override
  bool get isPaired => pairingAccepted;
  void acceptPairing() {
    pairingAccepted = true;
    notifyListeners();
  }
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('device-pair-return');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  late PairOutcome app;
  setUp(() => app = PairOutcome());
  tearDown(() => app.dispose());
  Future<void> open(WidgetTester t) async {
    await localizedPage(t, const MyDevices(), app: app, push: true);
    await t.tap(find.text('Pair a band'));
    await t.pumpAndSettle();
    expect(find.byType(RePair), findsOneWidget);
    expect(find.byType(PairingScreen), findsOneWidget);
  }

  testWidgets(
    'pairing Skip returns to the same Devices page and keeps saved measurements',
    (t) async {
      await LocalDb.putMetricSeriesValue('2021-04-06', 'steps', 1234);
      final db = await LocalDb.instance;
      final before = await db.query('metric_series');
      await open(t);
      t.widget<PairingView>(find.byType(PairingView)).onSkip!();
      await t.pumpAndSettle();
      expect(find.byType(RePair), findsNothing);
      expect(find.byType(MyDevices), findsOneWidget);
      expect(find.text('Closed test page'), findsNothing);
      expect(await t.runAsync(() => db.query('metric_series')), before);
      expect(app.isPaired, false);
    },
  );

  testWidgets(
    'pairing success pops the repair route once and leaves its parent intact',
    (t) async {
      await open(t);
      app.acceptPairing();
      await t.pumpAndSettle();
      expect(find.byType(RePair), findsNothing);
      expect(find.byType(MyDevices), findsOneWidget);
      expect(find.text('Closed test page'), findsNothing);
      // Later revisions must not retain RePair's provider subscription or pop
      // Devices. The underlying route still belongs to its original caller.
      app.notifyListeners();
      await t.pumpAndSettle();
      expect(find.byType(MyDevices), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'an already paired repair request returns without opening another gate',
    (t) async {
      app.pairingAccepted = true;
      await localizedPage(t, const MyDevices(), app: app, push: true);
      Navigator.of(
        t.element(find.byType(MyDevices)),
      ).push<void>(MaterialPageRoute<void>(builder: (_) => const RePair()));
      await t.pumpAndSettle();
      expect(find.byType(RePair), findsNothing);
      expect(find.byType(MyDevices), findsOneWidget);
      expect(find.text('Closed test page'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
