// Load Today through its ordinary read path, including the persisted seen-night
// marker. Authored readers and phase state do not claim sensor/OS delivery.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/profile/settings.dart';
import 'package:whoop_companion/ui2/profile/status.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_home_phases_test.dart' show PhaseApp;
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class _App extends PhaseApp {
  @override
  Future<void> refreshSigningStatus() async {}
  @override
  Future<void> refreshBackupPassphraseState() async {}
}

class _Reader extends LocalRepositoryImpl {
  _Reader() : super(getProfileMap: () => {});
  bool measured = true;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> getToday() async {
    reads++;
    return {
      'status': {'today_day': todayLabel()},
      'daily': {if (measured) 'readiness': 74},
      'sleep': {},
      if (measured) 'hrv': {'rmssd': 45, 'confidence': .8, 'tier': 'HIGH'},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _App app;
  late _Reader reader;
  late ThemeController theme;
  late UnitsController units;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('home-current-read');
  });
  setUp(() async {
    await resetCoverageStore();
    reader = _Reader();
    app = _App()..repo = reader;
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
    units = UnitsController.seed(UnitSystem.metric);
  });
  tearDown(() {
    app.dispose();
    theme.dispose();
    units.dispose();
  });
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t) async {
    await localizedPage(
      t,
      const Scaffold(body: HomeScreen()),
      app: app,
      themeController: theme,
      units: units,
      settle: false,
    );
    await io(t);
  }

  testWidgets(
    'a newly read night is marked once and keeps its data on reopening',
    (t) async {
      await open(t);
      final hero = find.byWidgetPredicate(
        (w) => w is HeroStat && w.label == 'Recovery',
      );
      expect(t.widget<HeroStat>(hero).fresh, true);
      expect(t.widget<HeroStat>(hero).value, '74');
      final saved = await t.runAsync(
        () async => (await SharedPreferences.getInstance()).getString(
          'today.seen_night',
        ),
      );
      expect(saved, todayLabel());
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await open(t);
      expect(t.widget<HeroStat>(hero).fresh, false);
      expect(t.widget<HeroStat>(hero).value, '74');
      final before = reader.reads;
      app.bumpInsights();
      await io(t);
      expect(reader.reads, greaterThan(before));
      expect(t.widget<HeroStat>(hero).fresh, false);
      expect(t.widget<HeroStat>(hero).value, '74');
    },
  );

  testWidgets(
    'a sync tap with no progress expires without inventing a completed sync',
    (t) async {
      reader.measured = false;
      await open(t);
      final empty = find.byWidgetPredicate(
        (w) => w is StatusCard && w.what == 'Nothing derived yet',
      );
      expect(empty, findsOneWidget);
      t.widget<StatusCard>(empty).onFix!();
      await t.pump(const Duration(milliseconds: 100));
      expect(app.syncCalls, 1);
      expect(find.text('Connecting to your band'), findsOneWidget);
      await t.pump(const Duration(seconds: 21));
      await t.pumpAndSettle();
      expect(find.text('Connecting to your band'), findsNothing);
      expect(empty, findsOneWidget);
      expect(app.syncCalls, 1);
      expect(app.lastRecordAt, isNull);
      expect(app.lastSynced, isNull);
    },
  );

  testWidgets(
    'both freshness doors and Settings open their existing destinations',
    (t) async {
      await open(t);
      for (final (label, destination) in [
        ('Data freshness. Opens Status', StatusScreen),
        ('Sync status. Opens Status', StatusScreen),
        ('Settings', MoreSettings),
      ]) {
        final action = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == label,
        );
        await reveal(t, action);
        t.widget<Pressable>(action).onTap!();
        await io(t);
        expect(find.byType(destination), findsOneWidget);
        Navigator.of(t.element(find.byType(destination))).pop();
        await io(t);
        expect(find.byType(HomeScreen), findsOneWidget);
      }
      expect(
        (await t.runAsync(
          () async => (await SharedPreferences.getInstance()).getString(
            'today.seen_night',
          ),
        )),
        todayLabel(),
      );
    },
  );
}
