// B88-05: a night with no sleep recorded must never present an EARLIER
// night's numbers as today's.
//
// Before the repair, a today row flagged NO_SLEEP_DETECTED marked the overnight
// "ready" for today (`showing_prior_overnight=false`) while the repository
// served the newest earlier night that had sleep — so its readiness, HRV and
// resting HR printed in Today's slot with no held-over note.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart' show kAlgoVersion;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart'
    show heldOverNightOf, staleOvernightNote;

String _label(DateTime d) => dayLabelOf(d);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_b88_freshness_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  test('a no-sleep today holds over the earlier scored night', () async {
    final db = await LocalDb.instance;
    await db.delete('day_result');
    final today = todayLabel();
    final yesterday = _label(DateTime.now().subtract(const Duration(days: 1)));
    await LocalDb.putDayResult(
      dayId: yesterday,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': {'readiness': 72},
        'sleep': {
          'accounting': {
            'value': {'tst_sec': 25000},
          },
        },
      }),
      windowJson: '{}',
    );
    await LocalDb.putDayResult(
      dayId: today,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'scalars': <String, dynamic>{},
        'flags': ['NO_SLEEP_DETECTED'],
      }),
      windowJson: '{}',
    );
    await LocalDb.refreshComputeFreshness();
    final row = (await LocalDb.computeFreshness('today'))!;
    final status = (jsonDecode(row['payload_json'] as String) as Map)
        .cast<String, dynamic>();

    expect(status['overnight_day'], yesterday,
        reason: 'the overnight is the night that actually has sleep');
    expect(status['showing_prior_overnight'], isTrue);
    expect(status['overnight_no_sleep_today'], isTrue);

    final todayMap = {'status': status};
    expect(heldOverNightOf(todayMap), yesterday);
    expect(staleOvernightNote(todayMap), 'No sleep was recorded last night.');
  });
}
