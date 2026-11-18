// Actual root gate callbacks and native profile refusal;no radio or heavy derivation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/app.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/locale_controller.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/onboarding/pairing.dart';
import 'package:whoop_companion/ui2/onboarding/profile_setup.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_step_tail_recovery_test.dart' show CheckpointStore;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final nativeStore = SharedPreferencesStorePlatform.instance;
  final notifications = NotificationService.instance;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('root-onboarding-profile', fresh: true);
  });
  setUp(() async {
    await resetCoverageStore();
    notifications.debugProbePermission = () async => false;
    notifications.debugRequestPermission = () async => false;
    notifications.debugCancel = (_) async {};
    notifications.invalidatePermissionCache();
  });
  tearDown(() async {
    binding.platformDispatcher.clearTextScaleFactorTestValue();
    notifications.debugProbePermission = null;
    notifications.debugRequestPermission = null;
    notifications.debugCancel = null;
    notifications.invalidatePermissionCache();
    SharedPreferencesStorePlatform.instance = nativeStore;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  tearDownAll(LocalDb.close);
  for (final refusal in ['false', 'throws']) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'root onboarding preserves bypass/profile state across $refusal native save at ${scale}x',
        (t) async {
          binding.platformDispatcher.textScaleFactorTestValue = scale;
          final store = CheckpointStore(targetKey: 'local_profile_json')
            ..values['flutter.authored-unrelated'] = 'keep';
          SharedPreferencesStorePlatform.instance = store;
          SharedPreferences.resetStatic();
          await Prefs.ensureLoaded();
          final app = AppState.forTesting()..initialized = true;
          app.repo = LocalRepositoryImpl(
            getProfileMap: () => app.user,
            saveProfileFields: app.updateProfile,
          );
          final theme = ThemeController.seed(
            AppThemeChoice.light,
            Brightness.light,
          );
          final locale = LocaleController.seed('en');
          final units = UnitsController.withUnits();
          addTearDown(app.dispose);
          addTearDown(theme.dispose);
          addTearDown(locale.dispose);
          addTearDown(units.dispose);
          try {
            await localizedPage(
              t,
              MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: theme),
                  ChangeNotifierProvider.value(value: locale),
                  ChangeNotifierProvider.value(value: units),
                ],
                child: const WhoopApp(),
              ),
              app: app,
              scale: scale,
            );
            Future<void> press(String label) async {
              final button = find.byWidgetPredicate(
                (w) => w is BigButton && w.label == label,
              );
              await reveal(t, button);
              await t.runAsync(() async {
                final dynamic callback = t.widget<BigButton>(button).onTap;
                await callback();
              });
              // Home starts real asynchronous reads;drive both clocks instead
              // of advancing the five-minute refresh timer while I/O is held.
              for (var i = 0; i < 30; i++) {
                await t.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 10)),
                );
                await t.pump(const Duration(milliseconds: 20));
              }
              expect(t.takeException(), isNull);
            }

            expect(app.route, AppRoute.welcome);
            await press('Set up my band');
            expect(app.route, AppRoute.pairing);
            expect(find.byType(PairingScreen), findsOneWidget);
            await press('Skip for now');
            expect(OnboardingBypass.pairingSkipped, true);
            expect(find.byType(ProfileSetupScreen), findsOneWidget);
            expect(
              MediaQuery.textScalerOf(
                t.element(find.byType(ProfileSetupScreen)),
              ).scale(10),
              closeTo(10 * scale, .001),
            );
            await reveal(t, find.text('Female'));
            await t.tap(find.text('Female'));
            await t.pumpAndSettle();
            final before = app.user;
            store.refuseWrite = refusal;
            await press('Continue');
            expect(
              find.text(
                'Profile could not save. Check age, height and weight, then retry.',
              ),
              findsOneWidget,
            );
            expect(find.byType(ProfileSetupScreen), findsOneWidget);
            expect(app.user, before);
            expect(OnboardingBypass.profileSeen, false);
            expect(Prefs.getBool('onboard.completed', false), false);
            expect(store.values['flutter.local_profile_json'], isNull);
            store.refuseWrite = null;
            await press('Continue');
            expect(OnboardingBypass.profileSeen, true);
            expect(Prefs.getBool('onboard.completed', false), true);
            expect(find.byType(ProfileSetupScreen), findsNothing);
            expect(app.isPaired, false);
            expect(app.user!['sex'], 'f');
            expect(app.profileComplete, false);
            expect(store.values['flutter.authored-unrelated'], 'keep');
            final db = (await t.runAsync(() => LocalDb.instance))!;
            expect((await t.runAsync(() => db.query('day_result')))!, isEmpty);
            expect(
              (await t.runAsync(() => db.query('decoded_onehz')))!,
              isEmpty,
            );
          } finally {
            app.stopForegroundRefresh();
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
          }
        },
      );
    }
  }
}
