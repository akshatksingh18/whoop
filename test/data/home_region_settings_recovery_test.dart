// Returning from permission settings never changes the saved Home boundary.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/home_region.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';

import 'home_setup_handoff_test.dart' show action;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('whoop/home_region');
  const settings = MethodChannel('flutter.baseflow.com/geolocator');
  final messenger = binding.defaultBinaryMessenger;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('home-region-settings-recovery');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final opened in [false, true]) {
    testWidgets('Home keeps its saved boundary when Settings opens: $opened', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final native = <String>[], settingsCalls = <MethodCall>[];
      var authorized = false;
      messenger
        ..setMockMethodCallHandler(bridge, (call) async {
          native.add(call.method);
          return switch (call.method) {
            'status' => {
              'authorization': authorized ? 'always' : 'whenInUse',
              'monitoring': true,
              'monitored': true,
              'backgroundRefresh': 'available',
            },
            'monitor' => true,
            _ => null,
          };
        })
        ..setMockMethodCallHandler(settings, (call) async {
          settingsCalls.add(call);
          if (opened) authorized = true;
          return opened;
        });
      const boundary = (lat: 0.0, lon: 0.0, radius: 250.0);
      try {
        await t.runAsync(() => HomeRegion.setHome(boundary));
        native.clear();
        await localizedPage(t, const HomeSetupScreen(), push: true);
        expect(find.text('Not working'), findsOneWidget);
        await reveal(t, action('Open Settings'));
        await t.tap(action('Open Settings'));
        await t.pumpAndSettle();
        expect(settingsCalls.single.method, 'openAppSettings');
        expect(native, ['status']);
        expect(await t.runAsync(HomeRegion.boundary), boundary);

        await t.pumpWidget(const SizedBox());
        await localizedPage(t, const HomeSetupScreen(), push: true);
        expect(find.text(opened ? 'Working' : 'Not working'), findsOneWidget);
        expect(await t.runAsync(HomeRegion.boundary), boundary);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('pushup_session'),
          ),
          isEmpty,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
        messenger
          ..setMockMethodCallHandler(bridge, null)
          ..setMockMethodCallHandler(settings, null);
      }
    });
  }
}
