// Build 87 redesign: every tab rendered at phone height and accessible text with
// synthetic data. Run with --dart-define=UI_CAPTURE=true to write the pages to
// build/ui_capture/ for review; without it the test still pumps every page at
// 1x, 2x and 3.1x text and fails on any overflow.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ui2/profile/status.dart';
import 'package:openstrap_edge/ui2/screens/food_diary.dart';
import 'package:openstrap_edge/ui2/screens/food_picker.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart'
    show OsTextField;
import 'package:openstrap_edge/data/calculation_store.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/goal_plan.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/gps/run_history.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/lift_log_ui.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/day_timeline.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/screens/nutrition_screen.dart';
import 'package:openstrap_edge/ui2/screens/workout_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

const _profile = <String, dynamic>{
  'age': 30,
  'sex': 'm',
  'weight_kg': 82.0,
  'height_cm': 180.0,
  'protein_target': 160,
  'kcal_target': 2300,
  'carbs_target': 240,
  'fat_target': 70,
  'fibre_target': 30,
};

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

int _ts(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

class _Repo extends LocalRepository {
  _Repo({this.failCharts = false});
  final bool failCharts;
  @override
  Future<Map<String, dynamic>> getProfile() async => _profile;
  @override
  Future<Map<String, dynamic>> getToday() async => {
    'daily': {
      'steps': {'value': 8642},
    },
  };
  @override
  Future<List<String>> availableDays() async => [];
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async {
    if (failCharts) throw StateError('fixture chart read failed');
    if (metric != 'strain') return {'points': []};
    final now = DateTime.now();
    return {
      'points': [
        for (var i = 0; i < 7; i++)
          {
            't': _ts(DateTime(now.year, now.month, now.day - (6 - i), 12)),
            'v': 6.0 + (i * 37 % 9),
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'}) async {
    final now = DateTime.now();
    Map<String, dynamic> row(String id, String type, int daysAgo, int min) {
      final s = DateTime(now.year, now.month, now.day - daysAgo, 18);
      return {
        'id': id,
        'type': type,
        'start_ts': _ts(s),
        'end_ts': _ts(s.add(Duration(minutes: min))),
        'strain': 9.4,
        'calories': 310,
        'avg_hr': 128,
        'max_hr': 161,
      };
    }

    return {
      'workouts': [
        row('w1', 'Weight training', 1, 62),
        row('w2', 'Weight training', 3, 55),
        row('w3', 'Cycling', 4, 35),
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getInsights() async => {};
  @override
  Future<Map<String, dynamic>> getDaySteps(String date) async => {
    'day_total': 8642,
  };
}

class _MutableHistoryRepo extends _Repo {
  bool empty = false;
  @override
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'}) =>
      empty ? Future.value({'workouts': []}) : super.getWorkouts(range: range);
}

class _RecentRepo extends _Repo {
  _RecentRepo({this.fail = false});
  final bool fail;
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async {
    if (metric != 'hr') return super.getChart(metric, from: from, to: to);
    if (fail) throw StateError('test HR read failed');
    return {
      'points': [
        {'t': _ts(DateTime.now()) - 60, 'v': 77},
      ],
    };
  }

  @override
  Future<List<Map<String, num>>> getRecordedHr(int fromSec, int toSec) async {
    if (fail) throw StateError('test recent read failed');
    return [
      {'t': (_ts(DateTime.now()) ~/ 60 - 2) * 60, 'v': 83},
    ];
  }

  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) =>
      throw StateError('Today must not wait for the calculated timeline');
}

class _BurstEngine extends BleEngine {
  _BurstEngine({this.productive = false})
    : super(onRecord: (s, r) async {}, onState: (_) {});
  final bool productive;
  int requests = 0, rounds = 0, count = 200;
  @override
  bool get isConnected => true;
  @override
  int get historyRecordCount => count;
  @override
  int? get strapHistoryNewestTs => 1790003600;
  @override
  Future<void> requestHistorySync() async {
    requests++;
  }

  @override
  Future<SyncReport> runSync({
    Duration timeout = const Duration(seconds: 600),
  }) async {
    rounds++;
    if (productive && rounds == 1) count += 50;
    return SyncReport(count, 4 + rounds, true);
  }
}

HomeData _home() {
  final hr = <double?>[
    for (var m = 0; m < 1440; m++)
      m < 60 * 6
          ? 52 + (m * 7 % 5).toDouble()
          : m > 60 * 19
          ? null
          : 68 + (m * 13 % 30).toDouble() + (m ~/ 60 == 18 ? 50 : 0),
  ];
  return HomeData(
    name: 'Alex',
    dayId: todayLabel(),
    readiness: const Metric(value: 74, confidence: .8, tier: MetricTier.high),
    sleepMin: const Metric(
      value: 431,
      unit: 'min',
      confidence: .8,
      tier: MetricTier.estimate,
    ),
    strain: const Metric(
      value: 11.8,
      confidence: .6,
      tier: MetricTier.estimate,
    ),
    rhr: const Metric(
      value: 53,
      unit: 'bpm',
      confidence: .8,
      tier: MetricTier.high,
    ),
    hrv: const Metric(
      value: 61,
      unit: 'ms',
      confidence: .8,
      tier: MetricTier.high,
    ),
    steps: const Metric(
      value: 8642,
      unit: 'steps',
      confidence: .6,
      tier: MetricTier.estimate,
    ),
    stepGoal: 10000,
    graph: DayGraph(hr: hr, dayStartSec: _ts(DateTime.parse(todayLabel()))),
    recentHr: [
      for (var i = 0; i < 60; i++)
        if (i < 20 || i > 25)
          {'t': (_ts(DateTime.now()) ~/ 60 - i) * 60, 'v': 65 + i % 12},
    ],
    upkeep: DayUpkeep(
      Profile.fromMap(_profile),
      steps: 8642,
      eaten: 1450,
      date: todayLabel(),
    ),
    updatedAt: DateTime.now().subtract(const Duration(minutes: 12)),
  );
}

Widget _app(
  AppState app,
  Widget child,
  double scale,
  ShellDomain domain, {
  bool shell = true,
}) => MultiProvider(
  providers: [ChangeNotifierProvider<AppState>.value(value: app)],
  child: RepaintBoundary(
    key: const ValueKey('capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 59, bottom: 34),
        ),
        child: w!,
      ),
      home: shell
          ? AppShell(initial: domain, builder: (c, tab) => child)
          : child,
    ),
  ),
);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 40; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('UI_CAPTURE')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    Directory('build/ui_capture').createSync(recursive: true);
    File(
      'build/ui_capture/$name.png',
    ).writeAsBytesSync(bytes.buffer.asUint8List());
    image.dispose();
  });
}

ProgressData _progress({bool empty = false, bool failed = false}) {
  final now = DateTime.now();
  String label(int ago) =>
      dayLabelOf(DateTime(now.year, now.month, now.day - ago));
  return ProgressData(
    weights: empty
        ? []
        : [
            for (var i = 60; i >= 0; i--)
              if (i != 4 && i != 5)
                (
                  date: label(i),
                  kg: 80 + i * .018,
                  atTs: _ts(DateTime(now.year, now.month, now.day - i, 7)),
                  unit: 'kg',
                  entered: null,
                  source: 'whoop',
                  originId: null,
                  historyOnly: false,
                ),
          ],
    measures: empty
        ? []
        : [
            for (final i in [0, 14, 28, 56])
              BodyMeasure(
                id: 'm$i',
                date: label(i),
                recordedAt: now,
                inches: {'waistNavel': 33.5 + i * .02, 'neck': 15.1},
              ),
          ],
    photos: [],
    lifts: [],
    food: empty
        ? []
        : [
            for (var i = 60; i > 0; i--)
              (
                date: label(i),
                kcal: 2300.0,
                counts: i % 6 != 0,
                protein: 162.0,
                proteinComplete: i % 6 != 0,
              ),
          ],
    steps: empty
        ? []
        : [for (var i = 60; i >= 0; i--) (date: label(i), value: 12680.0)],
    sleepMin: empty
        ? []
        : [for (var i = 60; i >= 0; i--) (date: label(i), value: 425.0)],
    recovery: empty
        ? []
        : [for (var i = 60; i >= 0; i--) (date: label(i), value: 72.0)],
    sessions: empty
        ? []
        : [
            for (var i = 50; i >= 0; i -= 3)
              (date: label(i), type: i % 2 == 0 ? 'Walking' : 'Cycling'),
          ],
    baseline: empty ? null : label(60),
    heightCm: 180,
    user: _profile,
    readErrors: failed ? ['Food'] : [],
  );
}

HealthData _trends({int days = 30, bool gaps = false}) {
  final now = DateTime.now();
  return HealthData(
    charts: {
      for (final (name, base) in [
        ('recovery', 72.0),
        ('sleep', 425.0),
        ('hrv', 63.0),
        ('resting_hr', 52.0),
        ('strain', 8.0),
        ('steps', 12680.0),
        ('step_kcal', 410.0),
        ('step_kcal_acsm', 530.0),
        ('resp_rate', 15.0),
        ('skin_temp', .1),
        ('wear', 1350.0),
      ])
        name: [
          for (var i = 0; i < days; i++)
            if (!gaps || (i % 11 != 3 && (i < 40 || i > 48)))
              (
                t: _ts(
                  DateTime(now.year, now.month, now.day - (days - 1 - i), 12),
                ),
                v: base + (i % 5).toDouble() + (i % 13) / 3,
              ),
        ],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory photoRoot;
  late PathProviderPlatform oldPaths;
  final photos = [
    for (var i = 0; i < 3; i++)
      BodyPhoto(
        id: 'render-$i',
        date: '2026-09-${20 + i}',
        pose: i == 2 ? 'side' : 'front',
        recordedAt: DateTime(2026, 9, 20 + i),
      ),
  ];

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build87_redesign_render_test.db';
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
    photoRoot = Directory.systemTemp.createTempSync('build87-photos-');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(photoRoot.path);
    final dir = await BodyLogDb.photoDir();
    for (var i = 0; i < photos.length; i++) {
      final bitmap = img.Image(width: 160, height: 220);
      img.fill(bitmap, color: img.ColorRgb8(80 + i * 50, 130, 110));
      await File(
        path.join(dir.path, photos[i].fileName),
      ).writeAsBytes(img.encodeJpg(bitmap));
    }
    await beginLiftLog(
      LiftSplitChoice(
        LiftSplit(
          name: 'Upper body',
          exercises: [
            LiftSplitExercise(
              name: 'Dumbbell bench press',
              loadMode: LiftLoadMode.perHand,
            ),
          ],
        ),
      ),
      sessionId: 'b87-live-lift',
      startedAt: DateTime.now(),
    );
    for (final family in ['Manrope', '.SF Pro Text']) {
      final loader = FontLoader(family);
      for (final f in Directory(
        'assets/fonts/Manrope',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
        loader.addFont(
          f.readAsBytes().then(
            (b) => ByteData.sublistView(Uint8List.fromList(b)),
          ),
        );
      }
      await loader.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
    icons.addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
    await icons.load();
    final today = todayLabel();
    final at = DateTime.parse(today);
    var n = 0;
    for (final (meal, label, kcal, protein, hour) in const [
      ('breakfast', 'Greek yogurt', 180.0, 18.0, 8),
      ('breakfast', 'Oats', 300.0, 10.0, 8),
      ('lunch', 'Chicken rice bowl', 640.0, 48.0, 13),
      ('snack', 'Protein bar', 210.0, 20.0, 16),
      ('dinner', 'Salmon and potatoes', 120.0, 12.0, 19),
    ]) {
      await NutritionDb.put(
        db,
        FoodEntry(
          id: 'e${n++}',
          date: today,
          meal: meal,
          label: label,
          kcal: kcal,
          proteinG: protein,
          carbsG: kcal / 8,
          fatG: kcal / 40,
          atTs: _ts(at.add(Duration(hours: hour))),
          confirmed: true,
        ),
      );
    }
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = oldPaths;
    await photoRoot.delete(recursive: true);
    WorkoutClock.current = null;
    LiveDraft.clear();
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    runsChanged();
  });

  for (final scale in [1.0, 2.0]) {
    for (final name in [
      'photos',
      'live_walk',
      'live_lift',
      'summary',
      'body_entry',
    ]) {
      testWidgets('$name uses real phone height at ${scale}x', (t) async {
        t.view.physicalSize = const Size(390 * 1.5, 844 * 1.5);
        t.view.devicePixelRatio = 1.5;
        addTearDown(t.view.reset);
        final app = AppState.forTesting()
          ..repo = _Repo()
          ..user = {..._profile};
        addTearDown(app.dispose);
        final walking = activityByName('Walking')!;
        final lifting = activityByName('Weight training')!;
        if (name.startsWith('live')) {
          LiveDraft.begin(name == 'live_lift' ? lifting : walking);
          WorkoutClock.current = WorkoutClock('b87-live-lift', DateTime.now());
        }
        final child = switch (name) {
          'photos' => PhotoCompareScreen(photos: photos),
          'live_walk' => LiveMeasured(
            walking,
            weightKg: 82,
            feed: () => const LiveFeed(
              hr: 112,
              maxHr: 132,
              currentSpeedMps: 1.4,
              distanceKm: 1.2,
              steps: 1600,
              cadence: 110,
              gpsActive: true,
              zoneMinutes: [1, 4, 0, 0, 0],
            ),
          ),
          'live_lift' => LiveMeasured(
            lifting,
            weightKg: 82,
            feed: () => const LiveFeed(hr: 118, maxHr: 140),
          ),
          'summary' => ActivitySummary(
            ActivityResult(
              walking,
              start: DateTime(2026, 9, 20, 7, 15),
              duration: const Duration(minutes: 30),
              distanceKm: 2.5,
              steps: 3200,
              avgHr: 112,
              maxHr: 136,
            ),
            weightKg: 82,
          ),
          _ => const BodyEntryScreen(unit: 'kg'),
        };
        await t.pumpWidget(
          _app(app, child, scale, ShellDomain.workout, shell: false),
        );
        await _settle(t);
        expect(t.takeException(), isNull);
        await _capture(t, 'b87_${name}_${scale}x');
        for (var i = 0; i < 3; i++) {
          await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
          await _settle(t);
          expect(t.takeException(), isNull);
        }
        if (name == 'photos') {
          await t.scrollUntilVisible(
            find.text('Front'),
            -200,
            scrollable: find.byType(Scrollable).first,
          );
          await t.tap(find.text('Front'));
          await t.pump();
          expect(find.text('Sep 20'), findsWidgets);
          Finder side(String name, String? date) => find.byWidgetPredicate(
            (w) =>
                w is Pressable &&
                (w.semanticLabel?.startsWith('$name panel,') ?? false) &&
                (date == null || w.semanticLabel!.contains(date)),
          );
          await t.scrollUntilVisible(
            side('Left', null),
            -150,
            scrollable: find.byType(Scrollable).first,
          );
          await t.tap(side('Left', null));
          await t.pump();
          final next = find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'front photo, Sep 21',
          );
          await t.scrollUntilVisible(
            next,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await t.tap(next);
          await t.pump();
          await t.scrollUntilVisible(
            side('Left', 'Sep 21'),
            -150,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            side('Right', 'Sep 22'),
            findsOneWidget,
            reason: 'changing the left panel must not replace the right',
          );
          await t.tap(
            find.byWidgetPredicate(
              (w) => w is Pressable && w.semanticLabel == 'Swap sides',
            ),
          );
          await t.pump();
          expect(side('Left', 'Sep 22'), findsOneWidget);
          expect(side('Right', 'Sep 21'), findsOneWidget);
        }
        await t.pumpWidget(const SizedBox.shrink());
        LiveDraft.clear();
        WorkoutClock.current = null;
        await _settle(t);
      });
    }
  }

  test(
    'recent HR uses absolute minutes across midnight and preserves gaps',
    () {
      final now = DateTime(2026, 11, 2, 0, 4, 30);
      final end = _ts(now) ~/ 60 * 60;
      final result = recentHeartSlots(
        [
          {'t': end - 9 * 60, 'v': 71},
          {'t': end - 2 * 60, 'v': 84},
          {'t': end - 11 * 60, 'v': 99},
          {'t': end + 60, 'v': 100},
          {'t': end - 60, 'v': 0},
        ],
        now,
        minutes: 10,
      );
      expect(result.values.length, 11);
      expect(result.values[1], 71);
      expect(result.values[8], 84);
      expect(result.values.where((v) => v != null).length, 2);
      expect(
        DateTime.fromMillisecondsSinceEpoch(result.startSec * 1000).day,
        1,
      );
      expect(() => recentHeartSlots([], now, minutes: 61), throwsArgumentError);
    },
  );

  test(
    'recent HR read includes only primary-band minutes with enough samples',
    () async {
      final start = _ts(DateTime(2026, 9, 1, 12));
      final batch = db.batch();
      for (final source in <String?>[null, 'unverified_sensor']) {
        for (var i = 0; i < 40; i++) {
          final second = start + i;
          batch.insert('decoded_onehz', {
            'device_id': source ?? '',
            'ts_ms': second * 1000,
            'rec_ts': second,
            'counter': 400000 + i,
            'hr': source == null ? (i < 20 ? 70 : 0) : 140,
            'source': source,
          });
        }
        if (source != null) {
          for (var i = 0; i < 20; i++) {
            final second = start + 60 + i;
            batch.insert('decoded_onehz', {
              'device_id': source,
              'ts_ms': second * 1000,
              'rec_ts': second,
              'counter': 500000 + i,
              'hr': 150,
              'source': source,
            });
          }
        }
      }
      await batch.commit(noResult: true);
      final repo = LocalRepositoryImpl(getProfileMap: () => _profile);
      final recorded = await repo.getRecordedHr(start, start + 120);
      expect(recorded, [
        {'t': start, 'v': 70.0},
      ]);
      await db.delete(
        'decoded_onehz',
        where: 'rec_ts >= ? AND rec_ts < ?',
        whereArgs: [start, start + 120],
      );
    },
  );

  test(
    'Today uses committed result metadata before the pass finishes',
    () async {
      final today = todayLabel();
      await LocalDb.putComputeFreshness(
        'today',
        jsonEncode({
          'today_day': today,
          'activity_state': 'building',
          'activity_computed_at': 1,
          'overnight_state': 'missing',
        }),
      );
      await LocalDb.putDayResult(
        dayId: today,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'scalars': {'strain': 4.2},
        }),
        windowJson: '{}',
      );
      // No end-of-pass refresh: a background expiration may stop the next day.
      final row = await LocalDb.dayResult(today);
      final repo = LocalRepositoryImpl(getProfileMap: () => _profile);
      final result = await repo.getToday();
      expect(result['status']['activity_state'], 'ready');
      expect(result['status']['activity_computed_at'], row!['computed_at']);
      expect(result['daily']['strain']['value'], 4.2);
      // A future-version sibling cannot replace the current build's result.
      await LocalDb.putDayResult(
        dayId: today,
        algoVersion: kAlgoVersion + 1,
        payloadJson: jsonEncode({
          'scalars': {'strain': 20},
        }),
        windowJson: '{}',
      );
      expect((await repo.getToday())['daily']['strain']['value'], 4.2);
      await db.delete('day_result', where: 'day_id = ?', whereArgs: [today]);
      await db.delete(
        'compute_freshness',
        where: 'key = ?',
        whereArgs: ['today'],
      );
    },
  );

  testWidgets('primary buttons preserve vibrant fills and contrast', (t) async {
    for (final color in C.all) {
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: BigButton('Add entry', color: color, onTap: () {}),
          ),
        ),
      );
      final container = t.widget<Container>(
        find
            .descendant(
              of: find.byType(BigButton),
              matching: find.byType(Container),
            )
            .first,
      );
      final fill = (container.decoration! as BoxDecoration).color!;
      final ink = t.widget<Text>(find.text('Add entry')).style!.color!;
      expect(fill, const P(false).fill(color));
      expect(P.contrast(ink, fill), greaterThanOrEqualTo(4.5));
    }
  });

  test('energy and protein totals qualify unknown and partial logs', () {
    expect(
      energyProteinSummary(
        const NutrientTotal(567, 2, 0),
        const NutrientTotal(58, 2, 0),
      ),
      '567 kcal · 58 g protein',
    );
    expect(
      energyProteinSummary(
        const NutrientTotal(567, 2, 0),
        const NutrientTotal(58, 1, 1),
      ),
      '567 kcal · at least 58 g protein',
    );
    expect(
      energyProteinSummary(
        const NutrientTotal(200, 1, 0),
        const NutrientTotal(null, 0, 1),
      ),
      '200 kcal · Protein not tracked',
    );
    final meal = MealTemplate(
      key: 'test',
      label: 'Test',
      meal: 'breakfast',
      items: const [('whey', 2), ('deleted', 40)],
      units: const {'whey': 'scoop'},
    );
    expect(
      mealSummary(meal, {
        'whey': myFoodDef(
          key: 'whey',
          label: 'Whey',
          refGrams: 100,
          kcal: 400,
          protein: 80,
          measures: [(label: 'scoop', amount: 31)],
        ),
      }),
      'at least 248 kcal · at least 50 g protein · 2 foods · Breakfast',
    );
  });

  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets('meal group protein totals fit at ${scale}x', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const date = '2026-08-12';
      await t.runAsync(() async {
        for (final (id, kcal, protein, group) in [
          ('group-protein-a', 300.0, 40.0, 'Oatmeal and breakfast extras'),
          ('group-protein-b', 267.0, null, 'Oatmeal and breakfast extras'),
          ('group-protein-c', 200.0, 20.0, ''),
        ]) {
          await NutritionDb.put(
            db,
            FoodEntry(
              id: id,
              date: date,
              meal: 'breakfast',
              label: id,
              kcal: kcal,
              proteinG: protein,
              group: group,
            ),
          );
        }
      });
      final app = AppState.forTesting()..repo = _Repo();
      addTearDown(app.dispose);
      await t.pumpWidget(
        _app(
          app,
          const MealPage(date: date, meal: 'breakfast'),
          scale,
          ShellDomain.nutrition,
          shell: false,
        ),
      );
      await _settle(t);
      expect(find.text('567 kcal · at least 40 g protein'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('200 kcal · 20 g protein'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(t.takeException(), isNull);
      await _capture(t, 'b87_meal_groups_${scale}x');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await t.runAsync(
        () => db.delete('food_entry', where: 'date = ?', whereArgs: [date]),
      );
    });
  }

  test(
    'Today reads raw-extended HR before calculated timeline, retains failed reads',
    () async {
      final d = await HomeData.load(_RecentRepo());
      expect(d.graph.hr, contains(77));
      expect(d.recentHr.single['v'], 83);
      expect(d.graphFailed, isFalse);
      final failed = await HomeData.load(_RecentRepo(fail: true), null, d);
      expect(failed.graph.hr, contains(77));
      expect(failed.recentHr.single['v'], 83);
      expect(failed.graphFailed && failed.recentHrFailed, isTrue);
    },
  );

  for (final productive in [false, true]) {
    test(
      'backfill stops on current empty attempt, not earlier totals ($productive)',
      () async {
        final engine = _BurstEngine(productive: productive);
        final app = AppState.forTesting(engine: engine);
        addTearDown(app.dispose);
        await LocalDb.setCursor('rec_ts_hw', '1790000000');
        await app.debugRunSyncBurst();
        expect(engine.rounds, productive ? 2 : 1);
        expect(engine.requests, engine.rounds);
      },
    );
  }

  testWidgets('Status uses committed data time instead of the boot sample', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final now = DateTime.now();
    final old = Sample(tsEpoch: _ts(now) - 4 * 3600, counter: 9900, hr: 72);
    app.lastSynced = old;
    final sample = Sample(tsEpoch: _ts(now) - 60, counter: 9901, hr: 76);
    await t.runAsync(
      () => app.engine.onRecord(
        sample,
        RawRecord(
          counter: sample.counter,
          hex: '2f0c000087',
          capturedAt: now.millisecondsSinceEpoch,
          recTs: sample.tsEpoch,
          packetType: 0x2f,
        ),
      ),
    );
    expect(app.lastRecordAt!.millisecondsSinceEpoch ~/ 1000, sample.tsEpoch);
    await t.pumpWidget(
      _app(app, const StatusScreen(), 1, ShellDomain.home, shell: false),
    );
    await _settle(t);
    expect(find.text('4 h ago'), findsNothing);
    expect(find.text('1 min ago'), findsOneWidget);
    expect(
      app.lastSynced,
      same(old),
      reason: 'boot snapshot is deliberately not the status source',
    );
    await t.pumpWidget(const SizedBox.shrink());
  });

  test(
    'workout activity/date filters include other types and exact calendar bounds',
    () {
      final range = DateTimeRange(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 2),
      );
      expect(
        workoutMatchesFilters(
          'Walking',
          DateTime(2026, 11, 2, 23, 59),
          activity: WorkoutActivityFilter.walk,
          dates: range,
        ),
        isTrue,
      );
      expect(
        workoutMatchesFilters('Walking', DateTime(2026, 11, 3), dates: range),
        isFalse,
      );
      expect(
        workoutMatchesFilters(
          'Running',
          DateTime(2026, 10, 31, 23, 59),
          dates: range,
        ),
        isFalse,
      );
      expect(
        workoutMatchesFilters(
          'Weight training',
          DateTime(2026, 11, 1),
          activity: WorkoutActivityFilter.lift,
        ),
        isTrue,
      );
      expect(
        workoutMatchesFilters(
          'Imported unknown',
          DateTime(2020),
          activity: WorkoutActivityFilter.other,
        ),
        isTrue,
      );
      expect(
        workoutMatchesFilters(
          'Cycling',
          DateTime(2026),
          activity: WorkoutActivityFilter.run,
        ),
        isFalse,
      );
    },
  );

  testWidgets('custom workout dates remain valid after history is removed', (
    t,
  ) async {
    final repo = _MutableHistoryRepo();
    final app = AppState.forTesting()..repo = repo;
    addTearDown(app.dispose);
    await t.pumpWidget(
      _app(
        app,
        const WorkoutHistoryScreen(),
        1,
        ShellDomain.workout,
        shell: false,
      ),
    );
    await _settle(t);
    Future<void> chooseDates() async {
      await t.tap(find.text('All dates'));
      await t.pumpAndSettle();
      await t.tap(find.text('Choose dates'));
      await t.pumpAndSettle();
    }

    await chooseDates();
    final dialog = t.widget<DateRangePickerDialog>(
      find.byType(DateRangePickerDialog),
    );
    Navigator.of(
      t.element(find.byType(DateRangePickerDialog)),
    ).pop(DateTimeRange(start: dialog.firstDate, end: dialog.firstDate));
    await t.pumpAndSettle();
    repo.empty = true;
    app.bumpInsights();
    await _settle(t);
    // Reopen the custom range using its now-visible compact date label.
    await t.tap(find.byTooltip('Select Dates'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose dates'));
    await t.pumpAndSettle();
    final updated = t.widget<DateRangePickerDialog>(
      find.byType(DateRangePickerDialog),
    );
    expect(updated.initialDateRange!.start, updated.firstDate);
    expect(updated.initialDateRange!.end, updated.firstDate);
    expect(t.takeException(), isNull);
    Navigator.of(t.element(find.byType(DateRangePickerDialog))).pop();
    await t.pumpAndSettle();
  });

  testWidgets('All workouts filters and resets without changing history', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = AppState.forTesting()
      ..repo = _Repo()
      ..user = {..._profile};
    addTearDown(app.dispose);
    await t.pumpWidget(
      _app(
        app,
        const WorkoutHistoryScreen(),
        1,
        ShellDomain.workout,
        shell: false,
      ),
    );
    await _settle(t);
    await t.tap(find.byTooltip('Select Activity'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lifting').last);
    await t.pumpAndSettle();
    expect(find.text('2 of 3 sessions'), findsOneWidget);
    await t.tap(find.byTooltip('Select Dates'));
    await t.pumpAndSettle();
    await t.tap(find.text('Today').last);
    await t.pumpAndSettle();
    expect(find.text('No matching sessions'), findsOneWidget);
    await t.tap(find.byTooltip('Clear workout filters'));
    await t.pumpAndSettle();
    expect(find.text('No matching sessions'), findsNothing);
    expect(find.text('All activities'), findsOneWidget);
    expect(find.text('All dates'), findsOneWidget);
    await _capture(t, 'b87_workout_filters');
    await t.pumpWidget(const SizedBox.shrink());
  });

  for (final unit in ['g', 'scoop', 'old unit']) {
    testWidgets(
      'diary row edits $unit directly and preserves historical identity/group',
      (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        final def = myFoodDef(
          key: 'b87-portion',
          label: 'Test protein',
          refGrams: 31,
          unit: 'scoop',
          kcal: 120,
          protein: 22,
        );
        final entry = FoodEntry(
          id: 'b87-direct-$unit',
          date: '2026-09-15',
          atTs: _ts(DateTime(2026, 9, 15, 8)),
          meal: 'breakfast',
          label: 'Test protein',
          foodKey: 'b87-portion',
          quantity: 2,
          unit: unit,
          kcal: 240,
          proteinG: 44,
          group: 'Oatmeal',
        );
        await t.runAsync(() async {
          await NutritionDb.putFoodDef(db, def);
          await NutritionDb.put(db, entry);
        });
        var saves = 0;
        await t.pumpWidget(
          _app(
            app,
            Scaffold(
              body: SafeArea(
                child: MealCard(
                  date: entry.date,
                  meal: entry.meal,
                  entries: [entry],
                  onChanged: () => saves++,
                ),
              ),
            ),
            1,
            ShellDomain.nutrition,
            shell: false,
          ),
        );
        await t.tap(find.text('Test protein'));
        await _settle(t);
        expect(find.byType(GramsSheet), findsOneWidget);
        final amount = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is OsTextField && w.label.startsWith('Amount ('),
          ),
          matching: find.byType(TextField),
        );
        expect(t.widget<TextField>(amount).controller!.text, '2');
        await t.enterText(amount, '3');
        await t.pump();
        await t.tap(find.text('Save').last);
        await _settle(t);
        final rows = (await t.runAsync(
          () => NutritionDb.entriesForDay(db, entry.date),
        ))!;
        final changed = rows.singleWhere((e) => e.id == entry.id);
        expect(changed.quantity, 3);
        expect(changed.unit, unit);
        expect(changed.meal, entry.meal);
        expect(changed.group, entry.group);
        expect(changed.atTs, entry.atTs);
        if (unit == 'old unit') expect(changed.kcal, 360);
        expect(saves, 1);
        // Cancel the next edit without another write.
        await t.tap(find.text('Test protein'));
        await _settle(t);
        await t.tap(
          find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Close',
          ),
        );
        await t.pumpAndSettle();
        expect(saves, 1);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final window in ['10 min', '1 hour']) {
    testWidgets('recent HR $window works at accessible text and retains Day', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await t.pumpWidget(
        _app(app, HomeScreen(data: _home(), hour: 9), 2, ShellDomain.home),
      );
      await _settle(t);
      // Build 88's Today panel is taller; scroll to the card, not a distance.
      await t.scrollUntilVisible(
        find.text(window),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text(window));
      await t.pumpAndSettle();
      expect(find.text('Recorded minute averages'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(t.takeException(), isNull);
      await _capture(t, 'b87_hr_${window.replaceAll(' ', '_')}');
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
    'strict food marks do not turn a failed read into an automatic day',
    () async {
      final isolated = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await createNutritionTables(isolated);
      await isolated.close();
      expect(await NutritionDb.dayMarks(isolated, '0000-00-00'), isEmpty);
      await expectLater(
        NutritionDb.dayMarks(isolated, '0000-00-00', strict: true),
        throwsA(anything),
      );
    },
  );

  testWidgets('unknown intake is not a zero or a full remaining allowance', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(
          body: CalorieCard(eaten: null, goal: 2300, maintenance: 2600),
        ),
      ),
    );
    expect(find.text('Goal 2,300 · intake not recorded'), findsOneWidget);
    expect(find.text('Intake not recorded'), findsOneWidget);
    expect(find.textContaining('2,300 left'), findsNothing);
    expect(find.text('Maintenance not available'), findsNothing);
  });

  testWidgets('failed source reads retain the last chart and goal', (t) async {
    final app = AppState.forTesting()..repo = _Repo(failCharts: true);
    addTearDown(app.dispose);
    late BuildContext context;
    await t.pumpWidget(
      _app(
        app,
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
        1,
        ShellDomain.progress,
        shell: false,
      ),
    );
    final previous = _progress();
    final loaded = await t.runAsync(() async {
      await CalculationStore.write(GoalPlan.key, 'not valid JSON');
      try {
        return await ProgressData.load(context, previous: previous);
      } finally {
        await CalculationStore.remove(GoalPlan.key);
      }
    });
    expect(loaded!.steps, previous.steps);
    expect(loaded.sleepMin, previous.sleepMin);
    expect(loaded.recovery, previous.recovery);
    expect(loaded.goal, previous.goal);
    expect(
      loaded.readErrors,
      containsAll(['steps', 'sleep', 'recovery', 'Goal']),
    );
    expect(
      loaded.weights,
      isEmpty,
      reason: 'a successful empty read must replace the previous view',
    );
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'weekly block excludes future readings and dates its real predecessor',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting()..repo = _Repo();
      addTearDown(app.dispose);
      final today = todayLabel();
      final now = DateTime.parse(today);
      String label(int offset) =>
          dayLabelOf(DateTime(now.year, now.month, now.day + offset));
      final d = _progress();
      d.weights
        ..clear()
        ..addAll([
          for (final (offset, kg) in [(-21, 84.0), (0, 80.0), (1, 100.0)])
            (
              date: label(offset),
              kg: kg,
              atTs: _ts(now),
              unit: 'kg',
              entered: null,
              source: 'whoop',
              originId: null,
              historyOnly: true,
            ),
        ]);
      d.measures
        ..clear()
        ..addAll([
          BodyMeasure(
            date: label(1),
            recordedAt: now,
            inches: {'waistNavel': 70, 'neck': 30},
          ),
          BodyMeasure(date: today, recordedAt: now, inches: {'waistNavel': 34}),
          BodyMeasure(date: label(-21), recordedAt: now, inches: {'neck': 15}),
        ]);
      await t.pumpWidget(
        _app(app, ProgressScreen(data: d), 1, ShellDomain.progress),
      );
      await _settle(t);
      final block = find.textContaining('This week (from');
      // Build 88: the review leads Progress, so scroll to the weight block.
      await t.scrollUntilVisible(
        block,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final text = t.widget<Text>(block).data!;
      expect(text, contains('80 kg from 1 reading'));
      expect(text, contains('−4 vs '));
      expect(text, isNot(contains('previous week')));
      final prior = DateTime.parse(
        // B88-08: weight weeks run Monday–Sunday.
        BodyLogDb.blockStart(label(-21), DateTime.monday),
      );
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      expect(text, contains('vs ${months[prior.month - 1]} ${prior.day}'));
      await t.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byTooltip('Select Measurement'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byTooltip('Select Measurement'));
      await t.pumpAndSettle();
      await t.tap(find.text('Waist (navel)').last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.textContaining('Estimates from'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final estimate = t
          .widget<Text>(find.textContaining('Estimates from'))
          .data!;
      expect(estimate, contains('neck '));
      expect(estimate, contains((34 / (180 / 2.54)).toStringAsFixed(2)));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed refresh retains values and withholds combined advice', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = AppState.forTesting()..repo = _Repo();
    addTearDown(app.dispose);
    await t.pumpWidget(
      _app(
        app,
        ProgressScreen(data: _progress(failed: true)),
        1,
        ShellDomain.progress,
      ),
    );
    await _settle(t);
    expect(find.textContaining('Food could not refresh'), findsOneWidget);
    expect(find.textContaining('On track for recomposition'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  for (final (width, height, scale) in const [
    (390.0, 844.0, 1.0),
    (390.0, 844.0, 2.0),
    (390.0, 844.0, 3.1),
    (320.0, 740.0, 1.0),
    (430.0, 932.0, 2.0),
    (844.0, 390.0, 1.0),
  ]) {
    final tag = width == 390 ? '${scale}x' : '${width.toInt()}w_${scale}x';
    for (final (name, domain, build)
        in <(String, ShellDomain, Widget Function())>[
          ('today', ShellDomain.home, () => HomeScreen(data: _home(), hour: 9)),
          ('food', ShellDomain.nutrition, () => const NutritionScreen()),
          ('train', ShellDomain.workout, () => const WorkoutScreen()),
          ('trends', ShellDomain.health, () => HealthScreen(data: _trends())),
          // Build 88: the 30-day line + 7-day average and the 3-month weekly
          // band, both over data with real gaps.
          (
            'trends_30',
            ShellDomain.health,
            () => HealthScreen(data: _trends(days: 90, gaps: true), range: 2),
          ),
          (
            'trends_90',
            ShellDomain.health,
            () => HealthScreen(data: _trends(days: 90, gaps: true), range: 3),
          ),
          (
            'progress',
            ShellDomain.progress,
            () => ProgressScreen(data: _progress()),
          ),
          (
            'progress_empty',
            ShellDomain.progress,
            () => ProgressScreen(data: _progress(empty: true)),
          ),
        ]) {
      testWidgets('$name renders whole at $tag text without overflow', (
        t,
      ) async {
        t.view.physicalSize = Size(width * 1.5, height * 1.5);
        t.view.devicePixelRatio = 1.5;
        addTearDown(t.view.reset);
        final app = AppState.forTesting()
          ..repo = _Repo()
          ..user = {..._profile};
        addTearDown(app.dispose);
        final previousError = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint(details.toString());
          previousError?.call(details);
        };
        addTearDown(() => FlutterError.onError = previousError);
        await t.pumpWidget(_app(app, build(), scale, domain));
        await _settle(t);
        expect(t.takeException(), isNull);
        await _capture(t, 'b87_${name}_$tag');
        final scroll = find.byType(Scrollable).first;
        for (var i = 0; i < 4; i++) {
          await t.drag(scroll, const Offset(0, -500));
          await _settle(t);
          expect(t.takeException(), isNull);
        }
        await _capture(t, 'b87_${name}_${tag}_lower');
        await t.pumpWidget(const SizedBox.shrink());
        await _settle(t);
      });
    }
  }
}
