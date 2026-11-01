import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../tool/strain_comparison.dart';
import '../tool/strain_measurement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'measurement keeps the session floor and exposes whole-day cancellation',
    () {
      final ts = List.generate(600 * 60, (i) => 1800000000 + i);
      final quiet = List<double>.filled(ts.length, 60);
      final a = compareStrainForms(
        timestamps: ts,
        heartRates: quiet,
        restingHr: 50,
        maxHr: 190,
        female: false,
        sessionStrains: [4],
      );
      expect(a!['whole_with_floor'], closeTo(4, 1e-10));
      expect(a['excess_with_floor'], closeTo(4, 1e-10));
      final mixed = [
        for (var i = 0; i < ts.length; i++) i < 20 * 60 ? 150.0 : 50.0,
      ];
      final b = compareStrainForms(
        timestamps: ts,
        heartRates: mixed,
        restingHr: 50,
        maxHr: 190,
        female: false,
      )!;
      expect(b['per_minute_excess'], greaterThan(b['whole_day']!));
      expect(
        compareStrainForms(
          timestamps: [],
          heartRates: [],
          restingHr: 50,
          maxHr: 190,
          female: false,
        ),
        isNull,
      );
      expect(
        compareStrainForms(
          timestamps: [1],
          heartRates: [60],
          restingHr: 80,
          maxHr: 70,
          female: false,
        ),
        isNull,
      );
    },
  );
  test(
    'read-only runner uses sleep envelope, provenance and source exclusions',
    () async {
      sqfliteFfiInit();
      final root = await Directory.systemTemp.createTemp('synthetic-strain-');
      final path = '${root.path}/input.db';
      Database? db;
      try {
        db = await databaseFactoryFfi.openDatabase(path);
        await db.execute('CREATE TABLE baselines(key TEXT,payload_json TEXT)');
        await db.execute(
          'CREATE TABLE day_result(day_id TEXT,algo_version INTEGER,payload_json TEXT,window_json TEXT)',
        );
        await db.execute(
          'CREATE TABLE metric_series(date TEXT,key TEXT,value REAL)',
        );
        await db.execute(
          'CREATE TABLE decoded_onehz(rec_ts INTEGER,hr REAL,device_id TEXT,source TEXT)',
        );
        await db.execute(
          'CREATE TABLE sessions(start_ts INTEGER,status TEXT,strain REAL)',
        );
        const start = 1704153600;
        await db.insert('baselines', {
          'key': 'calculation:profile.calculation_history',
          'payload_json': jsonEncode({
            'baseline': {'age': 34, 'sex': 'm', 'resting_hr': 50},
          }),
        });
        await db.insert('day_result', {
          'day_id': '2024-01-02',
          'algo_version': 94,
          'payload_json': jsonEncode({
            'scalars': {'rhr_nocturnal': 50},
            'wear': {
              'segments': [
                {'start': start, 'end': start + 7200},
              ],
            },
          }),
          'window_json': jsonEncode({
            'value': {
              'onset_ms': start * 1000,
              'offset_ms': (start + 3600) * 1000,
            },
          }),
        });
        await db.insert('sessions', {
          'start_ts': start + 3600,
          'status': 'done',
          'strain': 3.0,
        });
        final batch = db.batch();
        for (var i = 0; i < 7200; i++) {
          batch.insert('decoded_onehz', {
            'rec_ts': start + i,
            'hr': i < 3600 ? 150 : 70,
            'device_id': 'synthetic-primary',
            'source': null,
          });
          batch.insert('decoded_onehz', {
            'rec_ts': start + i,
            'hr': 180,
            'device_id': 'synthetic-import',
            'source': 'imported',
          });
        }
        await batch.commit(noResult: true);
        await db.close();
        db = null;
        final result = await runReadOnlyStrainMeasurement(
          path,
          synthetic: true,
        );
        expect(result['source_metadata_unchanged'], true);
        final comparisons = result['comparisons'] as List;
        expect(comparisons, hasLength(1));
        expect(comparisons.single['cohort'], 'recorded_workout');
        expect(comparisons.single['covered_waking_minutes'], closeTo(60, 0.02));
        expect(comparisons.single['whole_with_floor'], closeTo(3, 1e-10));
        expect(comparisons.single['retained_fraction_of_window'], 1);
      } finally {
        await db?.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'private read-only measurement',
    () async {
      final path = Platform.environment['WHOOP_MEASUREMENT_DB'];
      if (path == null) return;
      await runReadOnlyStrainMeasurement(path);
    },
    skip: Platform.environment['WHOOP_MEASUREMENT_DB'] == null,
  );
}
