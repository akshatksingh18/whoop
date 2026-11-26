import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/profile/profile.dart';

import '../screens/nutrition_root_test.dart' show io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('device-forget-handoff', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  testWidgets(
    'forgetting a disconnected band returns to the root and keeps workout history',
    (t) async {
      await PairedDevice.save(
        'authored-device',
        'Authored band',
        generation: 'gen4',
      );
      await LocalDb.putSession({
        'id': 'authored-history',
        'start_ts': 1617714000,
        'type': 'running',
        'status': 'finished',
        'source': 'manual',
        'created_at': 1,
      });
      final session = await LocalDb.session('authored-history');
      final identity = await LocalDb.deviceRow();
      expect(session, isNotNull);
      expect(identity?['remote_id'], 'authored-device');
      final app = AppState.forTesting()..paired = await PairedDevice.load();
      addTearDown(app.dispose);
      await localizedPage(
        t,
        DeviceDetail(liveSources(app).single),
        app: app,
        push: true,
      );
      final forget = find.byWidgetPredicate(
        (w) => w is SetRow && w.title == 'Forget this band',
      );
      await reveal(t, forget);
      await t.tap(forget);
      await t.pumpAndSettle();
      await t.tap(find.text('Keep it paired'));
      await t.pumpAndSettle();
      expect(app.paired?.remoteId, 'authored-device');
      expect(await LocalDb.deviceRow(), identity);
      expect(find.byType(DeviceDetail), findsOneWidget);

      await reveal(t, forget);
      await t.tap(forget);
      await t.pumpAndSettle();
      await t.tap(find.text('Forget it'));
      await io(t);
      expect(app.paired, isNull);
      expect(await t.runAsync(PairedDevice.load), isNull);
      expect(find.byType(DeviceDetail), findsNothing);
      expect(find.text('Closed test page'), findsOneWidget);
      expect(await LocalDb.session('authored-history'), session);
      expect(t.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
