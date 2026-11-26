// My sources keeps each confirmed band tied to its own calibration disclosure.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';

import '../screens/body_history_actions_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('source-family-route');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final family in ['gen4', 'gen5']) {
    testWidgets(
      'My sources opens the original $family row with its own disclosure',
      (t) async {
        const id = 'authored-device-family';
        final app = AppState.forTesting()
          ..paired = PairedDevice(id, null, generation: family);
        addTearDown(app.dispose);
        app.device.generation = family;
        await t.runAsync(() => PairedDevice.save(id, null, generation: family));

        await localizedPage(t, const MyDevices(), app: app, push: true);
        final rows = find.byType(SourceRow);
        expect(
          t
              .widget<MyDevicesView>(find.byType(MyDevicesView))
              .sources
              .where((item) => item.isBand),
          hasLength(1),
        );
        await reveal(t, rows.first);
        await t.tap(rows.first);
        await flush(t);
        final view = t.widget<DeviceDetailView>(find.byType(DeviceDetailView));
        expect(view.s.family, family);
        expect(
          calibrationDisclosure(view.s)?.$1,
          family == 'gen5' ? 'WHOOP 5' : 'WHOOP 4',
        );

        Navigator.of(t.element(find.byType(DeviceDetail))).pop();
        await flush(t);
        expect(find.byType(MyDevices), findsOneWidget);
        expect((await t.runAsync(PairedDevice.load))?.remoteId, id);
        expect((await t.runAsync(PairedDevice.load))?.generation, family);
        expect(app.isConnected, isFalse);
      },
    );
  }
}
