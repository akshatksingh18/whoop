// Dated weight edits and original measurement rows have separate provenance.
// All anchors/rows are authored; the actual calculation-store/SQLite readers run.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/profile_history.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('profile-weight-precedence'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';
  const fallback = Profile(weightKg: 65, ageYears: 31, heightCm: 172, sex: 'm');
  for (final (editDay, editTs, measuredTs, expected) in [
    ('2021-04-05', 500, 100, 70.0),
    ('2021-04-06', 99, 100, 70.0),
    ('2021-04-06', 100, 100, 70.0),
    ('2021-04-06', 101, 100, 80.0),
    ('2021-04-06', 1, 0, 80.0),
    ('2021-04-07', 500, 100, 70.0),
  ]) {
    test(
      'dated profile $editDay/$editTs versus measurement $measuredTs selects $expected without rewriting history',
      () async {
        final db = await LocalDb.instance;
        await db.insert('body_weight', {
          'date': day,
          'kg': 70,
          'at_ts': measuredTs,
          'source': 'authored',
          'history_only': 0,
        });
        final profile = {...fallback.toMap(), 'weight_kg': 80};
        await CalculationStore.write(
          ProfileHistory.key,
          jsonEncode({
            'baseline': profile,
            'weight_edits': {
              editDay: {'kg': 80, 'at_ts': editTs},
            },
          }),
        );
        final before = await CalculationStore.read(ProfileHistory.key);
        final row = (await db.query('body_weight')).single;
        final selected = await ProfileHistory.on(day, fallback);
        expect(selected.weightKg, expected);
        expect(selected.ageYears, fallback.ageYears);
        expect(selected.heightCm, fallback.heightCm);
        expect(selected.sex, fallback.sex);
        expect(await CalculationStore.read(ProfileHistory.key), before);
        expect((await db.query('body_weight')).single, row);
      },
    );
  }
  test(
    'a later applicable profile date overrides an older original weight; future edits do not',
    () async {
      final db = await LocalDb.instance;
      await db.insert('body_weight', {
        'date': '2021-04-04',
        'kg': 70,
        'at_ts': 100,
        'history_only': 0,
      });
      await ProfileHistory.record(fallback.toMap(), {
        ...fallback.toMap(),
        'weight_kg': 80,
      }, now: DateTime(2021, 4, 5, 12));
      await ProfileHistory.record(
        {...fallback.toMap(), 'weight_kg': 80},
        {...fallback.toMap(), 'weight_kg': 90},
        now: DateTime(2021, 4, 7, 12),
      );
      expect((await ProfileHistory.on(day, fallback)).weightKg, 80);
      expect((await ProfileHistory.on('2021-04-04', fallback)).weightKg, 70);
      expect((await ProfileHistory.on('2021-04-07', fallback)).weightKg, 90);
      expect(await db.query('body_weight'), hasLength(1));
    },
  );
}
