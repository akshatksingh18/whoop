// Measurement-only reader. Never opens LocalDb or runs app migrations.
import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/hr_max.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/series_codec.dart';
import 'strain_comparison.dart';

Future<void> main() async {
  final path = Platform.environment['WHOOP_MEASUREMENT_DB'];
  if (path == null)
    throw ArgumentError('Set WHOOP_MEASUREMENT_DB to a local export');
  await runReadOnlyStrainMeasurement(path);
}

Future<Map<String, dynamic>> runReadOnlyStrainMeasurement(
  String path, {
  bool synthetic = false,
}) async {
  // Fixed output path; callers cannot redirect private results elsewhere.
  final root = Directory('build/research-local').absolute.path;
  final destination = File(
    '$root/${synthetic ? 'synthetic-strain-comparison' : 'strain-comparison'}.json',
  );
  await destination.parent.create(recursive: true);
  Database? db;
  try {
    sqfliteFfiInit();
    final before = await File(path).stat();
    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    await db.execute('PRAGMA query_only = ON');
    final historyRows = await db.query(
      'baselines',
      where: 'key = ?',
      whereArgs: ['calculation:profile.calculation_history'],
    );
    final history = historyRows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(historyRows.first['payload_json'] as String) as Map,
          );
    final days = await db.rawQuery(
      'SELECT d.* FROM day_result d WHERE '
      'd.algo_version = (SELECT MAX(n.algo_version) FROM day_result n WHERE n.day_id = d.day_id) '
      'ORDER BY d.day_id',
    );
    final results = <Map<String, dynamic>>[];
    final skipped = <String, int>{};
    void skip(String why) => skipped[why] = (skipped[why] ?? 0) + 1;
    for (final row in days) {
      final date = row['day_id'] as String;
      final b = SeriesCodec.decodePayloadJson(row['payload_json']);
      final sc = b?['scalars'] as Map?;
      final wear = b?['wear'] as Map?;
      final segments = wear?['segments'] as List?;
      if (b == null || segments == null || segments.isEmpty) {
        skip('missing_absolute_bounds');
        continue;
      }
      final start = (segments.first as Map)['start'] as num?;
      final end = (segments.last as Map)['end'] as num?;
      if (start == null || end == null || end <= start) {
        skip('missing_absolute_bounds');
        continue;
      }
      final dates =
          history.keys
              .where(
                (k) =>
                    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(k) &&
                    k.compareTo(date) <= 0,
              )
              .toList()
            ..sort();
      final pm = history[dates.isEmpty ? 'baseline' : dates.last];
      if (pm is! Map) {
        skip('missing_dated_profile');
        continue;
      }
      final profile = Profile.fromMap(Map<String, dynamic>.from(pm));
      final rhr =
          (sc?['rhr_nocturnal'] as num?)?.toDouble() ??
          profile.restingHrManual?.toDouble();
      final ceilings = await db.rawQuery(
        'SELECT MAX(value) AS v FROM metric_series WHERE key = ? AND date < ?',
        ['hr_ceiling_bpm', date],
      );
      final maxHr = trainingZones(
        age: profile.ageYears,
        deviceFamily: b['device_family'] as String?,
        observedCeilingBpm: (ceilings.first['v'] as num?)?.toDouble(),
      )?.maxHr;
      if (rhr == null ||
          maxHr == null ||
          !['m', 'f', 'male', 'female'].contains(profile.sex)) {
        skip('missing_anchors');
        continue;
      }
      final raw = await db.rawQuery(
        'SELECT rec_ts,hr,device_id FROM decoded_onehz WHERE source IS NULL '
        'AND rec_ts >= ? AND rec_ts < ? AND hr > 0 ORDER BY rec_ts',
        [start, end],
      );
      if (raw.isEmpty) {
        skip('raw_not_retained');
        continue;
      }
      if (raw.map((r) => r['device_id']).toSet().length != 1) {
        skip('ambiguous_device');
        continue;
      }
      final envelope = jsonDecode(row['window_json'] as String) as Map;
      final window = envelope['value'] is Map
          ? envelope['value'] as Map
          : envelope;
      final onset = (window['onset_ms'] as num?)?.toDouble();
      final offset = (window['offset_ms'] as num?)?.toDouble();
      final awake = raw.where((r) {
        final t = (r['rec_ts'] as num).toInt() * 1000;
        return onset == null || offset == null || t < onset || t >= offset;
      }).toList();
      final sessions = await db.rawQuery(
        'SELECT strain FROM sessions WHERE status = ? AND start_ts >= ? AND start_ts < ?',
        ['done', start, end],
      );
      final comparison = compareStrainForms(
        timestamps: [for (final r in awake) (r['rec_ts'] as num).toInt()],
        heartRates: [for (final r in awake) (r['hr'] as num).toDouble()],
        restingHr: rhr,
        maxHr: maxHr,
        female: profile.sex == 'f' || profile.sex == 'female',
        sessionStrains: [
          for (final s in sessions)
            if (s['strain'] is num) (s['strain'] as num).toDouble(),
        ],
      );
      if (comparison == null) {
        skip('no_usable_waking_input');
        continue;
      }
      results.add({
        'date': date,
        'stored_algorithm': row['algo_version'],
        'cohort': sessions.isEmpty
            ? 'no_recorded_workout_quiet_candidate'
            : 'recorded_workout',
        'retained_fraction_of_window': raw.length / (end - start),
        'stored_strain': sc?['strain'],
        ...comparison,
      });
    }
    await db.close();
    db = null;
    final after = await File(path).stat();
    await destination.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'measurement_only': true,
        'quiet_reference': 'shipped fixed quietWakingHrr',
        'limits': [
          'Quiet candidates are not user-confirmed quiet days.',
          'Retained raw may cover only part of the stored day; outputs are lower bounds.',
          'Existing session floor is retained. No headline formula change is authorized.',
        ],
        'source_metadata_unchanged':
            before.size == after.size && before.modified == after.modified,
        'skipped': skipped,
        'comparisons': results,
      }),
    );
    return Map<String, dynamic>.from(
      jsonDecode(await destination.readAsString()) as Map,
    );
  } catch (e) {
    await File('$root/strain-measurement-error.txt').writeAsString('$e');
    throw StateError(
      'Measurement failed; details remain in the ignored local research directory',
    );
  } finally {
    await db?.close();
  }
}
