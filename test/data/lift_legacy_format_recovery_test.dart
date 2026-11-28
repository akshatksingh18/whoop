// Existing import/read contracts preserve source bytes and unrelated history.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('lift-legacy-format-recovery'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  // Fallback templates deliberately allocate fresh IDs. Their contract is the
  // names,order,load meanings and setup notes,not a stable persisted identity.
  List<Map<String, Object?>> splitContents(List<LiftSplit> splits) => [
    for (final s in splits)
      {
        'name': s.name,
        'exercises': [
          for (final e in s.exercises)
            {
              'name': e.name,
              'loadMode': e.loadMode.name,
              'equipmentNote': e.equipmentNote,
            },
        ],
      },
  ];

  String source({bool offset = false, int reps = 9, double load = 23.5}) =>
      jsonEncode({
        'version': 1,
        'workouts': [
          {
            'id': 'authored-iso-lift',
            'startedAt': offset
                ? '2021-04-06T07:00:00-05:00'
                : '2021-04-06T12:00:00Z',
            'endedAt': offset
                ? '2021-04-06T07:30:00-05:00'
                : '2021-04-06T12:30:00Z',
            'notes': 'Authored source note',
            'exercises': [
              {
                'id': 'authored-iso-exercise',
                'name': 'Authored press',
                'loadMode': 'total',
                'equipmentNote': 'Authored bar',
                'sets': [
                  {
                    'id': 'authored-iso-set',
                    'reps': reps,
                    'load': load,
                    'completedAt': offset
                        ? '2021-04-06T07:10:00-05:00'
                        : '2021-04-06T12:10:00Z',
                  },
                ],
              },
            ],
          },
        ],
      });
  for (final offset in [false, true]) {
    test(
      'the retained ISO import offset=$offset keeps instants, units and idempotent history',
      () async {
        final text = source(offset: offset);
        final originalText = text;
        final db = await LocalDb.instance;
        await SessionStore.put({
          'id': 'authored-unrelated-lift-session',
          'start_ts': 1617714000,
          'status': 'live',
          'type': 'weight_training',
          'created_at': 1,
          'calories': null,
        });
        final sessions = await db.query('sessions');
        final before = await db.query('lift_log');
        final plan = await planLiftImport(text);
        expect(
          await db.query('lift_log'),
          before,
          reason: 'Preview does not apply data',
        );
        expect(plan.add, hasLength(1));
        final workout = plan.add.single;
        expect(workout.startedAt, DateTime.utc(2021, 4, 6, 12));
        expect(workout.endedAt, DateTime.utc(2021, 4, 6, 12, 30));
        expect(workout.notes, 'Authored source note');
        expect(workout.origin, 'akshatos');
        expect(workout.sessionId, isNull);
        final exercise = workout.exercises.single;
        expect(exercise.loadMode, LiftLoadMode.total);
        expect(exercise.equipmentNote, 'Authored bar');
        expect(exercise.sets.single.load, 23.5);
        expect(exercise.sets.single.reps, 9);
        expect(
          exercise.sets.single.completedAt,
          DateTime.utc(2021, 4, 6, 12, 10),
        );
        expect(await applyLiftImport(plan), 1);
        final stored = await db.query('lift_log');
        expect(stored.single['session_id'], isNull);
        expect((await planLiftImport(text)).unchanged, 1);
        expect(await applyLiftImport(await planLiftImport(text)), 0);
        expect(await db.query('lift_log'), stored);
        expect(await db.query('sessions'), sessions);
        expect(text, originalText);
      },
    );
  }
  for (final invalid in ['reps', 'load']) {
    test(
      'an imported invalid $invalid carries its actual validation diagnostic without writing a row',
      () async {
        final db = await LocalDb.instance;
        final before = await db.query('lift_log');
        final text = source(
          reps: invalid == 'reps' ? 0 : 9,
          load: invalid == 'load' ? -1 : 23.5,
        );
        await expectLater(
          planLiftImport(text),
          throwsA(
            isA<LiftLogError>().having(
              (e) => e.toString(),
              'user-facing diagnostic',
              invalid == 'reps'
                  ? 'Repetitions must be greater than zero.'
                  : 'Weight must be zero or greater.',
            ),
          ),
        );
        expect(await db.query('lift_log'), before);
      },
    );
  }
  for (final raw in ['{authored-invalid', '{}', '[null]', '0']) {
    test(
      'corrupt retained split shape $raw reads a fallback without overwriting the recovery anchor',
      () async {
        await CalculationStore.write(LiftLogDb.splitsKey, raw);
        final baseline = await MetricSeriesStore.baseline(
          'calculation:${LiftLogDb.splitsKey}',
        );
        final expected = splitContents(LiftSplit.starting);
        for (var reopening = 0; reopening < 2; reopening++) {
          final splits = await LiftLogDb.splits();
          expect(splitContents(splits), expected);
          expect(splits.map((s) => s.id).toSet(), hasLength(splits.length));
          expect(splits.every((s) => s.id.isNotEmpty), true);
          expect(await CalculationStore.read(LiftLogDb.splitsKey), raw);
          expect(
            await MetricSeriesStore.baseline(
              'calculation:${LiftLogDb.splitsKey}',
            ),
            baseline,
          );
          expect(await (await LocalDb.instance).query('lift_log'), isEmpty);
        }
      },
    );
  }
}
