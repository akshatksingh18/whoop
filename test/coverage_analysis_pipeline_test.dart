// Read actual synthetic stores through the analysis-export pipeline and isolate.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/analysis_export.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/prefs.dart';

class _Repo extends LocalRepository {
  String day = '';
  bool fail = false;
  @override
  Future<Map<String, dynamic>> getChart(
    String key, {
    int? from,
    int? to,
  }) async {
    if (fail) throw StateError('synthetic chart read refusal');
    return {
      'points': [
        null,
        {'t': 0, 'v': null},
        {
          't': localDayStartSec(day),
          'v': switch (key) {
            'steps' => 4567,
            'sleep' => 420,
            'recovery' => 63,
            'hrv' => 51,
            'resting_hr' => 55,
            'strain' => 6.3,
            _ => 0,
          },
        },
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late String today, day;
  late _Repo repo;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory(
      'build/coverage-expansion/analysis',
    ).create(recursive: true);
    LocalDb.dbName = '${root.absolute.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    today = todayLabel();
    day = shiftLabel(today, -2);
    repo = _Repo()..day = day;
    await BodyLogDb.putWeight(
      day,
      70.1,
      'kg',
      source: 'synthetic-import',
      historyOnly: true,
      at: DateTime.parse(day).add(const Duration(hours: 7)),
    );
    await BodyLogDb.putWeight(
      day,
      70.4,
      'kg',
      source: 'synthetic-import',
      historyOnly: true,
      at: DateTime.parse(day).add(const Duration(hours: 18)),
    );
    await BodyLogDb.putMeasure(
      BodyMeasure(
        id: 'synthetic-tape',
        date: day,
        recordedAt: DateTime.parse(day),
        inches: {BodySite.waistNavel.name: 33.1},
      ),
    );
    await NutritionDb.put(
      db,
      FoodEntry(
        id: 'known',
        date: day,
        meal: 'lunch',
        label: 'Synthetic known | food',
        kcal: 400,
        proteinG: 20,
        atTs: localDayStartSec(day)! + 13 * 3600,
      ),
    );
    await NutritionDb.put(
      db,
      FoodEntry(
        id: 'partial',
        date: day,
        meal: 'dinner',
        label: 'Synthetic partial food',
        kcal: 600,
        atTs: localDayStartSec(day)! + 19 * 3600,
      ),
    );
    await NutritionDb.setDayMark(db, day, 'complete');
    final at = localDayStartSec(day)! + 10 * 3600;
    for (final (id, kind, privacy, status) in [
      ('visible', 'synthetic walk', 0, 'done'),
      ('private', 'synthetic secret', 1, 'done'),
      ('live', 'synthetic unfinished', 0, 'live'),
    ]) {
      await LocalDb.putSession({
        'id': id,
        'start_ts': at,
        'end_ts': at + 1200,
        'type': kind,
        'private': privacy,
        'status': status,
        'strain': 3.2,
        'source': 'manual',
        'created_at': at * 1000,
      });
      if (id == 'live') continue;
      final w = LiftWorkout(
        id: 'lift-$id',
        sessionId: id,
        startedAt: DateTime.fromMillisecondsSinceEpoch(at * 1000),
      );
      final e = w.addExercise(
        name: id == 'private'
            ? 'Synthetic hidden press'
            : 'Synthetic public press',
        loadMode: LiftLoadMode.perHand,
      );
      w.addSet(
        e,
        reps: 8,
        load: 20,
        at: w.startedAt.add(const Duration(minutes: 1)),
      );
      w.finish(w.startedAt.add(const Duration(minutes: 20)));
      await LiftLogDb.save(w);
    }
  });
  tearDownAll(LocalDb.close);
  const user = {
    'age': 30,
    'sex': 'f',
    'height_cm': 170,
    'kcal_target': 2100,
    'protein_target': 120,
  };
  for (final range in AnalysisRange.values) {
    test(
      '${range.label} exports actual readings, denominators and public completed sessions only',
      () async {
        final path = await writeAnalysisExport(
          range: range,
          repo: repo,
          user: user,
        );
        try {
          final text = await File(path).readAsString();
          expect(
            text,
            contains(
              '| $day | 70.1 | 33.1 | 1000 (2/2 items) | ≥20 (1/2 items)',
            ),
          );
          expect(text, contains('Marked complete'));
          expect(text, contains('synthetic-import | history only'));
          expect(text, contains('70.10'));
          expect(text, contains('70.40'));
          expect(text, contains('4567 | 7h 00m | 63 | 51 | 55 | 6.3'));
          expect(text, contains('synthetic walk 20 min strain 3.2'));
          expect(text, isNot(contains('synthetic secret')));
          expect(text, isNot(contains('synthetic unfinished')));
          expect(text, contains('Synthetic public press'));
          expect(text, isNot(contains('Synthetic hidden press')));
          expect(text.contains('## Food log'), range.listsFoods);
          expect(
            text,
            contains(
              'Period: ${range.days == null ? day : shiftLabel(today, -(range.days! - 1))} to $today',
            ),
          );
        } finally {
          await File(path).parent.delete(recursive: true);
        }
      },
    );
  }
  test(
    'a failed chart read is a failed export, not a report of missing measurements',
    () async {
      repo.fail = true;
      await expectLater(
        writeAnalysisExport(
          range: AnalysisRange.twoWeeks,
          repo: repo,
          user: user,
        ),
        throwsStateError,
      );
      expect((await BodyLogDb.weights()), hasLength(1));
      expect(await db.query('body_weight_reading'), hasLength(2));
    },
  );
}
