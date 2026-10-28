// Retained Trends choices and read recovery, authored evidence only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/compute/findings.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/findings_log.dart';
import 'package:whoop_companion/ui2/screens/health_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_home_read_navigation_test.dart' show App;
import 'coverage_settings_controls_test.dart' show Store;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class Reader extends LocalRepositoryImpl {
  Reader() : super(getProfileMap: () => {});
  bool refuse = true;
  @override
  Future<Map<String, dynamic>> getToday() async {
    if (refuse) throw StateError('Authored Trends refusal');
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late App app;
  late ThemeController theme;
  late SharedPreferencesStorePlatform previousStore;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('trends-owned-controls');
  });
  setUp(() async {
    previousStore = SharedPreferencesStorePlatform.instance;
    await resetCoverageStore();
    app = App();
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
  });
  tearDown(() async {
    app.dispose();
    theme.dispose();
    SharedPreferencesStorePlatform.instance = previousStore;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  HealthData data({
    Map<String, dynamic> today = const {},
    List<Finding> findings = const [],
  }) {
    final now = DateTime.now();
    return HealthData(
      today: today,
      findings: findings,
      charts: {
        for (final (key, value) in [
          ('recovery', 70.0),
          ('steps', 5000.0),
          ('sleep', 420.0),
        ])
          key: [
            for (var i = 0; i < 7; i++)
              (
                t:
                    DateTime(
                      now.year,
                      now.month,
                      now.day - i,
                      12,
                    ).millisecondsSinceEpoch ~/
                    1000,
                v: value,
              ),
          ],
      },
    );
  }

  Future<void> open(WidgetTester t, HealthScreen page) async {
    await localizedPage(
      t,
      Scaffold(body: page),
      app: app,
      themeController: theme,
    );
    await flush(t);
  }

  Future<void> tap(WidgetTester t, String label) async {
    await reveal(t, find.text(label));
    await t.tap(find.text(label));
    await flush(t);
  }

  Finder pin(String label) =>
      find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
  testWidgets(
    'hidden breathing pins can be freed and the remaining pins persist',
    (t) async {
      final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
      await prefs.setStringList('trends.pinned', [
        'resp_rate',
        'steps',
        'sleep',
      ]);
      await open(t, HealthScreen(data: data()));
      expect((await readPage(t)).join(' '), contains('Pinned'));
      await tap(t, 'Edit pins');
      await t.tap(pin('Breathing rate · not shown now, pinned'));
      await t.pumpAndSettle();
      await t.tap(pin('Recovery'));
      await t.pumpAndSettle();
      await tap(t, 'Done');
      expect(prefs.getStringList('trends.pinned'), [
        'steps',
        'sleep',
        'recovery',
      ]);
      expect(find.text('Pinned'), findsOneWidget);
    },
  );
  testWidgets('a refused pin save reports the failure and can be retried', (
    t,
  ) async {
    final store = Store()..refuse = 'flutter.trends.pinned';
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    await open(t, HealthScreen(data: data()));
    await tap(t, 'Pin favourites');
    await t.tap(pin('Steps'));
    await t.pumpAndSettle();
    await tap(t, 'Done');
    expect(find.text('Favourites were not saved. Try again.'), findsOneWidget);
    expect(store.values.containsKey('flutter.trends.pinned'), isFalse);
    store.refuse = null;
    await tap(t, 'Pin favourites');
    await t.tap(pin('Steps'));
    await t.pumpAndSettle();
    await tap(t, 'Done');
    expect(store.values['flutter.trends.pinned'], ['steps']);
  });
  testWidgets(
    'failed Trends reads retry, refresh and reset only their range on tab reselection',
    (t) async {
      final reader = Reader();
      app.repo = reader;
      await open(t, const HealthScreen(range: 1));
      expect(find.text('Trends could not be read'), findsOneWidget);
      reader.refuse = false;
      await tap(t, 'Try again');
      expect(find.text('Trends could not be read'), findsNothing);
      final tabs = find.byType(SubTabs);
      t.widget<SubTabs>(tabs).onTap(2);
      await t.pumpAndSettle();
      expect(t.widget<SubTabs>(tabs).index, 2);
      shellReselect.value = (ShellDomain.health, shellReselect.value.$2 + 1);
      await t.pumpAndSettle();
      expect(t.widget<SubTabs>(tabs).index, 1);
      await invokeControl(
        t,
        t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh,
      );
      await flush(t);
      expect(app.pulls, 1);
    },
  );
  for (final state in ['yellow', 'red']) {
    testWidgets(
      'the $state illness watch retains dated uncertainty and the full observation log',
      (t) async {
        final findings = [const Finding(FindingKind.illness, '2021-04-06')];
        await open(
          t,
          HealthScreen(
            data: data(
              today: {
                'illness': {'state': state, 'date': '2021-04-06'},
              },
              findings: findings,
            ),
          ),
        );
        final text = (await readPage(t)).join(' ');
        expect(
          text,
          contains('Your sleeping heart rate has been running high.'),
        );
        expect(text, contains('Worth noting if it continues'));
        expect(
          text,
          contains(
            state == 'red'
                ? 'Several nights in a row'
                : 'Tuesday, 6 April was above your normal',
          ),
        );
        await tap(t, 'See all');
        expect(
          t.widget<FindingsLog>(find.byType(FindingsLog)).findings,
          findings,
        );
      },
    );
  }
  testWidgets(
    'a stored finding has a retained log doorway when no illness watch is active',
    (t) async {
      final findings = [
        const Finding(FindingKind.rhrShift, '2021-04-06', risen: false),
      ];
      await open(t, HealthScreen(data: data(findings: findings)));
      await tap(t, findings.single.title);
      expect(
        t.widget<FindingsLog>(find.byType(FindingsLog)).findings,
        findings,
      );
    },
  );
}
