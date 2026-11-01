import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/series_codec.dart';
import 'support/coverage_store.dart';

const day = '2021-04-06';
Map<String, dynamic> night() => {
  'date': day,
  'sleep_source': 'manual',
  'sleep': {
    'accounting': {
      'value': {'tst_sec': 7200},
    },
    'window': {
      'value': {'onset_ms': 1000, 'offset_ms': 9000000},
    },
  },
  'scalars': {'rhr': 52, 'rmssd': 44, 'readiness': 72, 'strain': 8},
  'naps': {'naps': [], 'nap_min': 0},
  'series': {
    'hr_curve': [
      {'t': 1, 'v': 66},
    ],
    'hypnogram': [
      {'stage': 'light'},
    ],
  },
};
Future<void> seed() async {
  await LocalDb.putDayResult(
    dayId: day,
    algoVersion: 100,
    payloadJson: jsonEncode(night()),
    windowJson: '{"onset_ms":1000,"offset_ms":9000000}',
    finalized: true,
    rhr: 52,
    rmssd: 44,
    readiness: 72,
    series: {'rhr': 52, 'rmssd': 44, 'readiness': 72, 'strain': 8},
    source: 'band',
  );
  await LocalDb.putSleepOverride(
    dayId: day,
    onsetTs: 1,
    offsetTs: 9000,
    source: 'manual',
  );
  await LocalDb.setFrozenHeadline(
    day,
    72,
    explanation: {'original': 'authored'},
  );
}

