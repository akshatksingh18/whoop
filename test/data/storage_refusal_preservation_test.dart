// Real SQLite failure/transaction boundaries for active correction and editors.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import '../support/store_fixtures.dart';
import '../support/coverage_store.dart';

const day = '2021-04-06';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('storage-refusal-preservation'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<Map<String, Object>> snapshot() async {
    final db = await LocalDb.instance;
    return {
      for (final table in [
        'day_result',
        'baselines',
        'sleep_override',
        'metric_series',
        'metric_series_version',
        'sleep_session_candidates',
        'sync_cursor',
        'journal',
        'journal_metric',
        'journal_field_def',
      ])
        table: await db.query(table),
    };
  }

  for (final c in [
    ('unrecognized', 1, 10),
    ('manual', 10, 10),
    ('confirmed', 10, 9),
    ('rejected', null, 10),
  ]) {
    test(
      'invalid ${c.$1} bounds ${c.$2}/${c.$3} preserve every correction and journal row',
      () async {
        await CursorStore.write('authored_recovery', 'kept');
        await JournalStore.put(day, '["travel"]', 'Keep authored note');
        final before = await snapshot();
        await expectLater(
          SleepOverrideStore.acceptCorrection(
            dayId: day,
            action: c.$1,
            onsetTs: c.$2,
            offsetTs: c.$3,
          ),
          throwsArgumentError,
        );
        expect(await snapshot(), before);
      },
    );
  }

  test(
    'a malformed served night aborts preservation atomically including archive and pin',
    () async {
      final db = await LocalDb.instance;
      await DayResultStore.put(
        dayId: day,
        algoVersion: 100,
        payloadJson: '{}',
        windowJson: '{}',
      );
      await db.update(
        'day_result',
        {'payload_json': 'not-json'},
        where: 'day_id=?',
        whereArgs: [day],
      );
      await FrozenHeadlineStore.put(day, 72, explanation: {'authored': true});
      final before = await snapshot();
      await expectLater(
        SleepOverrideStore.acceptCorrection(
          dayId: day,
          action: 'manual',
          onsetTs: 1,
          offsetTs: 10,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('Cannot safely preserve malformed sleep result'),
          ),
        ),
      );
      expect(
        await snapshot(),
        before,
        reason: 'Intent, archives, revision and old result roll back together',
      );
    },
  );

  test(
    'same-size concurrent tag replacement refuses the entire numeric edit and can retry',
    () async {
      await JournalStore.put(day, '["travel"]', 'Authored note');
      await seedJournalMetrics(day, {
        'caffeine_mg': const JournalMetricValue(0, atMinuteOfDay: 600),
      });
      final repo = LocalRepositoryImpl(getProfileMap: () => {});
      final before = await snapshot();
      final conflict = await repo.saveJournalEdit(
        day,
        changes: {
          'caffeine_mg': const JournalMetricValue(100, atMinuteOfDay: 660),
        },
        base: {'caffeine_mg': const JournalMetricValue(0, atMinuteOfDay: 600)},
        tags: ['workout'],
        baseTags: ['rest day'],
      );
      expect(conflict, ['tags']);
      expect(await snapshot(), before);
      expect(
        await repo.saveJournalEdit(
          day,
          changes: {
            'caffeine_mg': const JournalMetricValue(100, atMinuteOfDay: 660),
          },
          base: {
            'caffeine_mg': const JournalMetricValue(0, atMinuteOfDay: 600),
          },
          tags: ['workout'],
          baseTags: ['travel'],
        ),
        isEmpty,
      );
      expect(
        (await JournalStore.metricsForDay(day))['caffeine_mg']!.atMinuteOfDay,
        660,
      );
      expect(
        (await JournalStore.entries(date: day)).single['note'],
        'Authored note',
      );
    },
  );

  test(
    'a duplicate custom definition cannot replace units or existing numeric history',
    () async {
      const original = JournalFieldSpec(
        key: 'custom_authored',
        label: 'Authored field',
        kind: JournalFieldKind.dose,
        unit: 'mg',
        max: 1000,
        step: 50,
        hasTime: true,
        custom: true,
      );
      await JournalStore.putFieldDef(original);
      await seedJournalMetrics(day, {
        'custom_authored': const JournalMetricValue(0, atMinuteOfDay: 600),
      });
      final before = await snapshot();
      await expectLater(
        JournalStore.putFieldDef(
          const JournalFieldSpec(
            key: 'custom_authored',
            label: 'Different meaning',
            kind: JournalFieldKind.duration,
            unit: 'min',
            max: 60,
            step: 1,
            custom: true,
          ),
        ),
        throwsStateError,
      );
      expect(await snapshot(), before);
      expect((await JournalStore.fieldDefs()).single.unit, 'mg');
    },
  );
}
