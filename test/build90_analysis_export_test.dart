import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/analysis_export.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/temporary_export.dart';
import 'package:whoop_companion/data/media_backup.dart';
import 'package:whoop_companion/ui2/profile/data.dart';

void main() {
  const profile = Profile(ageYears: 30, sex: 'm', weightKg: 70, heightCm: 175);
  String render({
    List<AnalysisDay> days = const [],
    List<LiftWorkout> lifts = const [],
    List<Map<String, Object?>> readings = const [],
  }) => buildAnalysisMarkdown(
    range: AnalysisRange.twoWeeks,
    from: '2025-01-01',
    today: '2025-01-14',
    profile: profile,
    targets: const {},
    goal: null,
    days: days,
    lifts: lifts,
    measures: const [],
    weightReadings: readings,
  );
  test(
    'each nutrient keeps partial totals and its own counted-day denominator',
    () {
      final a = AnalysisDay('2025-01-06')
        ..kcal = 2000
        ..protein = 80
        ..counted = true;
      a.nutrients.addAll({
        'kcal': const NutrientTotal(2000, 2, 0),
        'protein': const NutrientTotal(80, 1, 1),
      });
      final b = AnalysisDay('2025-01-07')
        ..kcal = 2200
        ..protein = 120
        ..counted = true;
      b.nutrients.addAll({
        'kcal': const NutrientTotal(2200, 2, 0),
        'protein': const NutrientTotal(120, 2, 0),
      });
      final c = AnalysisDay('2025-01-13')
        ..kcal = 1000
        ..counted = false;
      final md = render(days: [a, b, c]);
      expect(md, contains('≥80 (1/2 items)'));
      expect(md, contains('2100 (2/2 days) | 120 (1/2 days)'));
      expect(md, contains('— (0/2 days)'));
    },
  );
  test(
    'every historical weigh-in retains source and calculation eligibility',
    () {
      final md = render(
        readings: [
          {
            'id': 'one',
            'date': '2025-01-06',
            'at_ts': 100,
            'kg': 70.1,
            'source': 'synthetic import',
            'history_only': 1,
            'entered': 154.5,
            'unit': 'lb',
          },
          {
            'id': 'two',
            'date': '2025-01-06',
            'at_ts': 200,
            'kg': 70.4,
            'source': 'whoop',
            'history_only': 0,
            'entered': 70.4,
            'unit': 'kg',
          },
        ],
      );
      expect(md, contains('70.10 | synthetic import | history only'));
      expect(md, contains('70.40 | whoop | additional reading (history)'));
      expect(md, contains('first weigh-in'));
    },
  );
  test('lifts share best-set rules, including high reps and load meaning', () {
    final at = DateTime(2025, 1, 6);
    final w = LiftWorkout(
      startedAt: at,
      exercises: [
        LiftExercise(
          name: 'Synthetic press',
          loadMode: LiftLoadMode.perHand,
          equipmentNote: 'Dumbbells',
          sets: [
            LiftSet(load: 55, reps: 10, completedAt: at),
            LiftSet(load: 60, reps: 15, completedAt: at),
          ],
        ),
      ],
    );
    final md = render(lifts: [w]);
    expect(
      md,
      contains(
        'best set 60 lb/hand × 15; Weight per hand; Dumbbells; comparison: reps at load',
      ),
    );
    expect(md, isNot(contains('estimated one-rep load 90.0')));
    expect(md, contains('do not add both dumbbells'));
  });
  for (final outcome in ['selected', 'cancelled', 'unavailable', 'failure']) {
    test('temporary copies are removed after $outcome', () async {
      final dir = await Directory.systemTemp.createTemp(
        'synthetic-export-test',
      );
      final f = await File(
        '${dir.path}/synthetic.txt',
      ).writeAsString('synthetic');
      try {
        final result = withTemporaryExport([f.path], () async {
          expect(await f.exists(), true);
          if (outcome == 'failure') throw StateError('synthetic share failure');
          return outcome;
        });
        if (outcome == 'failure') {
          await expectLater(result, throwsStateError);
        } else {
          expect(await result, outcome);
        }
        expect(await f.exists(), false);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  }
  test(
    'analysis rendering crosses the isolate boundary with synthetic inputs',
    () async {
      final md = await renderAnalysisOffThread(
        range: AnalysisRange.twoWeeks,
        from: '2025-01-01',
        today: '2025-01-14',
        profile: profile,
        targets: const {},
        goal: null,
        days: [
          AnalysisDay('2025-01-01')
            ..kcal = 1000
            ..counted = false,
        ],
        lifts: const [],
        measures: const [],
        foods: const {},
        weightReadings: const [],
      );
      expect(md, contains('2025-01-01'));
    },
  );
  test('a failed media pack removes its partial generated archive', () async {
    final dir = await Directory.systemTemp.createTemp(
      'synthetic-media-failure',
    );
    try {
      final path = '${dir.path}/absent.db';
      await expectLater(
        packMediaBackupWithCount(path, '${dir.path}/photos'),
        throwsA(anything),
      );
      expect(await File('$path.zip').exists(), false);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('media packing reports actual included photo files', () async {
    final dir = await Directory.systemTemp.createTemp('synthetic-media-test');
    try {
      final db = await File(
        '${dir.path}/synthetic.db',
      ).writeAsString('synthetic');
      final photos = await Directory('${dir.path}/photos').create();
      await File('${photos.path}/abcdefgh.jpg').writeAsBytes([1, 2, 3]);
      await File('${photos.path}/ignored.txt').writeAsString('not a photo');
      expect(await mediaBackupPhotoCount(photos.path), 1);
      final packed = await packMediaBackupWithCount(db.path, photos.path);
      expect(packed.photos, 1);
      expect(await File(packed.path).exists(), true);
    } finally {
      await dir.delete(recursive: true);
    }
    expect(
      DataScreen,
      isNotNull,
    ); // compile the actual share/description consumer.
  });
}
