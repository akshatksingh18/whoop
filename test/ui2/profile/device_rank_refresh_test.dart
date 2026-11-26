// Source ranking inside one tier, and the band page re-reading its forecast
// when the band reports a new charge. Authored sources only.
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

HealthSource _band({
  double? battery,
  DateTime? at,
  String name = 'Band',
  bool charging = false,
  String family = 'gen4',
}) => HealthSource(
  name: name,
  kind: 'Wrist optical',
  tier: SourceTier.wristOptical,
  icon: LucideIcons.watch,
  isBand: true,
  family: family,
  charging: charging,
  batteryPct: battery,
  lastData: at,
);

void main() {
  test('inside a tier a source with data outranks one without', () {
    final withData = _band(name: 'Z with data', at: DateTime(2021, 4, 6));
    final without = _band(name: 'A without');
    for (final order in [
      [withData, without],
      [without, withData],
    ]) {
      expect(rankSources(order).first.name, 'Z with data');
    }
  });

  group('band page', () {
    setUpAll(() async {
      await loadAuditFonts();
      await coverageStore('device-rank-refresh');
    });
    setUp(resetCoverageStore);
    tearDownAll(LocalDb.close);

    testWidgets('a new battery reading re-reads the forecast', (t) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await localizedPage(t, DeviceDetail(_band(battery: 70)), app: app);
      expect(find.textContaining('70%'), findsWidgets);
      await localizedPage(t, DeviceDetail(_band(battery: 55)), app: app);
      expect(find.textContaining('55%'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('a charge or family change at the same battery re-reads it', (
      t,
    ) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await localizedPage(t, DeviceDetail(_band(battery: 70)), app: app);
      expect(find.text('Charging'), findsNothing);
      // Same battery, now on the charger: the second test of the OR.
      await localizedPage(
        t,
        DeviceDetail(_band(battery: 70, charging: true)),
        app: app,
      );
      expect(find.textContaining('Charging'), findsWidgets);
      // Same battery and charge, another family: the third test.
      await localizedPage(
        t,
        DeviceDetail(_band(battery: 70, charging: true, family: 'gen5')),
        app: app,
      );
      expect(find.textContaining('70%'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  });
}
