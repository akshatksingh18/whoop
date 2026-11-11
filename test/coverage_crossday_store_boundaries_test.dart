// Existing rollup orchestration from authored compact rows, not a raw sensor replay.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('crossday-store-boundaries'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  final calendar = DateTime.now();
  String label(int ago) =>
      dayLabelOf(DateTime(calendar.year, calendar.month, calendar.day - ago));
  Future<Map> baseline(String key) async =>
      jsonDecode((await LocalDb.baseline(key))!['payload_json'] as String)
          as Map;
  Future<void> nap(String date) async {
    final at = localDayStartSec(date)! + 14 * 3600;
    await LocalDb.putNapEdit(
      dayId: date,
      startTs: at,
      endTs: at + 1800,
      source: 'manual',
    );
  }

  Future<void> day(String date, int i, {bool finalized = true}) async {
    final midnight = localDayStartSec(date)!;
    await LocalDb.putDayResult(
      dayId: date,
      algoVersion: kAlgoVersion,
      finalized: finalized,
      rhr: 55.0 + i % 3,
      rmssd: 50,
      payloadJson: jsonEncode({
        'device_family': 'gen4',
        'scalars': {
          'rhr': 55 + i % 3,
          'rmssd': 50,
          'efficiency': 93.75,
          'nap_min': 0,
        },
        'sleep': {
          'window': {
            'value': {
              'onset_ms': (midnight - 3600) * 1000,
              'offset_ms': (midnight + 7 * 3600) * 1000,
            },
          },
          'accounting': {
            'value': {
              'tst_sec': 450 * 60,
              'in_bed_sec': 8 * 3600,
              'observed_in_bed_sec': 8 * 3600,
            },
          },
        },
      }),
      windowJson: '{}',
    );
  }

  test(
    'manual naps alone never satisfy the rollup history floor or invent a night',
    () async {
      await nap(label(0));
      await nap(label(1));
      await nap(label(100));
      await nap(label(-1));
      final engine = DerivationEngine();
      expect(await engine.rebuildCrossDay(const Profile()), 'needs_history');
      final status = await baseline('crossday_status');
      expect(status['kind'], 'needs_history');
      expect(
        status['days'],
        2,
        reason: 'Old/future corrections are outside the current rollup',
      );
      expect(await LocalDb.baseline('crossday'), isNull);
      expect((await baseline('crossday_input'))['days'], isEmpty);
      expect(await LocalDb.dayResult(label(0)), isNull);
    },
  );
  for (final hasToday in [false, true]) {
    test(
      'corrected Today naps ${hasToday ? 'replace its own saved scalar' : 'add no invented overnight physiology'} and live sessions stay outside morning associations',
      () async {
        for (var i = 0; i < 40; i++) {
          final ago = 39 - i;
          if (ago == 0 && !hasToday) continue;
          await day(label(ago), i, finalized: ago != 0);
        }
        // Ten eligible next mornings, all with a completed run and a separate
        // uncompleted session. Counting the latter would make every day ambiguous.
        for (var i = 14; i < 24; i++) {
          final start = localDayStartSec(label(39 - i))! + 10 * 3600;
          for (final live in [false, true]) {
            await LocalDb.putSession({
              'id': 'authored-$i-$live',
              'start_ts': start,
              'end_ts': live ? null : start + 1800,
              'type': live ? 'yoga' : 'running',
              'status': live ? 'live' : 'done',
              'created_at': start * 1000,
            });
          }
        }
        await nap(label(0));
        final engine = DerivationEngine();
        expect(
          await engine.rebuildCrossDay(
            const Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70),
          ),
          'ready',
        );
        final out = await baseline('crossday');
        expect(out['n_days'], 40);
        expect(out['built_for_day'], label(0));
        expect(out['algo_version'], kAlgoVersion);
        final latest = (out['recent'] as List).last as Map;
        expect(latest['date'], label(0));
        expect(latest['unsettled'], isTrue);
        expect(latest['rhr'], hasToday ? 55 : isNull);
        expect((out['sleep_coach'] as Map)['nap_credit_min'], 30);
        final effects =
            ((out['session_cost'] as Map)['rhr'] as Map)['value'] as List;
        expect(effects, hasLength(1));
        expect((effects.single as Map)['n'], 10);
        expect((effects.single as Map)['session_type'], 'running');
        final artifact = await baseline('crossday_input');
        final rows = artifact['days'] as List;
        if (hasToday) {
          expect((rows.last as Map)['is_today'], isTrue);
          expect((rows.last as Map)['unsettled'], isTrue);
          expect((rows.last as Map)['nap_min'], 0);
        } else {
          expect(rows, hasLength(39));
          expect(rows.any((r) => (r as Map)['is_today'] == true), isFalse);
        }
        // A second rebuild must neither multiply nap credit nor count live sessions.
        expect(
          await engine.rebuildCrossDay(
            const Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70),
          ),
          'ready',
        );
        expect(
          ((await baseline('crossday'))['sleep_coach']
              as Map)['nap_credit_min'],
          30,
        );
      },
    );
  }
}
