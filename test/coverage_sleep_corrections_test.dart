// The real Sleep page and its two time pickers. Only the post-write
// calculation/repository boundary is substituted; the recording guard uses SQLite.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

const _day = '2026-02-05';
final _onset = DateTime(2026, 2, 4, 23).millisecondsSinceEpoch ~/ 1000;

class _Repo extends LocalRepository {
  Map<String, dynamic> night = {
    'duration_min': 420,
    'in_bed_min': 480,
    'onset_ts': _onset,
    'wake_ts': _onset + 8 * 3600,
    'sleep_source': 'auto_fallback',
  };
  @override
  Future<Map<String, dynamic>> getToday() async => {
    'status': {'today_day': _day},
  };
  @override
  Future<List<String>> availableDays() async => [_day];
  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) async =>
      Map.of(night);
  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) async => {};
  @override
  Future<Map<String, dynamic>> getNightSignals(int onsetTs, int wakeTs) async =>
      {};
  @override
  Future<Map<String, dynamic>> getInsights() async => {};
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async => {};
  @override
  Future<Map<String, dynamic>> getDayNaps(String date) async => {};
  @override
  Future<List<Map<String, dynamic>>> sleepWindows({
    int days = 60,
    String? before,
  }) async => [];
}

class _App extends AppState {
  _App(this.source) : super.forTesting() {
    repo = source;
  }
  final _Repo source;
  final calls = <String>[];
  bool refuse = false, apply = true;
  Completer<void>? waiting;
  (DateTime, DateTime)? entered;
  Future<void> write(String command, String after) async {
    calls.add(command);
    if (waiting != null) await waiting!.future;
    if (refuse) throw StateError('synthetic sleep write refusal');
    if (apply) source.night['sleep_source'] = after;
  }

  @override
  Future<void> confirmSleep(String date) => write('confirm:$date', 'confirmed');
  @override
  Future<void> clearSleepOverride(String date) => write('clear:$date', 'auto');
  @override
  Future<void> rejectSleep(String date) => write('reject:$date', 'rejected');
  @override
  Future<void> setSleepOverride(
    String date,
    DateTime onset,
    DateTime offset, {
    String source = 'manual',
  }) async {
    entered = (onset, offset);
    await write('manual:$date', source);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Repo repo;
  late _App app;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final dir = (await Directory(
      'build/coverage-remainder/sleep-corrections',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${dir.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    repo = _Repo();
    app = _App(repo);
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
            child: w!,
          ),
          home: const SleepDetail(day: _day),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Fix sleep times');
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  }

  testWidgets('fallback confirmation reloads the newly confirmed window', (
    t,
  ) async {
    await open(t);
    await tap(t, 'These times are right');
    expect(app.calls, ['confirm:$_day']);
    expect(find.text('You set this window'), findsOneWidget);
    expect(find.text('Back to automatic'), findsOneWidget);
    expect(find.text('These times are right'), findsNothing);
    await close(t);
  });
  testWidgets('reverting a manual window restores its automatic actions', (
    t,
  ) async {
    repo.night['sleep_source'] = 'manual';
    await open(t);
    await tap(t, 'Back to automatic');
    expect(app.calls, ['clear:$_day']);
    expect(
      find.text('This window was staged from the signals'),
      findsOneWidget,
    );
    expect(find.text('Back to automatic'), findsNothing);
    await close(t);
  });
  testWidgets('Not sleep uses the selected night, not today', (t) async {
    await open(t);
    await tap(t, 'Not sleep');
    expect(app.calls, ['reject:$_day']);
    expect(find.text('That correction has not been applied'), findsNothing);
    await close(t);
  });
  testWidgets('a refused correction tells the user nothing was saved', (
    t,
  ) async {
    app.refuse = true;
    await open(t);
    await tap(t, 'These times are right');
    expect(repo.night['sleep_source'], 'auto_fallback');
    await show(t, 'Nothing was saved. Try again.');
    expect(find.text('Nothing was saved. Try again.'), findsOneWidget);
    expect(find.text('These times are right'), findsOneWidget);
    await close(t);
  });
  testWidgets(
    'a saved but unchanged analysis is distinguished from write failure',
    (t) async {
      app.apply = false;
      await open(t);
      await tap(t, 'These times are right');
      await show(t, 'That correction has not been applied');
      expect(
        find.textContaining('The times you set are saved'),
        findsOneWidget,
      );
      expect(find.text('Nothing was saved. Try again.'), findsNothing);
      await close(t);
    },
  );
  for (final cancelAt in [0, 1]) {
    testWidgets('cancelling time picker ${cancelAt + 1} makes no correction', (
      t,
    ) async {
      await open(t);
      await tap(t, 'Set the times myself');
      expect(find.byType(TimePickerDialog), findsOneWidget);
      if (cancelAt == 1) await tap(t, 'OK');
      await tap(t, 'Cancel');
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(app.calls, isEmpty);
      expect(app.entered, isNull);
      await close(t);
    });
  }
  testWidgets(
    'accepting both clock pickers preserves the original overnight instants',
    (t) async {
      await open(t);
      await tap(t, 'Set the times myself');
      await tap(t, 'OK');
      await tap(t, 'OK');
      for (var i = 0; i < 30 && app.entered == null; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(app.calls, ['manual:$_day']);
      expect(app.entered!.$1.millisecondsSinceEpoch ~/ 1000, _onset);
      expect(app.entered!.$2.millisecondsSinceEpoch ~/ 1000, _onset + 8 * 3600);
      expect(find.text('You set this window'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'a pending correction disables duplicate writes and survives page disposal',
    (t) async {
      app.waiting = Completer<void>();
      await open(t);
      await tap(t, 'These times are right');
      expect(app.calls, ['confirm:$_day']);
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Not sleep'))
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'These times are right'),
            )
            .onPressed,
        isNull,
      );
      await close(t);
      app.waiting!.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}

Future<void> show(WidgetTester t, String text) async {
  await t.scrollUntilVisible(
    find.text(text),
    300,
    maxScrolls: 35,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String text) async {
  final target = find.text(text);
  if (find.byType(TimePickerDialog).evaluate().isEmpty) {
    await show(t, text);
  } else {
    await t.ensureVisible(target);
    await t.pumpAndSettle();
  }
  await t.tap(target);
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}
