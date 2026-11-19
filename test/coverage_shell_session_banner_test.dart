// Shell-owned session recovery controls, with authored state and substituted stop.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/app.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/home_region.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/locale_controller.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_app_gate_contracts_test.dart' show GateApp;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class App extends GateApp {
  bool awaiting = false;
  int stopped = 0;
  @override
  bool get workoutAwaitingSave => awaiting;
  @override
  Future<void> stopWorkout() async {
    stopped++;
    activeWorkout = null;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late App app;
  late ThemeController theme;
  late LocaleController locale;
  late UnitsController units;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('shell-session-banner');
  });
  setUp(() async {
    await resetCoverageStore();
    LiveDraft.clear();
    await LiveDraft.retrySave();
    app = App()..gate = AppRoute.shell;
    app.repo = LocalRepositoryImpl(getProfileMap: () => {});
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
    locale = LocaleController.seed('en');
    units = UnitsController.withUnits();
    NotificationService.instance.debugRequestPermission = () async => false;
    NotificationService.instance.debugProbePermission = () async => false;
  });
  tearDown(() async {
    app.dispose();
    app.activeWorkout = null;
    LiveDraft.clear();
    await LiveDraft.retrySave();
    HomeRegion.onEvent = null;
    theme.dispose();
    locale.dispose();
    units.dispose();
    NotificationService.instance.debugRequestPermission = null;
    NotificationService.instance.debugProbePermission = null;
  });
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> open(WidgetTester t, String type) async {
    final start = DateTime.now().subtract(const Duration(minutes: 10));
    app.activeWorkout = LiveWorkoutState(
      startTime: start,
      targetKcal: 0,
      workoutId: 'authored-live',
      type: type,
      profile: const Profile(
        ageYears: 30,
        sex: 'f',
        heightCm: 170,
        weightKg: 70,
      ),
    );
    await LocalDb.putSession({
      'id': 'authored-live',
      'type': type,
      'start_ts': start.millisecondsSinceEpoch ~/ 1000,
      'status': 'live',
      'created_at': 1,
    });
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
    );
    await flush(t);
  }

  Finder action(String label) =>
      find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
  for (final awaiting in [false, true]) {
    testWidgets(
      'the shell exposes the ${awaiting ? 'stopped save retry' : 'running session'} when no live draft is open',
      (t) async {
        app.awaiting = awaiting;
        await open(t, 'general_workout');
        expect(action('Back to your general workout session'), findsOneWidget);
        expect(
          find.text(awaiting ? 'Stopped · retry save' : 'Session running'),
          findsOneWidget,
        );
        expect(LiveDraft.current, isNull);
      },
    );
  }
  testWidgets(
    'rapid shell resume taps open only the session that owns the active row',
    (t) async {
      await open(t, 'general_workout');
      final back = action('Back to your general workout session');
      await t.tap(back);
      await t.tap(back, warnIfMissed: false);
      await flush(t);
      expect(find.byType(SessionDestination), findsOneWidget);
      expect(
        t.widget<SessionDestination>(find.byType(SessionDestination)).id,
        'authored-live',
      );
      expect(LiveDraft.current, isNotNull);
      Navigator.of(t.element(find.byType(SessionDestination))).pop();
      await flush(t);
      expect(app.stopped, 0);
      expect(action('Back to your general workout session'), findsOneWidget);
    },
  );
  testWidgets(
    'a retained unknown activity resumes with its exact identity and no invented MET',
    (t) async {
      await open(t, 'authored-retired-type');
      final resume = action('Back to your authored-retired-type session');
      expect(resume, findsOneWidget);
      await t.tap(resume);
      await flush(t);
      expect(app.stopped, 0);
      expect(app.activeWorkout, isNotNull);
      expect(LiveDraft.current!.activityKey, 'authored-retired-type');
      expect(t.widget<LiveMeasured>(find.byType(LiveMeasured)).a.met, isNull);
      expect(app.activeWorkout!.type, 'authored-retired-type');
    },
  );
}
