// Real SQLite -> repository absence/provenance contracts. Every input is
// authored; these checks preserve the existing zone and distribution methods.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'coverage_localized_progress_test.dart' show ago;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('zones-missing-anchors'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final mode in [
    'age-missing',
    'ceiling-short',
    'resting-0',
    'resting-13',
    'resting-14',
  ]) {
    test(
      'zones $mode name the missing anchor without manufacturing a distribution',
      () async {
        final repo = LocalRepositoryImpl(
          getProfileMap: () => {if (mode != 'age-missing') 'age': 30},
        );
        await LocalDb.putDayResult(
          dayId: todayLabel(),
          algoVersion: kAlgoVersion,
          payloadJson: jsonEncode({'device_family': 'gen4'}),
          windowJson: '{}',
          finalized: true,
        );
        if (mode != 'age-missing') {
          await LocalDb.putMetricSeriesValue(
            todayLabel(),
            'hr_ceiling_bpm',
            mode == 'ceiling-short' ? 180 : 196,
          );
        }
        final days = mode == 'resting-13'
            ? 13
            : mode == 'resting-14' || mode == 'ceiling-short'
            ? 14
            : 0;
        for (var i = 0; i < days; i++) {
          await LocalDb.putMetricSeriesValue(ago(i), 'rhr', 50);
        }
        final z = await repo.getZones();
        expect(z['distribution'], isNull);
        expect(z['device_family'], 'gen4');
        expect(z['resting_days'], days);
        expect(z['resting_min_days'], 14);
        final absent = z['absent'] as Map;
        final note = (absent['distribution'] as Map)['note'];
        if (mode == 'age-missing') {
          expect(z['zones'], isEmpty);
          expect(z['source'], isNull);
          expect(z['max_hr'], isNull);
          expect(z['note'], 'need_input:name=age');
          expect(note, 'need_input:name=age');
        } else if (mode == 'ceiling-short') {
          expect((z['ceiling'] as Map)['bpm'], 180);
          expect(z['source'], 'tanaka');
          expect(z['max_hr'], 187);
          expect(z['resting_hr'], isNull);
          expect(note, 'need_input:name=maximal_effort');
        } else {
          expect(z['source'], days < 14 ? 'observed' : 'karvonen');
          expect(z['max_hr'], 196);
          expect(z['resting_hr'], days < 14 ? isNull : 50);
          expect(z['zones'], hasLength(5));
          expect(z['note'], isNull);
          expect(
            note,
            days < 14
                ? 'need_input:name=resting_hr_days,have=$days,need=14'
                : 'need_input:name=sessions,have=0,need=8',
          );
        }
      },
    );
  }
}
