// A REASON MUST REACH THE FIGURE IT EXPLAINS.
//
// The measured failure: `calories`, `calories_total`, `zones` and `max_hr_used`
// went absent with no tier and no note, while the gate that killed all four
// wrote `unknown_device_family:id=none` onto `heart.daytime_hrv` and
// `hr_ceiling` — neither of which any screen that renders them reads. The
// screens then guessed, and printed causes that were not true.
//
// This is the producer side of that contract (`absence_reason_test.dart` is the
// renderer side): the serve seam must hand every ABSENT figure its OWN reason,
// hand a PRESENT figure none, and say it does not know rather than borrow a
// sibling's when the bundle never recorded one.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/models/metric.dart';

Future<void> _put(String day, Map<String, dynamic> payload) =>
    LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(payload),
      windowJson: '{}',
      finalized: true,
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_absence_routing_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  final repo = LocalRepositoryImpl(getProfileMap: () => const {'age': 30});

  test('each absent figure carries its OWN reason, and a present one carries '
      'none', () async {
    // One upstream gate (no resting HR) killed strain and TRIMP; a different
    // one (no height) killed the two calorie figures. Zones survived. This is
    // exactly the shape that used to reach the screen as four bare nulls.
    await _put('2020-03-01', {
      'zones': {'z1': 10, 'z2': 5, 'z3': 0, 'z4': 0, 'z5': 0},
      'max_hr_used': 187.0,
      'absent_notes': {
        'strain': 'need_input:name=resting_hr',
        'trimp': 'need_input:name=resting_hr',
        'calories': 'need_input:name=height_cm',
        'calories_total': 'need_input:name=height_cm',
      },
      'scalars': {'steps': 100.0},
    });

    final s = await repo.getDayStrain('2020-03-01');
    final absent = (s['absent'] as Map).cast<String, dynamic>();

    // Each figure's reason is under that figure's OWN key — never inferred
    // from a sibling, and keyed the way the value is keyed (`training_load`,
    // not `trimp`).
    expect(Metric.parse(absent['strain']).note, 'need_input:name=resting_hr');
    expect(
      Metric.parse(absent['training_load']).note,
      'need_input:name=resting_hr',
    );
    expect(Metric.parse(absent['calories']).note, 'need_input:name=height_cm');
    expect(
      Metric.parse(absent['calories_total']).note,
      'need_input:name=height_cm',
    );
    // …and it parses as an ABSENT metric with a tier, not as a bare string.
    expect(Metric.parse(absent['strain']).isEmpty, isTrue);
    expect(Metric.parse(absent['strain']).tier, MetricTier.estimate);
    // The reason turns into a sentence that names the missing INPUT.
    expect(whyFromNote(Metric.parse(absent['calories']).note),
        contains('height'));

    // Figures that ARE present get no entry at all — an explanation for an
    // absence that did not happen is its own kind of lie.
    expect(absent.containsKey('zones'), isFalse);
    expect(absent.containsKey('max_hr_used'), isFalse);

    // The headline's reason is also promoted to the top level, because with no
    // strain the whole screen is one card explaining why.
    expect(s['note'], 'need_input:name=resting_hr');
  });

  test('a bundle that recorded no reason says it does not know — it never '
      'borrows one', () async {
    await _put('2020-03-02', {
      'scalars': {'steps': 100.0},
    });
    final s = await repo.getDayStrain('2020-03-02');
    expect((s['absent'] as Map), isEmpty);
    expect(s['note'], isNull);
    // Which is what the renderer turns into "nothing recorded says why".
    expect(whyFromNote(s['note'] as String?), isNull);
  });

  test('an IMPORTED day names the import, which is a fact about the row',
      () async {
    // 284 of whoop-5's 287 days are this: an export file that carried sleep
    // only, with no raw to re-derive from, so nothing here ever fills in.
    await _put('2020-03-03', {
      'imported': true,
      'scalars': {'tst_min': 400.0},
    });
    final s = await repo.getDayStrain('2020-03-03');
    final absent = (s['absent'] as Map).cast<String, dynamic>();
    for (final k in const [
      'strain',
      'training_load',
      'calories',
      'calories_total',
      'zones',
      'max_hr_used',
    ]) {
      expect(
        Metric.parse(absent[k]).note,
        'need_input:name=imported_day',
        reason: '$k must say the day came from an import',
      );
    }
  });
}
