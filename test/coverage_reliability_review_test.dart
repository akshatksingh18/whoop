// Full-page synthetic evidence for the authorized reliability fixes. No new design.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/profile/profile.dart';
import 'coverage_data_export_handoff_test.dart' show Keychain;
import 'coverage_device_controls_test.dart' show DeviceApp, source;
import 'support/audit_visual.dart';
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const before = bool.fromEnvironment('REPAIR_REVIEW_BEFORE');
const stage = before ? 'before' : 'after';
void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('reliability-review');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<void> open(
    WidgetTester t,
    Widget child,
    AppState app,
    double scale,
  ) async {
    await localizedPage(t, child, app: app, scale: scale, capture: true);
    t.view.physicalSize = scale == 1
        ? const Size(390, 844)
        : const Size(430, 932);
    await t.pumpAndSettle();
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('COV-46 complete backup refusal review $stage at $scale', (
      t,
    ) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final oldKeys = FlutterSecureStoragePlatform.instance;
      final keys = Keychain()..refuse = true;
      FlutterSecureStoragePlatform.instance = keys;
      addTearDown(() => FlutterSecureStoragePlatform.instance = oldKeys);
      await open(t, const DataScreen(), app, scale);
      await reveal(t, find.text('Backup passphrase'));
      final row = t.widget<SetRow>(
        find.ancestor(
          of: find.text('Backup passphrase'),
          matching: find.byType(SetRow),
        ),
      );
      Future<dynamic>? action;
      await t.runAsync(() async {
        action = (row.onTap as dynamic)();
      });
      await t.pump(const Duration(milliseconds: 300));
      for (final field in find.byType(TextField).evaluate().toList()) {
        await t.enterText(
          find.byWidget(field.widget),
          'synthetic review passphrase',
        );
      }
      await t.ensureVisible(find.text('Encrypt'));
      await t.tap(find.text('Encrypt'));
      await t.runAsync(() async => await action);
      await t.pumpAndSettle();
      final text = (await readPage(t)).join(' ');
      expect(text.contains('could not be saved'), !before);
      expect(keys.value, isNull);
      await captureAuditScroll(
        t,
        'backup_refusal_${scale}x',
        prefix: 'cov46_$stage',
        scrollable: find.byType(Scrollable).first,
      );
    });
    testWidgets('COV-46 complete name dialog review $stage at $scale', (
      t,
    ) async {
      final app = DeviceApp();
      addTearDown(app.dispose);
      await open(t, const DeviceDetail(source), app, scale);
      await captureAuditScroll(
        t,
        'device_host_${scale}x',
        prefix: 'cov46_$stage',
        scrollable: find.byType(Scrollable).first,
      );
      final row = find.byWidgetPredicate(
        (w) => w is SetRow && w.title == 'Name',
      );
      await reveal(t, row);
      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.text('Name this band'), findsOneWidget);
      await captureAuditScroll(
        t,
        'name_dialog_${scale}x',
        prefix: 'cov46_$stage',
        scrollable: find.byType(Scrollable).first,
      );
      // Before evidence leaves the known-defective dialog mounted. Its retained
      // Save regressions are separate; the review does not ignore exceptions.
      if (!before) {
        await t.enterText(find.byType(TextField), 'Synthetic owner');
        await t.ensureVisible(find.text('Save'));
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(app.names, ['Synthetic owner']);
      }
    });
  }
}
