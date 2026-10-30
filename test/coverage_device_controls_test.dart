// Device detail validates explicit names and reports command/pairing refusals.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/profile/profile.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class DeviceApp extends AppState {
  DeviceApp() : super.forTesting() {
    engine.state.generation = 'whoop4';
    engine.state.batteryPct = 70;
  }
  final names = <String>[];
  bool refuse = false;
  Completer<void>? renameWait;
  int buzzes = 0, unpairs = 0;
  @override
  bool get isConnected => true;
  @override
  bool get isPaired => true;
  @override
  Future<void> renameStrap(String name) async {
    names.add(name);
    await renameWait?.future;
    if (refuse) throw StateError('synthetic rename refusal');
  }

  @override
  Future<bool> buzzBand() async {
    buzzes++;
    return !refuse;
  }

  @override
  Future<void> unpair() async {
    unpairs++;
    if (refuse) throw StateError('synthetic unpair refusal');
  }
}

const source = HealthSource(
  name: 'Synthetic band',
  kind: 'Wrist optical',
  tier: SourceTier.wristOptical,
  icon: LucideIcons.watch,
  isBand: true,
  family: 'whoop4',
  connected: true,
);
void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('device-controls');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<void> row(WidgetTester t, String title) async {
    final f = find.byWidgetPredicate((w) => w is SetRow && w.title == title);
    await reveal(t, f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  for (final refused in [false, true]) {
    testWidgets(
      'COV-44 actual device rename validates draft and reports write $refused',
      (t) async {
        final app = DeviceApp()..refuse = refused;
        addTearDown(app.dispose);
        await localizedPage(t, const DeviceDetail(source), app: app);
        await row(t, 'Name');
        expect(find.text('Name this band'), findsOneWidget);
        await t.enterText(find.byType(TextField), ' ');
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(find.text('Give it a name'), findsOneWidget);
        expect(app.names, isEmpty);
        await t.enterText(find.byType(TextField), '🚲');
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(app.names, isEmpty);
        await t.enterText(find.byType(TextField), 'Synthetic owner');
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(app.names, ['Synthetic owner']);
        expect(
          find.textContaining(
            refused ? 'Could not rename' : 'Renamed to Synthetic owner',
          ),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      'COV-44 actual device buzz reports transport acknowledgement $refused',
      (t) async {
        final app = DeviceApp()..refuse = refused;
        addTearDown(app.dispose);
        await localizedPage(t, const DeviceDetail(source), app: app);
        await row(t, 'Buzz the band');
        expect(app.buzzes, 1);
        expect(
          find.textContaining(refused ? 'Could not send' : 'Buzz command sent'),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'COV-44 forgetting cancellation sends no command and a refusal keeps page retryable',
    (t) async {
      final app = DeviceApp()..refuse = true;
      addTearDown(app.dispose);
      await localizedPage(t, const DeviceDetail(source), app: app, push: true);
      await row(t, 'Forget this band');
      await t.tap(find.text('Keep it paired'));
      await t.pumpAndSettle();
      expect(app.unpairs, 0);
      await row(t, 'Forget this band');
      await t.tap(find.text('Forget it'));
      await t.pumpAndSettle();
      expect(app.unpairs, 1);
      expect(
        find.textContaining('forgetting it did not finish'),
        findsOneWidget,
      );
      expect(find.byType(DeviceDetail), findsOneWidget);
    },
  );
  testWidgets('COV-44 band-name validation keeps an invalid draft local', (
    t,
  ) async {
    final app = DeviceApp();
    addTearDown(app.dispose);
    await localizedPage(t, const DeviceDetail(source), app: app);
    await row(t, 'Name');
    await t.enterText(find.byType(TextField), ' ');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Give it a name'), findsOneWidget);
    expect(app.names, isEmpty);
    await t.enterText(find.byType(TextField), '🚲');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(app.names, isEmpty);
    // Replacing the whole host must also dispose an invalid draft safely.
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(app.names, isEmpty);
  });
  testWidgets('COV-46 cancel and barrier dismissal reopen a fresh name draft', (
    t,
  ) async {
    final app = DeviceApp();
    addTearDown(app.dispose);
    await localizedPage(t, const DeviceDetail(source), app: app);
    for (final cancel in [true, false]) {
      await row(t, 'Name');
      await t.enterText(find.byType(TextField), 'Unsaved draft');
      if (cancel) {
        await t.tap(find.text('Cancel'));
      } else {
        await t.tapAt(const Offset(5, 5));
      }
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(app.names, isEmpty);
    }
    await row(t, 'Name');
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'Your band', // Live state overrides the stale source-list name.
    );
    await t.enterText(find.byType(TextField), '  Retry name  ');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(app.names, ['Retry name']);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'COV-46 refused rename can reopen and retry without a stale error',
    (t) async {
      final app = DeviceApp()..refuse = true;
      addTearDown(app.dispose);
      await localizedPage(t, const DeviceDetail(source), app: app);
      for (final name in ['First name', 'Second name']) {
        await row(t, 'Name');
        await t.enterText(find.byType(TextField), name);
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        app.refuse = false;
      }
      expect(app.names, ['First name', 'Second name']);
    },
  );
  for (final refused in [false, true]) {
    testWidgets(
      'COV-46 rename completion after host disposal $refused is safe',
      (t) async {
        final app = DeviceApp()..refuse = refused;
        final release = Completer<void>();
        app.renameWait = release;
        addTearDown(app.dispose);
        await localizedPage(t, const DeviceDetail(source), app: app);
        await row(t, 'Name');
        await t.enterText(find.byType(TextField), 'Synthetic owner');
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(app.names, ['Synthetic owner']);
        await t.pumpWidget(const SizedBox());
        release.complete();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }
}
