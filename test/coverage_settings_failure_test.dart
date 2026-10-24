// Secondary Settings screens retain honest read/save/retry states.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/pushups.dart';
import 'package:openstrap_edge/data/calculation_store.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/screens/pushups_screen.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart';

class _ReadStore extends SharedPreferencesStorePlatform {
  var fail = true;
  @override
  Future<Map<String, Object>> getAll() async {
    if (fail) throw StateError('synthetic preference read failure');
    return {'flutter.notif_health': false};
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      true;
  @override
  Future<bool> remove(String key) async => true;
  @override
  Future<bool> clear() async => true;
}

Widget frame(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light),
  home: RepaintBoundary(key: auditCaptureKey, child: child),
);
Finder press(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
Future<void> settleIo(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> captureFailure(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('UI_CAPTURE')) return;
  t.view.physicalSize = const Size(1170, 2700);
  t.view.devicePixelRatio = 3;
  try {
    await t.pumpAndSettle();
    await captureAuditScroll(t, name, prefix: 'build100');
    t.platformDispatcher.textScaleFactorTestValue = 3.1;
    await t.pumpAndSettle();
    await captureAuditScroll(t, '${name}_large', prefix: 'build100');
  } finally {
    t.platformDispatcher.clearTextScaleFactorTestValue();
    t.view.reset();
    await t.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory(
      'build/coverage-audit/settings',
    ).create(recursive: true);
    LocalDb.dbName = '${root.absolute.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  tearDownAll(LocalDb.close);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    NotificationService.instance.debugProbePermission = () async => true;
  });
  tearDown(() => NotificationService.instance.debugProbePermission = null);

  final bodyData = ProgressData(
    weights: [],
    measures: [],
    photos: [],
    lifts: [],
    food: [],
    steps: [],
    sleepMin: [],
    recovery: [],
    sessions: [],
    baseline: '2026-01-01',
    heightCm: null,
  );
  testWidgets('Body settings do not expose defaults after a failed read', (
    t,
  ) async {
    await t.runAsync(() async {
      await db.execute('ALTER TABLE baselines RENAME TO synthetic_baselines');
    });
    try {
      await t.pumpWidget(frame(BodySettingsScreen(data: bodyData)));
      await settleIo(t);
      expect(t.takeException(), isNull);
      expect(find.text('Body settings could not load'), findsOneWidget);
      expect(find.text('Measurement day'), findsNothing);
      await captureFailure(t, 'body_settings_read_failure');
    } finally {
      await t.runAsync(() async {
        await db.execute('ALTER TABLE synthetic_baselines RENAME TO baselines');
      });
    }
    await t.tap(find.text('Retry'));
    await settleIo(t);
    expect(find.text('Measurement day'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('a refused journey start retains its previous date and retries', (
    t,
  ) async {
    await t.runAsync(
      () => CalculationStore.write(ProgressData.baselineKey, '2026-01-01'),
    );
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: buildTheme(Brightness.light),
        home: BodySettingsScreen(data: bodyData),
      ),
    );
    await settleIo(t);
    await t.scrollUntilVisible(find.text('Journey start'), 300);
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await db.execute(
        "CREATE TRIGGER synthetic_settings_refusal BEFORE INSERT ON baselines BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
      );
    });
    try {
      await t.tap(find.text('Journey start'));
      await t.pumpAndSettle();
      nav.currentState!.pop(DateTime(2026, 1, 2));
      await settleIo(t);
      expect(t.takeException(), isNull);
      expect(
        find.text('Journey start was not saved. Try again.'),
        findsOneWidget,
      );
      expect(
        await t.runAsync(() => CalculationStore.read(ProgressData.baselineKey)),
        '2026-01-01',
      );
    } finally {
      await t.runAsync(() async {
        await db.execute('DROP TRIGGER synthetic_settings_refusal');
      });
    }
    await t.tap(find.text('Journey start'));
    await t.pumpAndSettle();
    nav.currentState!.pop(DateTime(2026, 1, 2));
    await settleIo(t);
    expect(
      await t.runAsync(() => CalculationStore.read(ProgressData.baselineKey)),
      '2026-01-02',
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'notification settings read failure has Retry and no invented switches',
    (t) async {
      final original = SharedPreferencesStorePlatform.instance,
          store = _ReadStore();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      addTearDown(() async {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
        await Prefs.ensureLoaded();
      });
      await t.pumpWidget(frame(const NotificationSettings()));
      await settleIo(t);
      expect(t.takeException(), isNull);
      expect(find.text('Notification settings could not load'), findsOneWidget);
      expect(find.byType(NotificationSettingsView), findsNothing);
      await captureFailure(t, 'notification_settings_read_failure');
      store.fail = false;
      await t.tap(find.text('Retry'));
      await settleIo(t);
      final view = t.widget<NotificationSettingsView>(
        find.byType(NotificationSettingsView),
      );
      expect(view.loaded, isTrue);
      expect(view.prefs.healthEnabled, isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Pushups settings distinguish a failed read from default values',
    (t) async {
      await t.runAsync(() async {
        await db.execute('ALTER TABLE baselines RENAME TO synthetic_baselines');
      });
      try {
        await t.pumpWidget(
          frame(const PushupSettingsScreen(canEditInterval: true)),
        );
        await settleIo(t);
        expect(t.takeException(), isNull);
        expect(find.text('Pushup settings could not load'), findsOneWidget);
        await captureFailure(t, 'pushup_settings_read_failure');
      } finally {
        await t.runAsync(() async {
          await db.execute(
            'ALTER TABLE synthetic_baselines RENAME TO baselines',
          );
        });
      }
      await t.tap(find.text('Retry'));
      await settleIo(t);
      expect(press('45 min'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final interval in [false, true]) {
    testWidgets(
      'Pushups ${interval ? 'interval' : 'goal'} refusal keeps its value and can retry',
      (t) async {
        await t.runAsync(() async {
          await PushupDb.setGoal(4);
          await PushupDb.setInterval(45);
        });
        await t.pumpWidget(
          frame(const PushupSettingsScreen(canEditInterval: true)),
        );
        await settleIo(t);
        await t.runAsync(() async {
          await db.execute(
            "CREATE TRIGGER synthetic_settings_refusal BEFORE INSERT ON baselines BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
          );
        });
        try {
          await t.tap(press(interval ? '60 min' : '8 sets'));
          await settleIo(t);
          expect(t.takeException(), isNull);
          expect(
            find.text('That setting was not saved. Try again.'),
            findsOneWidget,
          );
          expect(
            t.widget<Pressable>(press(interval ? '45 min' : '4 sets')).selected,
            isTrue,
          );
        } finally {
          await t.runAsync(() async {
            await db.execute('DROP TRIGGER synthetic_settings_refusal');
          });
        }
        await t.tap(press(interval ? '60 min' : '8 sets'));
        await settleIo(t);
        expect(
          t.widget<Pressable>(press(interval ? '60 min' : '8 sets')).selected,
          isTrue,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
