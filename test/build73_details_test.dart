import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart' show Profile;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/state/locale_controller.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/ui2/screens/naps.dart';
import 'package:openstrap_edge/ui2/screens/sleep_detail.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/screens/day_steps.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart';
import 'package:openstrap_edge/ui2/screens/nutrition_screen.dart'
    show showMaintenance, DayUpkeep;
import 'package:openstrap_edge/ui2/ui2.dart';

final today = todayLabel();
final base = DateTime.parse(today).millisecondsSinceEpoch ~/ 1000;
const profile = <String, dynamic>{
  'age': 23,
  'sex': 'm',
  'weight_kg': 80.5,
  'height_cm': 186.69,
};
final proposal = <String, dynamic>{
  'start': base + 14 * 3600,
  'end': base + 15 * 3600,
  'duration_min': 55,
  'confidence': .8,
};

class SlowNapApp extends AppState {
  SlowNapApp() : super.forTesting();
  final pending = Completer<void>();
  int requests = 0;
  @override
  Future<void> reanalyzeForNapEdit([String? day]) {
    requests++;
    napRebuilding = true;
    napRebuildMessage = 'Updating in the background';
    bumpInsights();
    notifyListeners();
    return pending.future;
  }
}

class GraphRepo extends LocalRepository {
  bool fail = false;
  int steps = 5000;
  @override
  Future<Map<String, dynamic>> getProfile() async => profile;
  @override
  Future<List<String>> availableDays() async => [
    for (var i = 0; i < 10; i++)
      dayLabelOf(DateTime.now().subtract(Duration(days: i))),
  ];
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async {
    if (fail) throw StateError('synthetic failure');
    return {
      'points': [
        for (var i = 9; i >= 0; i--)
          {
            't': base - i * 86400 + 12 * 3600,
            'v': metric == 'steps'
                ? steps
                : metric == 'sleep'
                ? 420
                : metric == 'strain'
                ? 6
                : 50,
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getInsights() async => {};
  @override
  Future<Map<String, dynamic>> getJournalInsights({
    String range = '90d',
  }) async => {};
  @override
  Future<Map<String, dynamic>> getToday() async => {
    'status': {'today_day': today},
  };
  @override
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'}) async => {
    'workouts': [],
  };
  @override
  Future<num?> getMeasuredDaySteps(String day) async => steps;
  @override
  Future<Map<String, dynamic>> getDaySteps(String day) async => {
    'day_total': steps,
    'total': steps,
    'phone': steps,
    'spans': [
      {
        // Already-recorded steps: a 9 AM fixture becomes future data on early CI runs.
        'start_ts': base,
        'end_ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'source': 'phone',
        'steps': steps,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> getDayNaps(String day) async => {
    'naps': [],
    'nap_min': 0,
  };
  @override
  Future<Map<String, dynamic>> getDayWear(String day) async => {
    'worn_min': 1000,
    'coverage_pct': 75,
    'segments': [
      {'start': base, 'end': base + 3600, 'on': true},
      {'start': base + 3600, 'end': base + 7200, 'on': false},
    ],
  };
  @override
  Future<Map<String, dynamic>> getDayStrain(String day) async => {
    'strain': 6.0,
    'curve': [
      {'t': base + 9 * 3600, 'v': 1},
      {'t': base + 10 * 3600, 'v': 6},
    ],
    'zones': {'z1': 30, 'z2': 10, 'z3': 0, 'z4': 0, 'z5': 0},
  };
  @override
  Future<Map<String, dynamic>> getDaySleepV2(String day) async => {
    'has_sleep': true,
    'duration_min': 420,
    'in_bed_min': 450,
    'efficiency': .93,
    'onset_ts': base - 3600,
    'wake_ts': base + 6 * 3600,
    'light_min': 200,
    'deep_min': 80,
    'rem_min': 140,
    'hypnogram': [
      {'t': base - 3600, 'stage': 'light'},
      {'t': base + 3600, 'stage': 'deep'},
      {'t': base + 6 * 3600, 'stage': 'awake'},
    ],
  };
  @override
  Future<Map<String, dynamic>> getDayTimeline(String day) async => {
    'date': today,
    'day_start': base,
    'hr': [
      {'t': base + 9 * 3600, 'v': 70},
      {'t': base + 10 * 3600, 'v': 80},
    ],
    'hypnogram': [
      {'t': base - 3600, 'stage': 'light'},
      {'t': base + 3600, 'stage': 'deep'},
      {'t': base + 6 * 3600, 'stage': 'awake'},
    ],
  };
  @override
  Future<List<Map<String, dynamic>>> sleepWindows({int days = 7}) async => [];
  @override
  Future<Map<String, dynamic>> getDayHrv(String day) async => {
    'timeline': [
      {'t': base - 3600, 'v': 60},
      {'t': base - 3000, 'v': 64},
    ],
  };
}

class DatedStepsRepo extends GraphRepo {
  @override
  Future<num?> getMeasuredDaySteps(String day) async =>
      day == todayLabel() ? 5000 : 9000;
}

Future<void> until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

Widget app(AppState state, Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AppState>.value(value: state),
    ChangeNotifierProvider<ThemeController>(
      create: (_) => ThemeController.seed(AppThemeChoice.dark, Brightness.dark),
    ),
    ChangeNotifierProvider<LocaleController>(
      create: (_) => LocaleController.seed('en'),
    ),
  ],
  child: RepaintBoundary(
    key: const ValueKey('capture'),
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: child),
    ),
  ),
);
void phone(WidgetTester t) {
  if (t.view.physicalSize.width / t.view.devicePixelRatio != 390) {
    t.view.physicalSize = const Size(390 * 3, 1200 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }
}

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('UI_CAPTURE')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('test/goldens').createSync(recursive: true);
    File(
      'test/goldens/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> close(WidgetTester t, AppState state) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 350)),
  );
  if (state is SlowNapApp && !state.pending.isCompleted)
    state.pending.complete();
  state.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  LocalRepositoryImpl repo() =>
      LocalRepositoryImpl(getProfileMap: () => profile);
  Future<void> seed(Map<String, dynamic> naps) => LocalDb.putDayResult(
    dayId: today,
    algoVersion: kAlgoVersion,
    payloadJson: jsonEncode({'naps': naps}),
    windowJson: '{}',
    finalized: false,
  );
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build73_details.db';
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
    for (final family in ['Manrope', '.SF Pro Text']) {
      final loader = FontLoader(family);
      for (final file in Directory(
        'assets/fonts/Manrope',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
      await loader.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    for (final table in [
      'sleep_nap',
      'day_result',
      'baselines',
      'metric_series',
      'sessions',
      'live_coverage',
      'food_entry',
      'body_weight',
    ]) {
      await db.delete(table);
    }
  });
  tearDownAll(() async {
    await LocalDb.close();
  });

  test(
    'rejection and last undo project immediately despite stale derived bundle',
    () async {
      await seed({
        'value': [proposal],
      });
      expect((await repo().getDayNaps(today))['nap_min'], 55);
      await LocalDb.putNapEdit(
        dayId: today,
        startTs: proposal['start'] as int,
        endTs: proposal['end'] as int,
        source: 'rejected',
      );
      expect((await repo().getDayNaps(today))['naps'], isEmpty);
      // Simulate the old engine baking rejection into the bundle, then relaunch.
      await seed({'value': []});
      expect((await repo().getDayNaps(today))['naps'], isEmpty);
      await LocalDb.deleteNapEdit(today, proposal['start'] as int);
      expect(await LocalDb.pendingNapDays(), contains(today));
      expect((await repo().getDayNaps(today))['nap_min'], 55);
    },
  );
  test(
    'manual addition and deletion do not duplicate or retain baked manual entries',
    () async {
      await seed({'value': null, 'detected': null});
      await LocalDb.putNapEdit(
        dayId: today,
        startTs: base + 3600,
        endTs: base + 5400,
        source: 'manual',
      );
      final merged = (await repo().getDayNaps(today))['naps'];
      await seed({'value': merged, 'detected': null});
      expect((await repo().getDayNaps(today))['nap_min'], 30);
      await LocalDb.deleteNapEdit(today, base + 3600);
      expect((await repo().getDayNaps(today))['naps'], isNull);
      expect((await repo().getDayNaps(today))['nap_min'], isNull);
    },
  );
  test(
    'a newer unjudged or empty assessment does not revive cached naps',
    () async {
      await seed({
        'value': [proposal],
        'detected': [proposal],
      });
      expect((await repo().getDayNaps(today))['nap_min'], 55);
      await seed({'value': null, 'detected': null});
      expect((await repo().getDayNaps(today))['naps'], isNull);
      await seed({'value': [], 'detected': []});
      expect((await repo().getDayNaps(today))['nap_min'], 0);
    },
  );
  test(
    'sleep periods and totals reflect corrections before derivation',
    () async {
      await LocalDb.putDayResult(
        dayId: today,
        algoVersion: kAlgoVersion,
        windowJson: '{}',
        payloadJson: jsonEncode({
          'naps': {
            'value': [proposal],
            'detected': [proposal],
          },
          'sleep': {
            'accounting': {
              'value': {'tst_sec': 420 * 60},
            },
          },
          'sleep_periods': {
            'total_asleep_min': 475,
            'periods': [
              {
                'is_main': true,
                'onset_ts': base,
                'wake_ts': base + 7 * 3600,
                'duration_min': 420,
              },
              {
                'is_main': false,
                'onset_ts': proposal['start'],
                'wake_ts': proposal['end'],
                'duration_min': 55,
              },
            ],
          },
        }),
      );
      expect((await repo().getDaySleep(today))['total_asleep_min'], 475);
      await LocalDb.putNapEdit(
        dayId: today,
        startTs: proposal['start'] as int,
        endTs: proposal['end'] as int,
        source: 'rejected',
      );
      final removed = await repo().getDaySleep(today);
      expect(removed['periods'], hasLength(1));
      expect(removed['total_asleep_min'], 420);
      await LocalDb.deleteNapEdit(today, proposal['start'] as int);
      expect((await repo().getDaySleep(today))['total_asleep_min'], 475);
      // A manual report remains available without a derived night at all.
      await db.delete('day_result');
      await db.delete('baselines');
      await LocalDb.putNapEdit(
        dayId: today,
        startTs: base + 3600,
        endTs: base + 5400,
        source: 'manual',
      );
      final manual = await repo().getDaySleep(today);
      expect(manual['has_sleep'], isFalse);
      expect(manual['periods'], hasLength(1));
      expect(
        manual['total_asleep_min'],
        isNull,
      ); // no complete detector assessment
    },
  );
  test('a held-over timeline uses that day’s corrected naps', () async {
    final previous = dayLabelOf(
      DateTime.parse(today).subtract(const Duration(days: 1)),
    );
    final previousBase = localDayStartSec(previous)!;
    await LocalDb.putDayResult(
      dayId: previous,
      algoVersion: kAlgoVersion,
      windowJson: '{}',
      payloadJson: jsonEncode({
        'sleep': {
          'accounting': {
            'value': {'tst_sec': 420 * 60},
          },
        },
        'naps': {
          'value': [
            {
              ...proposal,
              'start': previousBase + 14 * 3600,
              'end': previousBase + 15 * 3600,
            },
          ],
        },
      }),
    );
    await LocalDb.putNapEdit(
      dayId: today,
      startTs: base + 3600,
      endTs: base + 5400,
      source: 'manual',
    );
    final timeline = await repo().getDayTimeline(today);
    expect(
      (timeline['naps'] as List).single['start'],
      previousBase + 14 * 3600,
    );
    expect(timeline['day_start'], previousBase);
  });
  test(
    'nap credit recalculates from retained results with no raw data',
    () async {
      for (var i = 14; i >= 0; i--) {
        final date = dayLabelOf(DateTime.now().subtract(Duration(days: i)));
        final start = DateTime.parse(date).millisecondsSinceEpoch ~/ 1000;
        await LocalDb.putDayResult(
          dayId: date,
          algoVersion: kAlgoVersion - 1,
          finalized: true,
          windowJson: '{}',
          rhr: 55,
          rmssd: 60,
          payloadJson: jsonEncode({
            'scalars': {
              'rhr': 55,
              'rmssd': 60,
              'strain': 0,
              'nap_min': i == 0 ? 55 : 0,
            },
            'sleep': {
              'window': {
                'value': {
                  'onset_ms': (start - 3600) * 1000,
                  'offset_ms': (start + 7 * 3600) * 1000,
                },
              },
              'accounting': {
                'value': {
                  'tst_sec': 8 * 3600,
                  'in_bed_sec': 8 * 3600,
                  'observed_in_bed_sec': 8 * 3600,
                },
              },
            },
            'naps': {
              'value': i == 0 ? [proposal] : [],
            },
          }),
        );
      }
      final before = await db.query('day_result');
      final engine = DerivationEngine();
      Future<num> need() async {
        final value = jsonDecode(
          (await LocalDb.baseline('crossday'))!['payload_json'] as String,
        );
        return value['sleep_coach']['need']['value']['need_sec'] as num;
      }

      expect(await engine.rebuildCrossDay(Profile.fromMap(profile)), 'ready');
      final withNap = await need();
      // Capture the old detector proposal before rejection, as the screen does.
      await repo().getDayNaps(today);
      await LocalDb.putNapEdit(
        dayId: today,
        startTs: proposal['start'] as int,
        endTs: proposal['end'] as int,
        source: 'rejected',
      );
      final state = AppState.forTesting()..user = profile;
      await state.reanalyzeForNapEdit(today);
      expect(await need() - withNap, 55 * 60);
      await LocalDb.deleteNapEdit(today, proposal['start'] as int);
      await state.reanalyzeForNapEdit(today);
      expect(await need(), withNap);
      expect(await LocalDb.pendingNapDays(), isEmpty);
      expect(
        await db.query('day_result'),
        before,
        reason: 'editing a nap must preserve original sleep/HR measurements',
      );
      state.dispose();
    },
  );
  test('deleting a day clears nap proposals and pending corrections', () async {
    await seed({
      'value': [proposal],
    });
    await repo().getDayNaps(today);
    await LocalDb.putNapEdit(
      dayId: today,
      startTs: proposal['start'] as int,
      endTs: proposal['end'] as int,
      source: 'rejected',
    );
    await LocalDb.deleteDays({today});
    expect(await LocalDb.napCorrectionDays(), isEmpty);
    expect(await LocalDb.baseline('nap_proposals:$today'), isNull);
  });
  testWidgets(
    'remove restore and reopen never wait for background calculations',
    (t) async {
      await t.runAsync(
        () => seed({
          'value': [proposal],
          'detected': [proposal],
        }),
      );
      final state = SlowNapApp()..repo = repo();
      phone(t);
      await t.pumpWidget(app(state, NapsScreen(day: today)));
      await until(t, () => find.text('Not a nap').evaluate().isNotEmpty);
      await t.tap(find.text('Not a nap'));
      await until(t, () => find.text('Put it back').evaluate().isNotEmpty);
      expect(state.pending.isCompleted, isFalse);
      expect(find.text('Not a nap'), findsNothing);
      await t.pumpWidget(
        app(state, NapsScreen(key: const ValueKey('reopen'), day: today)),
      );
      await until(t, () => find.text('Put it back').evaluate().isNotEmpty);
      await t.ensureVisible(find.text('Put it back'));
      await t.tap(find.text('Put it back'));
      await until(t, () => find.text('Not a nap').evaluate().isNotEmpty);
      expect(find.text('Put it back'), findsNothing);
      expect(state.requests, 2);
      await capture(t, 'build73-nap-restore');
      await close(t, state);
    },
  );
  testWidgets(
    'pre-73 rejected window without proposal restores as user report',
    (t) async {
      await t.runAsync(() => seed({'value': [], 'detected': []}));
      await t.runAsync(
        () => LocalDb.putNapEdit(
          dayId: today,
          startTs: base + 3600,
          endTs: base + 5400,
          source: 'rejected',
        ),
      );
      final state = SlowNapApp()..repo = repo();
      phone(t);
      await t.pumpWidget(app(state, NapsScreen(day: today)));
      await until(t, () => find.text('Put it back').evaluate().isNotEmpty);
      await t.ensureVisible(find.text('Put it back'));
      await t.tap(find.text('Put it back'));
      await until(t, () => find.text('Delete').evaluate().isNotEmpty);
      final naps =
          (await t.runAsync(() => repo().getDayNaps(today)))!['naps'] as List;
      expect(naps.single['source'], 'manual');
      expect(naps.single['confidence'], isNull);
      await close(t, state);
    },
  );
  testWidgets('empty Sleep retains Naps entry point, including no main night', (
    t,
  ) async {
    for (final data in [
      const SleepData(),
      SleepData(
        day: today,
        night: {
          'duration_min': 420,
          'onset_ts': base - 3600,
          'wake_ts': base + 6 * 3600,
        },
      ),
    ]) {
      await t.pumpWidget(MaterialApp(home: SleepDetail(data: data)));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Naps').first, 500);
      expect(find.text('Naps'), findsWidgets);
      expect(t.takeException(), isNull);
    }
  });
  testWidgets(
    'Today maintenance rereads the current date after a stale snapshot',
    (t) async {
      final state = AppState.forTesting()
        ..repo = DatedStepsRepo()
        ..user = profile;
      phone(t);
      await t.pumpWidget(
        app(
          state,
          Builder(
            builder: (c) => TextButton(
              onPressed: () => showMaintenance(
                c,
                DayUpkeep(
                  Profile.fromMap(profile),
                  steps: 9000,
                  date: dayLabelOf(
                    DateTime.now().subtract(const Duration(days: 1)),
                  ),
                ),
                today: true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      // Build 85: the step count is in the folded explanation.
      await until(
        t,
        () => find.text("How it's worked out").evaluate().isNotEmpty,
      );
      // Let the sheet finish rising before tapping inside it.
      await t.pump(const Duration(seconds: 1));
      await t.ensureVisible(find.text("How it's worked out"));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text("How it's worked out"));
      await until(
        t,
        () => find.textContaining('5,000 steps').evaluate().isNotEmpty,
      );
      expect(find.textContaining('9,000 steps'), findsNothing);
      await close(t, state);
    },
  );
  testWidgets(
    'Steps Today has inline hourly chart and refreshes without re-opening',
    (t) async {
      t.view.physicalSize = const Size(390 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final r = GraphRepo(), state = AppState.forTesting();
      state.repo = r;
      state.user = profile;
      phone(t);
      await t.pumpWidget(app(state, const MetricDetail('steps')));
      await until(t, () => find.text('5,000').evaluate().isNotEmpty);
      await until(
        t,
        () => find.text('WHEN THEY WERE COUNTED').evaluate().isNotEmpty,
      );
      expect(find.text('Breakdown'), findsNothing);
      r.steps = 6500;
      state.bumpInsights();
      await until(t, () => find.text('6,500').evaluate().isNotEmpty);
      await until(t, () => find.text('Updating steps…').evaluate().isEmpty);
      expect(find.textContaining('6,500'), findsWidgets);
      expect(find.textContaining('5,000'), findsNothing);
      await until(
        t,
        () => find.textContaining('171 kcal').evaluate().isNotEmpty,
      );
      expect(find.textContaining('132 kcal'), findsNothing);
      await capture(t, 'build73-inline-steps');
      final previous = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Previous day',
      );
      expect(previous, findsOneWidget);
      await t.ensureVisible(previous);
      await t.tap(previous);
      final destination = find.byWidgetPredicate(
        (w) => w is DayStepsDetail && !w.embedded,
      );
      await until(t, () => destination.evaluate().isNotEmpty);
      expect(
        t.widget<DayStepsDetail>(destination).day,
        dayLabelOf(DateTime.now().subtract(const Duration(days: 1))),
      );
      await close(t, state);
    },
  );
  testWidgets(
    'Trends defaults to 7 days and Step calories opens at the same range',
    (t) async {
      final r = GraphRepo(), state = AppState.forTesting();
      state.repo = r;
      state.user = profile;
      phone(t);
      await t.pumpWidget(app(state, const HealthScreen()));
      await until(t, () => find.text('Step calories').evaluate().isNotEmpty);
      // Build 75: Today · 7 days · 30 days · 3 months, opening on 7 days.
      expect(t.widget<SubTabs>(find.byType(SubTabs).first).index, 1);
      await t.ensureVisible(find.text('Step calories'));
      await t.tap(find.text('Step calories'));
      await until(t, () => find.byType(MetricDetail).evaluate().isNotEmpty);
      expect(
        t.widget<MetricDetail>(find.byType(MetricDetail)).metricKey,
        'step_kcal',
      );
      await until(
        t,
        () => find
            .descendant(
              of: find.byType(MetricDetail),
              matching: find.text('132'),
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(t.widget<MetricDetail>(find.byType(MetricDetail)).range, 1);
      expect(find.text('steps', findRichText: true), findsNothing);
      await t.tap(
        find.descendant(
          of: find.byType(MetricDetail),
          matching: find.text('Today'),
        ).first,
      );
      await t.pump(const Duration(seconds: 1));
      await until(
        t,
        () => find.text('Walking energy by hour').evaluate().isNotEmpty,
      );
      await capture(t, 'build73-step-calories');
      await close(t, state);
    },
  );
  test(
    'Step calorie series agrees with maintenance Weyand contribution',
    () async {
      final d = await MetricData.load(GraphRepo(), 'step_kcal');
      expect(d.series.last.v, closeTo(2.74 * 5000 * 80.5 / 8368, .0001));
    },
  );
  testWidgets('Trends Sleep Today renders the full night graph', (t) async {
    final state = AppState.forTesting()
      ..repo = GraphRepo()
      ..user = profile;
    phone(t);
    await t.pumpWidget(app(state, const MetricDetail('sleep')));
    await until(t, () => find.text('Through the night').evaluate().isNotEmpty);
    expect(find.text('Stages'), findsOneWidget);
    expect(t.takeException(), isNull);
    await capture(t, 'build73-trends-sleep');
    await close(t, state);
  });
  testWidgets('Trends Strain Today renders the existing day curve', (t) async {
    final state = AppState.forTesting()
      ..repo = GraphRepo()
      ..user = profile;
    phone(t);
    await t.pumpWidget(app(state, const MetricDetail('strain')));
    await until(t, () => find.byType(Scrubber).evaluate().isNotEmpty);
    expect(find.text('6.0'), findsWidgets);
    expect(t.takeException(), isNull);
    await close(t, state);
  });
  testWidgets('HRV and Wear Today render their timestamped data', (t) async {
    for (final key in ['hrv', 'wear']) {
      final state = AppState.forTesting()
        ..repo = GraphRepo()
        ..user = profile;
      phone(t);
      await t.pumpWidget(app(state, MetricDetail(key)));
      await until(
        t,
        () => find
            .text(key == 'hrv' ? 'HRV through the night' : 'Wear by hour')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byType(Scrubber), findsWidgets);
      expect(t.takeException(), isNull);
      await close(t, state);
    }
  });
  testWidgets(
    'metric read failure offers retry instead of pretending empty history',
    (t) async {
      final r = GraphRepo()..fail = true;
      final state = AppState.forTesting()
        ..repo = r
        ..user = profile;
      phone(t);
      await t.pumpWidget(app(state, const MetricDetail('steps')));
      await until(
        t,
        () => find.text('This metric could not load').evaluate().isNotEmpty,
      );
      r.fail = false;
      await t.tap(find.text('Retry').first);
      await until(t, () => find.text('5,000').evaluate().isNotEmpty);
      await until(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await close(t, state);
    },
  );
  testWidgets('daily details fit a small phone with enlarged text', (t) async {
    t.view.physicalSize = const Size(320 * 3, 1300 * 3);
    t.view.devicePixelRatio = 3;
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    for (final key in ['steps', 'sleep', 'strain']) {
      final state = AppState.forTesting()
        ..repo = GraphRepo()
        ..user = profile;
      await t.pumpWidget(app(state, MetricDetail(key)));
      await until(t, () => find.byType(Scrubber).evaluate().isNotEmpty);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: key);
      await close(t, state);
    }
  });
}
