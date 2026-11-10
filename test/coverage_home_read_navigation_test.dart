// Real Today readers/navigation with authored envelopes and substituted live state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/models/metric.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/activity/day_strain.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/screens/day_timeline.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/screens/day_steps.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class App extends AppState {
  App() : super.forTesting();
  int pulls = 0;
  @override
  Future<String?> pullRefresh({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    pulls++;
    return 'Synthetic refresh completed';
  }

  @override
  int? get liveHr => 123;
  @override
  DateTime? get lastRecordAt => DateTime(2021, 4, 6, 8);
}

class Reader extends LocalRepositoryImpl {
  Reader() : super(getProfileMap: () => {});
  bool refuse = true;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> getToday() async {
    reads++;
    if (refuse) throw StateError('Synthetic day read refusal');
    return {
      'status': {'today_day': todayLabel()},
      'daily': {},
      'sleep': {},
    };
  }
}

HomeData complete() => HomeData(
  dayId: todayLabel(),
  readiness: const Metric(value: 75, confidence: 1),
  sleepMin: const Metric(value: 420, confidence: 1),
  sleepNeedMin: const Metric(value: 480, confidence: 1),
  strain: const Metric(value: 8, confidence: 1),
  steps: const Metric(value: 5000, confidence: 1),
  proteinToday: 70,
  proteinTarget: 100,
  kcalTarget: 2000,
  recentHrFailed: true,
  graphFailed: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late App app;
  late ThemeController theme;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('home-read-navigation');
  });
  setUp(() async {
    await resetCoverageStore();
    app = App();
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
  });
  tearDown(() {
    app.dispose();
    theme.dispose();
  });
  tearDownAll(LocalDb.close);
  testWidgets(
    'a refused Today read reports Retry and later reads the same stored day',
    (t) async {
      final repo = Reader();
      app.repo = repo;
      await localizedPage(
        t,
        const Scaffold(body: HomeScreen()),
        app: app,
        themeController: theme,
        settle: false,
      );
      await io(t);
      expect(find.text('Today could not be read'), findsOneWidget);
      repo.refuse = false;
      final failure = find.byWidgetPredicate(
        (w) => w is StatusCard && w.what == 'Today could not be read',
      );
      t.widget<StatusCard>(failure).onFix!();
      await io(t);
      expect(repo.reads, 2);
      expect(find.text('Today could not be read'), findsNothing);
      expect(find.text('Nothing derived yet'), findsOneWidget);
      final refresh = find.byType(RefreshIndicator).first;
      await invokeControl(t, t.widget<RefreshIndicator>(refresh).onRefresh);
      await io(t);
      expect(app.pulls, 1);
      expect(repo.reads, 3);
      expect(find.text('Synthetic refresh completed'), findsOneWidget);
    },
  );
  testWidgets(
    'Today without an available repository ends loading and can still pull refresh',
    (t) async {
      await localizedPage(
        t,
        const Scaffold(body: HomeScreen()),
        app: app,
        themeController: theme,
        settle: false,
      );
      await io(t);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Nothing derived yet'), findsOneWidget);
      await invokeControl(
        t,
        t
            .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
            .onRefresh,
      );
      expect(app.pulls, 1);
    },
  );
  testWidgets('Today detail and Food links retain their named destination', (
    t,
  ) async {
    await localizedPage(
      t,
      Scaffold(body: HomeScreen(data: complete())),
      app: app,
      themeController: theme,
    );
    for (final (label, type) in [
      ('Sleep', SleepDetail),
      ('Strain', DayStrainDetail),
      ('Steps', DayStepsDetail),
    ]) {
      final line = find.byWidgetPredicate(
        (w) => w is MetricLine && w.label == label,
      );
      await reveal(t, line);
      t.widget<MetricLine>(line).onTap!();
      await io(t);
      expect(find.byType(type), findsOneWidget);
      Navigator.of(t.element(find.byType(type))).pop();
      await io(t);
      expect(find.byType(HomeScreen), findsOneWidget);
    }
    for (final label in ['Food', 'Protein']) {
      final line = find.byWidgetPredicate(
        (w) => w is MetricLine && w.label == label,
      );
      await reveal(t, line);
      t.widget<MetricLine>(line).onTap!();
      expect(app.navRequest.value, 6);
      app.navRequest.value = 0;
    }
  });
  testWidgets(
    'recorded-data age, live pulse and low battery remain distinct, with graph retry',
    (t) async {
      app.device.batteryPct = 15;
      app.device.charging = false;
      app.insightsRebuildMessage = 'Synthetic retained-insights warning';
      await localizedPage(
        t,
        Scaffold(body: HomeScreen(data: complete())),
        app: app,
        themeController: theme,
      );
      var text = (await readPage(t)).join(' ');
      expect(text, contains('15%'));
      expect(text, contains('Band data Apr 6'));
      expect(text, contains('123'));
      expect(text, contains('bpm now'));
      expect(text, contains('Synthetic retained-insights warning'));
      expect(text, contains('Heart rate could not refresh'));
      final retry = find.byTooltip('Retry heart rate');
      await reveal(t, retry);
      await t.tap(retry);
      await io(t);
      expect(t.takeException(), isNull);
      final hour = find.text('1 hour');
      await reveal(t, hour);
      await t.tap(hour);
      await t.pumpAndSettle();
      text = (await readPage(t)).join(' ');
      expect(text, contains('No recorded HR in the last hour'));
      final heart = find.byWidgetPredicate(
        (w) =>
            w is Surface &&
            (w.semanticLabel?.startsWith('Heart rate') ?? false),
      );
      await reveal(t, heart);
      t.widget<Surface>(heart).onTap!();
      await io(t);
      expect(find.byType(DayTimelineScreen), findsOneWidget);
    },
  );
}