Future<void> accept(String action) => LocalDb.acceptSleepCorrection(
  dayId: day,
  action: action,
  onsetTs: 1,
  offsetTs: 9000,
);
Future<bool> publish(int generation, {int? revision, bool usable = true}) =>
    LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(
        usable
            ? (night()..['sleep_source'] = 'auto')
            : {
                'scalars': {'strain': 9},
              },
      ),
      windowJson: '{}',
      rhr: 52,
      rmssd: 44,
      readiness: 72,
      finalized: true,
      series: {'rhr': 52, 'rmssd': 44, 'readiness': 72, 'strain': 9},
      sleepIntentGeneration: generation,
      sleepRevision: revision,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('sleep-correction-preservation'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final action in ['rejected', 'clear', 'manual', 'confirmed']) {
    test(
      '$action preserves originals and immediately withholds stale night data',
      () async {
        await seed();
        final db = await LocalDb.instance;
        final before = await db.query('day_result');
        final pin = await LocalDb.getCursor(LocalDb.kFrozenHeadlineCursor);
        await accept(action);
        final row = (await LocalDb.dayResult(day))!;
        final b = SeriesCodec.decodePayloadJson(row['payload_json'])!;
        expect(row['partial'], 1);
        expect(row['finalized'], 0);
        expect(row['rmssd'], isNull);
        expect((b['scalars'] as Map)['readiness'], isNull);
        expect((b['scalars'] as Map)['strain'], 8);
        expect(
          (b['series'] as Map)['hr_curve'],
          night()['series']!['hr_curve'],
        );
        expect(await LocalDb.metricSeries('rmssd'), isEmpty);
        expect((await LocalDb.metricSeries('strain')).single['value'], 8);
        expect(await LocalDb.frozenHeadline(), isNull);
        expect(await LocalDb.dayResultIds(kAlgoVersion), isNot(contains(day)));
        final intent = (await LocalDb.sleepCorrection(day))!;
        final recovery = (intent['recovery'] as List).single as Map;
        expect(recovery['day_results'], before);
        expect((recovery['pin'] as List).single['value'], pin);
        final repo = LocalRepositoryImpl(getProfileMap: () => null);
        expect((await repo.getDaySleep(day))['has_sleep'], false);
        expect((await repo.getDayHrv(day))['rmssd'], isNull);
      },
    );
  }

  test(
    'refused preservation rolls back the command, output, pin and baselines',
    () async {
      await seed();
      final db = await LocalDb.instance;
      final before = await db.query('day_result');
      await db.execute(
        "CREATE TRIGGER refuse_sleep_intent BEFORE UPDATE ON metric_series WHEN NEW.key = 'rmssd' BEGIN SELECT RAISE(ABORT, 'authored refusal'); END",
      );
      try {
        await expectLater(accept('clear'), throwsA(isA<Exception>()));
        expect(await db.query('day_result'), before);
        expect((await LocalDb.getSleepOverride(day))?['source'], 'manual');
        expect((await LocalDb.frozenHeadline())?.value, 72);
        expect((await LocalDb.metricSeries('rmssd')).single['value'], 44);
        expect(await LocalDb.sleepCorrection(day), isNull);
      } finally {
        await db.execute('DROP TRIGGER refuse_sleep_intent');
      }
    },
  );

  test(
    'newer correction refuses old worker and keeps every recovery generation',
    () async {
      await seed();
      await accept('manual');
      await accept('clear');
      expect(await publish(1, revision: 1), false);
      expect((await LocalDb.sleepCorrection(day))?['generation'], 2);
      expect((await LocalDb.sleepCorrection(day))?['recovery'], hasLength(2));
      expect((await LocalDb.dayResult(day))?['rmssd'], isNull);
      expect(await publish(2, revision: 2), true);
      expect((await LocalDb.dayResult(day))?['rmssd'], 44);
      expect((await LocalDb.metricSeries('rmssd')).single['value'], 44);
      expect((await LocalDb.sleepCorrection(day))?['usable'], true);
    },
  );

  test(
    'missing automatic replacement remains unknown and cannot prune raw',
    () async {
      await seed();
      await accept('clear');
      expect(await publish(1, usable: false), true);
      expect((await LocalDb.dayResult(day))?['rmssd'], isNull);
      expect((await LocalDb.sleepCorrection(day))?['pending'], false);
      expect((await LocalDb.sleepCorrection(day))?['usable'], false);
      expect(await LocalDb.dayResultIds(kAlgoVersion), isNot(contains(day)));
      expect(
        (await LocalRepositoryImpl(
          getProfileMap: () => null,
        ).getDaySleep(day))['sleep_source'],
        'auto',
      );
    },
  );

  test(
    'rejection cannot publish a measured night even from matching worker',
    () async {
      await seed();
      await accept('rejected');
      expect(await publish(1), true);
      expect((await LocalDb.dayResult(day))?['readiness'], isNull);
      expect(
        (await LocalRepositoryImpl(
          getProfileMap: () => null,
        ).getDaySleep(day))['sleep_source'],
        'rejected',
      );
    },
  );

  test(
    'old candidate, morning pin and cross-day cache cannot revive after acceptance',
    () async {
      await seed();
      await accept('clear');
      await LocalDb.putSleepSessionCandidate(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: '{}',
      );
      expect(await LocalDb.sleepSessionCandidate(day, kAlgoVersion), isNull);
      await LocalDb.setFrozenHeadline(day, 99);
      await LocalDb.setFrozenHeadline(day, 99, sleepIntentGeneration: 1);
      expect(await LocalDb.frozenHeadline(), isNull);
      expect(await LocalDb.putBaseline('crossday', '{}'), false);
      expect(await LocalDb.baseline('crossday'), isNull);
      expect(
        await LocalDb.putBaseline(
          'crossday',
          '{"current":true}',
          sleepRevision: 1,
        ),
        true,
      );
      await accept('rejected');
      expect(
        await LocalDb.putBaseline('crossday', '{"old":true}', sleepRevision: 1),
        false,
      );
      expect(await LocalDb.baseline('crossday'), isNull);
    },
  );

  test(
    'full database export restores original recovery and current unknown output',
    () async {
      await seed();
      await accept('clear');
      final ledger = await LocalDb.sleepCorrection(day);
      final exported = await LocalDb.exportCopy();
      await LocalDb.wipeAll();
      await LocalDb.importFromDbFile(exported);
      expect(await LocalDb.sleepCorrection(day), ledger);
      expect(
        (await LocalRepositoryImpl(
          getProfileMap: () => null,
        ).getDaySleep(day))['has_sleep'],
        false,
      );
      expect((await LocalDb.dayResult(day))?['partial'], 1);
      expect(await LocalDb.metricSeries('rmssd'), isEmpty);
    },
  );

  test(
    'overlapping old backup refuses before changing a corrected day',
    () async {
      await seed();
      final oldBackup = await LocalDb.exportCopy();
      await accept('rejected');
      final before = await LocalDb.sleepCorrection(day);
      await expectLater(
        LocalDb.importFromDbFile(oldBackup),
        throwsA(isA<DbImportException>()),
      );
      expect(await LocalDb.sleepCorrection(day), before);
      expect(
        (await LocalRepositoryImpl(
          getProfileMap: () => null,
        ).getDaySleep(day))['has_sleep'],
        false,
      );
      expect(await LocalDb.metricSeries('rmssd'), isEmpty);
    },
  );
}
