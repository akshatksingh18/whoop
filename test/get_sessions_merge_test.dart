// getSessions: the saved sessions table, newest first — and nothing else.
//
// This file used to test a MERGE with `detected_workouts` out of each recent
// day bundle. That key was a permanently-empty stub, the derivation has stopped
// writing it (analytics deleted `workout_detect.dart`), and the merge therefore
// read every recent bundle's whole payload through jsonDecode to append
// nothing. What is tested now is what survives: saved sessions only, and a
// legacy bundle that still carries the key does not resurrect it.
//
// Runs the REAL LocalDb against in-memory sqlite.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_sessions_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('getSessions returns the saved sessions newest-first, and never revives '
      "a legacy bundle's detected_workouts", () async {
    final repo = LocalRepositoryImpl(getProfileMap: () => const {});

    // Anchor near "now" so the default month window includes it.
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = nowSec - 3600; // 1 h ago
    final date = _ymd(DateTime.fromMillisecondsSinceEpoch(base * 1000));

    await LocalDb.putSession({
      'id': 'manual1',
      'start_ts': base,
      'end_ts': base + 1200,
      'type': 'run',
      'status': 'done',
      'source': 'manual',
      'created_at': base * 1000,
    });
    await LocalDb.putSession({
      'id': 'manual2',
      'start_ts': base + 2000,
      'end_ts': base + 2600,
      'type': 'walk',
      'status': 'done',
      'source': 'manual',
      'created_at': (base + 2000) * 1000,
    });

    // A day derived before the key was dropped, still carrying a bout.
    await LocalDb.putDayResult(
      dayId: date,
      algoVersion: 1,
      payloadJson: jsonEncode({
        'date': date,
        'detected_workouts': [
          {
            'start': base + 4000,
            'end': base + 4600,
            'sport': 'detected',
            'strain': 9.1,
          },
        ],
      }),
      windowJson: '{}',
    );

    final sessions = await repo.getSessions();
    expect(sessions.map((s) => s['id']), ['manual2', 'manual1']);
    expect(sessions.any((s) => s['source'] == 'auto'), isFalse);

    // The flag is part of the repository interface and callers still pass it;
    // there is no detected half left for it to exclude.
    final savedOnly = await repo.getSessions(includeDetected: false);
    expect(savedOnly.map((s) => s['id']), ['manual2', 'manual1']);
  });
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
