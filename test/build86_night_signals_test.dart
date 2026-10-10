// B86-03: a night that starts before midnight keeps its pre-midnight signals.
// The Sleep screen used to read HR/HRV/respiration/temperature from the wake
// day's calendar bundle only, so the first hours of an 11 pm night were gone.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_night_signals_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  Future<void> day(String id, Map<String, Object?> series) =>
      LocalDb.putDayResult(
        dayId: id,
        algoVersion: kAlgoVersion,
        windowJson: '{}',
        payloadJson: jsonEncode({'series': series}),
      );

  test('signals span midnight and stay inside the night', () async {
    const wake = '2026-03-11';
    const before = '2026-03-10';
    final midnight = localDayStartSec(wake)!;
    final onset = midnight - 3600; // 23:00
    final wakeTs = midnight + 6 * 3600; // 06:00
    await day(before, {
      'hr_curve': [
        {'t': onset - 600, 'v': 80}, // before the night: excluded
        {'t': onset + 60, 'v': 58},
      ],
      'hrv_day': [
        {'t': onset + 300, 'v': 70},
        {'t': onset + 400, 'v': 900}, // artefact: clipped
      ],
    });
    await day(wake, {
      'hr_curve': [
        {'t': midnight + 3600, 'v': 52},
        {'t': wakeTs + 600, 'v': 75}, // after waking: excluded
      ],
      'hrv_day': [
        {'t': midnight + 7200, 'v': 64},
      ],
      'resp_day': [
        {'t': midnight + 7200, 'v': 14.5},
      ],
    });
    final s = await LocalRepositoryImpl(
      getProfileMap: () => const {},
    ).getNightSignals(onset, wakeTs);
    expect([for (final e in s['hr'] as List) e['v']], [58, 52]);
    expect([for (final e in s['hrv'] as List) e['v']], [70, 64]);
    expect((s['resp'] as List).single['v'], 14.5);
    expect(s.containsKey('skin_temp'), isFalse, reason: 'absent stays absent');
  });
}
