// Build 86 redesign: Today, Food and Train rendered whole at phone width with
// synthetic data. Run with --dart-define=UI_CAPTURE=true to write the pages to
// build/ui_capture/ for review; without it the test still pumps every page at
// 1x and 2x text and fails on any overflow.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/day_upkeep.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/gps/run_history.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/day_timeline.dart';
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

int _ts(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

class _Repo extends LocalRepository {
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
    graph: DayGraph(hr: hr),
    upkeep: DayUpkeep(
      Profile.fromMap(_profile),
      steps: 8642,
      eaten: 1450,
      date: todayLabel(),
    ),
    updatedAt: DateTime.now().subtract(const Duration(minutes: 12)),
  );
}

Widget _app(AppState app, Widget child, double scale) => MultiProvider(
  providers: [ChangeNotifierProvider<AppState>.value(value: app)],
  child: RepaintBoundary(
    key: const ValueKey('capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(
        body: ColoredBox(
          color: const P(true).bg,
          child: SafeArea(child: child),
        ),
      ),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build86_redesign_render_test.db';
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
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
      ('snacks', 'Protein bar', 210.0, 20.0, 16),
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

  for (final scale in const [1.0, 2.0]) {
    final tag = scale == 1.0 ? '1x' : '2x';
    for (final (name, build) in <(String, Widget Function())>[
      ('today', () => HomeScreen(data: _home(), hour: 9)),
      ('food', () => const NutritionScreen()),
      ('train', () => const WorkoutScreen()),
    ]) {
      testWidgets('$name renders whole at $tag text without overflow', (
        t,
      ) async {
        t.view.physicalSize = Size(390 * 1.5, (scale == 1 ? 2200 : 4200) * 1.5);
        t.view.devicePixelRatio = 1.5;
        addTearDown(t.view.reset);
        final app = AppState.forTesting()
          ..repo = _Repo()
          ..user = {..._profile};
        addTearDown(app.dispose);
        await t.pumpWidget(_app(app, build(), scale));
        await _settle(t);
        expect(t.takeException(), isNull);
        await _capture(t, 'b86_${name}_$tag');
        await t.pumpWidget(const SizedBox.shrink());
        await _settle(t);
      });
    }
  }
}
