import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/series_codec.dart';
import '../support/coverage_store.dart';

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
  await SleepOverrideStore.putOverride(
    dayId: day,
    onsetTs: 1,
    offsetTs: 9000,
    source: 'manual',
  );
  await FrozenHeadlineStore.put(day, 72, explanation: {'original': 'authored'});
}

Future<void> accept(String action) => SleepOverrideStore.acceptCorrection(
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
        final pin = await CursorStore.read(FrozenHeadlineStore.kCursorKey);
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
        expect(await MetricSeriesStore.series('rmssd'), isEmpty);
        expect((await MetricSeriesStore.series('strain')).single['value'], 8);
        expect(await FrozenHeadlineStore.read(), isNull);
        expect(await LocalDb.dayResultIds(kAlgoVersion), isNot(contains(day)));
        final intent = (await SleepOverrideStore.correction(day))!;
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
        expect(
          (await SleepOverrideStore.getOverride(day))?['source'],
          'manual',
        );
        expect((await FrozenHeadlineStore.read())?.value, 72);
        expect((await MetricSeriesStore.series('rmssd')).single['value'], 44);
        expect(await SleepOverrideStore.correction(day), isNull);
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
      expect((await SleepOverrideStore.correction(day))?['generation'], 2);
      expect(
        (await SleepOverrideStore.correction(day))?['recovery'],
        hasLength(2),
      );
      expect((await LocalDb.dayResult(day))?['rmssd'], isNull);
      expect(await publish(2, revision: 2), true);
      expect((await LocalDb.dayResult(day))?['rmssd'], 44);
      expect((await MetricSeriesStore.series('rmssd')).single['value'], 44);
      expect((await SleepOverrideStore.correction(day))?['usable'], true);
    },
  );

  test(
    'missing automatic replacement remains unknown and cannot prune raw',
    () async {
      await seed();
      await accept('clear');
      expect(await publish(1, usable: false), true);
      expect((await LocalDb.dayResult(day))?['rmssd'], isNull);
      expect((await SleepOverrideStore.correction(day))?['pending'], false);
      expect((await SleepOverrideStore.correction(day))?['usable'], false);
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
      await SleepIntermediateStore.putCandidate(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: '{}',
      );
      expect(await SleepIntermediateStore.candidate(day, kAlgoVersion), isNull);
      await FrozenHeadlineStore.put(day, 99);
      await FrozenHeadlineStore.put(day, 99, sleepIntentGeneration: 1);
      expect(await FrozenHeadlineStore.read(), isNull);
      expect(await MetricSeriesStore.putBaseline('crossday', '{}'), false);
      expect(await MetricSeriesStore.baseline('crossday'), isNull);
      expect(
        await MetricSeriesStore.putBaseline(
          'crossday',
          '{"current":true}',
          sleepRevision: 1,
        ),
        true,
      );
      await accept('rejected');
      expect(
        await MetricSeriesStore.putBaseline(
          'crossday',
          '{"old":true}',
          sleepRevision: 1,
        ),
        false,
      );
      expect(await MetricSeriesStore.baseline('crossday'), isNull);
    },
  );

  test(
    'full database export restores original recovery and current unknown output',
    () async {
      await seed();
      await accept('clear');
      final ledger = await SleepOverrideStore.correction(day);
      final exported = await LocalDb.exportCopy();
      await LocalDb.wipeAll();
      await LocalDb.importFromDbFile(exported);
      expect(await SleepOverrideStore.correction(day), ledger);
      expect(
        (await LocalRepositoryImpl(
          getProfileMap: () => null,
        ).getDaySleep(day))['has_sleep'],
        false,
      );
      expect((await LocalDb.dayResult(day))?['partial'], 1);
      expect(await MetricSeriesStore.series('rmssd'), isEmpty);
    },
  );

  test(
    'overlapping old backup refuses before changing a corrected day',
    () async {
      await seed();
      final oldBackup = await LocalDb.exportCopy();
      await accept('rejected');
      final before = await SleepOverrideStore.correction(day);
      await expectLater(
        LocalDb.importFromDbFile(oldBackup),
        throwsA(isA<DbImportException>()),
      );
      expect(await SleepOverrideStore.correction(day), before);
      expect(
        (await LocalRepositoryImpl(
          getProfileMap: () => null,
        ).getDaySleep(day))['has_sleep'],
        false,
      );
      expect(await MetricSeriesStore.series('rmssd'), isEmpty);
    },
  );
  test('obsolete staging cannot fold into the current sleep profile', () async {
    await seed();
    await MetricSeriesStore.putBaseline(
      'sleep_user_profile',
      '{"folded_days":[]}',
    );
    expect(
      await SleepIntermediateStore.putCandidate(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: '{"before":true}',
      ),
      true,
    );
    await accept('clear');
    var called = false;
    await MetricSeriesStore.updateBaseline('sleep_user_profile', (_) {
      called = true;
      return '{"obsolete":true}';
    }, sleepDayId: day);
    expect(called, false);
    expect(
      jsonDecode(
        (await MetricSeriesStore.baseline(
              'sleep_user_profile',
            ))!['payload_json']
            as String,
      ),
      {'folded_days': []},
    );
    // The correction can arrive after the candidate commit but before the fold.
    expect(
      await SleepIntermediateStore.putCandidate(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: '{"current":true}',
        sleepIntentGeneration: 1,
      ),
      true,
    );
    await accept('rejected');
    await MetricSeriesStore.updateBaseline(
      'sleep_user_profile',
      (_) {
        called = true;
        return '{"obsolete":true}';
      },
      sleepDayId: day,
      sleepIntentGeneration: 1,
    );
    expect(called, false);
    expect(
      await SleepIntermediateStore.putCandidate(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: '{"obsolete":true}',
        sleepIntentGeneration: 1,
      ),
      false,
    );
    expect(
      (await SleepIntermediateStore.candidate(
        day,
        kAlgoVersion,
      ))!['payload_json'],
      '{"current":true}',
    );
  });

  test(
    'matching profile fold retains atomic accumulation for an unaffected day',
    () async {
      await seed();
      await accept('clear');
      await MetricSeriesStore.updateBaseline(
        'sleep_user_profile',
        (_) => '{"accepted":true}',
        sleepDayId: day,
        sleepIntentGeneration: 1,
      );
      expect(
        jsonDecode(
          (await MetricSeriesStore.baseline(
                'sleep_user_profile',
              ))!['payload_json']
              as String,
        ),
        {'accepted': true},
      );
      await MetricSeriesStore.updateBaseline(
        'sleep_user_profile',
        (_) => '{"other_day":true}',
        sleepDayId: '2021-04-05',
      );
      expect(
        jsonDecode(
          (await MetricSeriesStore.baseline(
                'sleep_user_profile',
              ))!['payload_json']
              as String,
        ),
        {'other_day': true},
      );
    },
  );

  test(
    'malformed display pin is preserved and does not refuse a correction',
    () async {
      await seed();
      await CursorStore.write(
        FrozenHeadlineStore.kCursorKey,
        '{retained-unreadable',
      );
      await accept('clear');
      final recovery =
          ((await SleepOverrideStore.correction(day))!['recovery'] as List)
                  .single
              as Map;
      expect((recovery['pin'] as List).single['value'], '{retained-unreadable');
      expect((await LocalDb.dayResult(day))!['rmssd'], isNull);
      expect(await FrozenHeadlineStore.read(), isNull);
    },
  );

  const profile = Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170);
  for (final forced in [false, true]) {
    test(
      'a real empty-input read completes unknown without losing daytime forced=$forced',
      () async {
        await seed();
        await accept('clear');
        final recovery = (await SleepOverrideStore.correction(
          day,
        ))!['recovery'];
        final engine = DerivationEngine();
        if (forced) {
          expect(await engine.run(profile, force: true), 0);
        } else {
          expect(await engine.run(profile), 0);
        }
        expect((await SleepOverrideStore.correction(day))!['pending'], false);
        expect((await SleepOverrideStore.correction(day))!['usable'], false);
        expect(
          (await SleepOverrideStore.correction(day))!['recovery'],
          recovery,
        );
        final current = (await LocalDb.dayResult(day))!;
        expect(current['partial'], 1);
        expect(current['finalized'], 0);
        expect(current['rmssd'], isNull);
        final bundle = SeriesCodec.decodePayloadJson(current['payload_json'])!;
        expect((bundle['scalars'] as Map)['strain'], 8);
        expect((await MetricSeriesStore.series('strain')).single['value'], 8);
        expect(await LocalDb.dayResultIds(kAlgoVersion), isNot(contains(day)));
        await LocalDb.close();
        expect((await SleepOverrideStore.correction(day))!['pending'], false);
        expect(
          (await SleepOverrideStore.correction(day))!['recovery'],
          recovery,
        );
      },
    );
  }

  test(
    'read refusal keeps the accepted correction pending for a real retry',
    () async {
      await seed();
      await accept('clear');
      final db = await LocalDb.instance;
      final before = await SleepOverrideStore.correction(day);
      await db.execute(
        'ALTER TABLE decoded_onehz RENAME TO retained_authored_input',
      );
      try {
        expect(await DerivationEngine().run(profile, force: true), 0);
        expect(await SleepOverrideStore.correction(day), before);
        expect((await LocalDb.dayResult(day))!['rmssd'], isNull);
      } finally {
        await db.execute(
          'ALTER TABLE retained_authored_input RENAME TO decoded_onehz',
        );
      }
      await DerivationEngine().run(profile, force: true);
      expect((await SleepOverrideStore.correction(day))!['pending'], false);
    },
  );

  test(
    'refused empty completion rolls back intent status and retries safely',
    () async {
      await seed();
      await accept('clear');
      final db = await LocalDb.instance;
      final before = await SleepOverrideStore.correction(day);
      await db.execute(
        "CREATE TRIGGER refuse_empty_completion BEFORE INSERT ON day_result BEGIN SELECT RAISE(ABORT, 'authored completion refusal'); END",
      );
      try {
        await DerivationEngine().run(profile, force: true);
        expect(await SleepOverrideStore.correction(day), before);
        expect((await LocalDb.dayResult(day))!['partial'], 1);
      } finally {
        await db.execute('DROP TRIGGER refuse_empty_completion');
      }
      await DerivationEngine().run(profile, force: true);
      expect((await SleepOverrideStore.correction(day))!['pending'], false);
      expect(
        (await SleepOverrideStore.correction(day))!['recovery'],
        before!['recovery'],
      );
    },
  );
  for (final incomingCorrection in [false, true]) {
    test(
      'metric-only overlap is refused before any import writes incoming=$incomingCorrection',
      () async {
        final db = await LocalDb.instance;
        if (incomingCorrection) {
          await seed();
          await accept('clear');
        } else {
          await db.insert('metric_series', {
            'date': day,
            'key': 'rmssd',
            'value': 999,
          });
        }
        final exported = await LocalDb.exportCopy();
        await LocalDb.wipeAll();
        if (incomingCorrection) {
          await db.insert('metric_series', {
            'date': day,
            'key': 'rmssd',
            'value': 47,
          });
        } else {
          await seed();
          await accept('rejected');
        }
        final beforeSeries = await db.query('metric_series');
        final beforeLedger = await SleepOverrideStore.correction(day);
        final beforeRevision = await SleepOverrideStore.correctionRevision();
        await expectLater(
          LocalDb.importFromDbFile(exported),
          throwsA(
            isA<DbImportException>().having(
              (e) => e.records,
              'committed records',
              0,
            ),
          ),
        );
        expect(await db.query('metric_series'), beforeSeries);
        expect(await SleepOverrideStore.correction(day), beforeLedger);
        expect(await SleepOverrideStore.correctionRevision(), beforeRevision);
      },
    );
  }

  test(
    'overlapping recovery ledgers cannot overwrite each other without day rows',
    () async {
      final db = await LocalDb.instance;
      await accept('clear');
      await db.delete('day_result');
      final exported = await LocalDb.exportCopy();
      await LocalDb.wipeAll();
      await accept('manual');
      await accept('rejected');
      await db.delete('day_result');
      final before = await SleepOverrideStore.correction(day);
      await expectLater(
        LocalDb.importFromDbFile(exported),
        throwsA(
          isA<DbImportException>().having(
            (e) => e.records,
            'committed records',
            0,
          ),
        ),
      );
      expect(await SleepOverrideStore.correction(day), before);
    },
  );

  for (final action in ['manual', 'confirmed', 'rejected']) {
    test(
      'empty $action intent preserves provenance and completes without a measured night',
      () async {
        await seed();
        await accept(action);
        await DerivationEngine().run(profile, force: true);
        final intent = (await SleepOverrideStore.correction(day))!;
        expect(intent['pending'], false);
        expect(intent['usable'], false);
        expect((intent['recovery'] as List).single['day_results'], isNotEmpty);
        final sleep = await LocalRepositoryImpl(
          getProfileMap: () => null,
        ).getDaySleep(day);
        expect(sleep['has_sleep'], false);
        expect(sleep['sleep_source'], action);
        expect(
          await SleepOverrideStore.correctionDays(pendingOnly: true),
          isEmpty,
        );
        expect(await SleepOverrideStore.correctionDays(), {day});
      },
    );
  }
  for (final sourceRevision in [1, 9]) {
    test(
      'disjoint import cannot recycle a publication revision source=$sourceRevision',
      () async {
        const other = '2021-04-07';
        await SleepOverrideStore.acceptCorrection(
          dayId: other,
          action: 'clear',
        );
        await CursorStore.write('sleep_correction_revision', '$sourceRevision');
        final incomingLedger = await SleepOverrideStore.correction(other);
        final exported = await LocalDb.exportCopy();
        await LocalDb.wipeAll();
        await seed();
        for (var i = 0; i < 5; i++) {
          await accept('clear');
        }
        final currentLedger = await SleepOverrideStore.correction(day);
        expect(await SleepOverrideStore.correctionRevision(), 5);
        await LocalDb.importFromDbFile(exported);
        expect(await SleepOverrideStore.correctionRevision(), greaterThan(5));
        expect(
          await SleepOverrideStore.correctionRevision(),
          greaterThan(sourceRevision),
        );
        expect(await SleepOverrideStore.correction(day), currentLedger);
        expect(await SleepOverrideStore.correction(other), incomingLedger);
        expect(
          await MetricSeriesStore.putBaseline(
            'crossday',
            '{"obsolete":true}',
            sleepRevision: 5,
          ),
          false,
        );
        expect(
          await MetricSeriesStore.putBaseline(
            'crossday',
            '{"obsolete_source":true}',
            sleepRevision: sourceRevision,
          ),
          false,
        );
        expect(
          await MetricSeriesStore.putBaseline(
            'crossday',
            '{"fresh":true}',
            sleepRevision: await SleepOverrideStore.correctionRevision(),
          ),
          true,
        );
      },
    );
  }
}
