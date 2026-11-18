// Active Lift recovery: durable skipped links, refused sets and restored rest expiry.
// Authored SQLite/preferences; only native notification/haptic boundaries are substituted.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/ui2/activity/lift_log_ui.dart';
import 'coverage_deep_lift_test.dart' show action, field, ioFrame;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final haptics = <Object?>[];
  final notifications = NotificationService.instance;
  const id = 'authored-lift-recovery';
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-rest-isolated-expiry');
  });
  setUp(() async {
    await resetCoverageStore();
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
    notifications.debugRequestPermission = () async => false;
    notifications.debugProbePermission = () async => false;
    notifications.debugCancel = (_) async {};
    notifications.invalidatePermissionCache();
    await RestTimer.setDefault(0);
  });
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_lift_refusal',
    );
    await RestTimer.skip();
    notifications.debugRequestPermission = null;
    notifications.debugProbePermission = null;
    notifications.debugCancel = null;
    notifications.invalidatePermissionCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  tearDownAll(LocalDb.close);

  Future<LiftWorkout> seed(LiftLoadMode mode) async {
    final w = LiftWorkout(sessionId: id, startedAt: DateTime.now());
    w.addExercise(
      name: 'Authored press',
      loadMode: mode,
      equipmentNote: 'Authored setup',
    );
    await LiftLogDb.save(w);
    return w;
  }

  Future<void> open(WidgetTester t, double scale) => localizedPage(
    t,
    const Scaffold(
      body: SingleChildScrollView(child: LiftLivePanel(sessionId: id)),
    ),
    scale: scale,
  );

  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'restored near-expiry rest fires once without changing sets at ${scale}x',
      (t) async {
        final w = await seed(LiftLoadMode.total);
        // A durable deadline represents returning near the end of an ordinary rest.
        // No private timer/state mutation or shortened rest choice is introduced.
        await Prefs.saveValues({
          'lift.rest.deadline': DateTime.now()
              .add(const Duration(seconds: 3))
              .millisecondsSinceEpoch,
        });
        await open(t, scale);
        final skip = action('Skip rest');
        expect(skip, findsOneWidget);
        final before = haptics
            .where((x) => x == 'HapticFeedbackType.mediumImpact')
            .length;
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 3200)),
        );
        await t.pump(const Duration(seconds: 1));
        expect(
          haptics.where((x) => x == 'HapticFeedbackType.mediumImpact').length,
          before + 1,
        );
        await t.pump(const Duration(seconds: 2));
        expect(
          haptics.where((x) => x == 'HapticFeedbackType.mediumImpact').length,
          before + 1,
        );
        expect(await t.runAsync(RestTimer.deadline), isNull);
        expect(skip, findsNothing);
        expect(
          (await t.runAsync(() => LiftLogDb.forSession(id)))!.toJson(),
          w.toJson(),
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final scale in [1.0, 3.1]) {
    testWidgets('expiry redraw retains unsaved set entries at ${scale}x', (
      t,
    ) async {
      final original = await seed(LiftLoadMode.total);
      await Prefs.saveValues({
        'lift.rest.deadline': DateTime.now()
            .add(const Duration(seconds: 5))
            .millisecondsSinceEpoch,
      });
      await open(t, scale);
      await reveal(t, find.text('Authored press'));
      await t.tap(find.text('Authored press'));
      await ioFrame(t);
      await t.enterText(field('lb total'), '23.5');
      await t.enterText(field('Reps'), '11');
      expect(await t.runAsync(RestTimer.deadline), isNotNull);
      expect(action('Skip rest'), findsOneWidget);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5200)),
      );
      await t.pump(const Duration(seconds: 1));
      expect(action('Skip rest'), findsNothing);
      expect(t.widget<TextField>(field('lb total')).controller!.text, '23.5');
      expect(t.widget<TextField>(field('Reps')).controller!.text, '11');
      expect(
        (await t.runAsync(() => LiftLogDb.forSession(id)))!.toJson(),
        original.toJson(),
      );
      expect(await t.runAsync(RestTimer.deadline), isNull);
      expect(t.takeException(), isNull);
    });
  }
}
