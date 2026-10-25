// User actions -> Pushups commands -> real synthetic store and mirror.
// Notification permission is denied by a substitute; no OS delivery is claimed.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/pushups.dart';
import 'package:openstrap_edge/data/pushup_reminders.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/pushups_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

class Paths extends PathProviderPlatform {
  Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Finder action(String name) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == name);
Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 250; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 25));
    final commands = t.widgetList<Pressable>(
      find.byWidgetPredicate(
        (w) =>
            w is Pressable &&
            const [
              'Start my day',
              'Pause',
              'Resume',
              'End my day',
            ].contains(w.semanticLabel),
      ),
    );
    final busy = commands.isNotEmpty && commands.every((w) => w.onTap == null);
    if (i >= 24 &&
        !busy &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty)
      break;
  }
  expect(
    find.byType(CircularProgressIndicator),
    findsNothing,
    reason: 'Pushups read must finish before checking interactive controls',
  );
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> tap(WidgetTester t, Finder f) async {
  final list = find.byType(Scrollable).first;
  t.state<ScrollableState>(list).position.jumpTo(0);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(f, 250, scrollable: list, maxScrolls: 40);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await flush(t);
}

Future<void> command(WidgetTester t, Future<void> Function() call) async {
  var finished = false;
  Object? failure;
  call().then(
    (_) => finished = true,
    onError: (Object e) {
      failure = e;
      finished = true;
    },
  );
  for (var i = 0; i < 500 && !finished; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 25));
  }
  expect(
    finished,
    isTrue,
    reason:
        'The process-wide Pushups command must finish in its owning test clock',
  );
  if (failure != null) throw failure!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late PathProviderPlatform original;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/pushup-ui',
    ).create(recursive: true)).absolute;
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  Future<void> resetFixture() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    DayClock.install([], []);
    await LocalDb.wipeAll();
    await PushupReminders.clearInbox();
    await PushupReminders.writeMirror(null);
    NotificationService.instance.invalidatePermissionCache();
    NotificationService.instance.debugRequestPermission = () async => false;
    NotificationService.instance.debugProbePermission = () async => false;
  }

  setUp(resetFixture);
  tearDown(() => db.execute('DROP TRIGGER IF EXISTS synthetic_pushup_refusal'));
  tearDownAll(() async {
    await LocalDb.close();
    PathProviderPlatform.instance = original;
    NotificationService.instance.debugRequestPermission = null;
    NotificationService.instance.debugProbePermission = null;
  });
  Future<void> open(WidgetTester t, {Widget? page}) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: page ?? const PushupsScreen(),
      ),
    );
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await flush(t);
    });
    await flush(t);
  }

  Future<PushupStatus> status(WidgetTester t) async =>
      (await t.runAsync(Pushups.status))!;
  final scenarios =
      <({String name, Future<void> Function(WidgetTester) run})>[];
  void scenario(String name, Future<void> Function(WidgetTester) run) =>
      scenarios.add((name: name, run: run));
  scenario('Start, manual set, Undo, Pause and Resume retain one saved day', (
    t,
  ) async {
    await open(t);
    expect(find.text('Not started'), findsOneWidget);
    await tap(t, action('Start my day'));
    final id = (await status(t)).active!.id;
    expect(find.text('Reminders are blocked'), findsOneWidget);
    await tap(t, action('Log a set'));
    expect((await status(t)).today, 1);
    await tap(t, action('Show logged sets'));
    expect(find.textContaining('Set 1 ·'), findsOneWidget);
    await tap(t, action('Hide logged sets'));
    expect(find.textContaining('Set 1 ·'), findsNothing);
    await tap(t, action('Undo the last set'));
    expect((await status(t)).today, 0);
    await tap(t, action('Pause'));
    expect((await status(t)).active!.state, PushupState.paused);
    // Logging while paused counts a deliberate set without resuming reminders.
    await tap(t, action('Log a set'));
    expect((await status(t)).today, 1);
    expect((await status(t)).active!.state, PushupState.paused);
    await tap(t, action('Resume'));
    expect((await status(t)).active!.state, PushupState.running);
    expect((await status(t)).active!.id, id);
    expect((await status(t)).sessions, hasLength(1));
  });
  for (final operation in ['start', 'log']) {
    scenario('a refused $operation keeps the saved count and can retry', (
      t,
    ) async {
      if (operation == 'log')
        await command(t, () async {
          await Pushups.start();
        });
      await open(t);
      await t.runAsync(
        () => db.execute(
          "CREATE TRIGGER synthetic_pushup_refusal BEFORE INSERT ON pushup_session BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
        ),
      );
      final target = action(
        operation == 'start' ? 'Start my day' : 'Log a set',
      );
      await tap(t, target);
      expect((await status(t)).today, 0);
      expect(
        (await status(t)).active,
        operation == 'start' ? isNull : isNotNull,
      );
      expect(find.textContaining('synthetic refusal'), findsOneWidget);
      await t.runAsync(
        () => db.execute('DROP TRIGGER synthetic_pushup_refusal'),
      );
      await tap(t, target);
      expect((await status(t)).active, isNotNull);
      expect((await status(t)).today, operation == 'log' ? 1 : 0);
    });
  }
  for (final end in [false, true]) {
    scenario(
      'End day ${end ? 'commits and opens the dated recap' : 'can be cancelled'}',
      (t) async {
        await command(t, () async {
          await Pushups.start();
          await Pushups.done();
        });
        await open(t);
        await tap(t, action('End my day'));
        // The confirmation is not inside the page's scroll view.
        await t.tap(find.text(end ? 'End my day' : 'Not yet').last);
        await flush(t);
        if (end) {
          expect((await status(t)).active, isNull);
          expect(find.byType(PushupDayScreen), findsOneWidget);
          expect(find.text('1 set of 8'), findsOneWidget);
          expect((await status(t)).sessions.single.count, 1);
        } else {
          expect((await status(t)).active!.state, PushupState.running);
          expect(find.byType(PushupsScreen), findsOneWidget);
        }
      },
    );
  }
  scenario('settings opens with interval locked during an active day', (
    t,
  ) async {
    await command(t, () async {
      await Pushups.start();
    });
    await open(t);
    await tap(t, action('Settings'));
    expect(
      t
          .widget<PushupSettingsScreen>(find.byType(PushupSettingsScreen))
          .canEditInterval,
      isFalse,
    );
    Navigator.of(t.element(find.byType(PushupSettingsScreen))).pop();
    await flush(t);
    expect((await status(t)).active, isNotNull);
  });
  scenario('History reaches an older month and its recorded recap', (t) async {
    final old = DateTime(2025, 1, 6, 8);
    final session = PushupSession(
      day: '2025-01-06',
      started: old,
      interval: 30,
      goal: 1,
      state: PushupState.running,
    );
    session.log(
      PushupEvent(
        at: old.add(const Duration(minutes: 30)),
        kind: PushupEventKind.done,
      ),
    );
    session.state = PushupState.ended;
    session.ended = old.add(const Duration(hours: 1));
    await t.runAsync(() => PushupDb.save(session));
    await command(t, () async {
      await Pushups.start();
    });
    await open(t);
    await tap(t, action('History'));
    expect(find.byType(PushupHistoryScreen), findsOneWidget);
    await tap(t, action('Month 2025-01'));
    final day = find.byWidgetPredicate(
      (w) => w is Pressable && (w.semanticLabel?.endsWith(', 1 sets') ?? false),
    );
    await tap(t, day);
    expect(find.byType(PushupDayScreen), findsOneWidget);
    expect(find.text('1 set of 1'), findsOneWidget);
    expect(find.text('30 min'), findsWidgets);
    expect((await status(t)).sessions, hasLength(2));
  });
  scenario('empty history explains that no days exist', (t) async {
    await open(t, page: const PushupHistoryScreen(sessions: []));
    expect(find.text('No days yet.'), findsOneWidget);
  });
  // Pushups retains a process-wide command Future. Keep its UI commands in
  // one FakeAsync zone; a completed Future from a retired test zone cannot
  // schedule the next test's callbacks. Reset stores between the named flows.
  testWidgets(
    'Pushups user journeys preserve command, count and navigation contracts',
    (t) async {
      for (final flow in scenarios) {
        await t.pumpWidget(const SizedBox());
        await flush(t);
        await t.runAsync(resetFixture);
        debugPrint('Pushups flow: ${flow.name}');
        await flow.run(t);
      }
    },
  );
}
