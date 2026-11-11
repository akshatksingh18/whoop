// Real NOOP rolling input and SQLite step ledger. Only heavy derivation is
// captured at its existing boundary; no retired band-step UI is activated.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/noop_ingest.dart';
import 'coverage_noop_container_contract_test.dart' show CaptureEngine;
import 'support/coverage_store.dart';

class BankObservationEngine extends CaptureEngine {
  final bankedAtDerive = <List<Map<String, Object?>>>[];
  @override
  Future<int> deriveImportedDays(
    Substrate sub,
    Profile profile,
    Set<String> days, {
    void Function(String day)? onDayDone,
  }) async {
    bankedAtDerive.add(await (await LocalDb.instance).query('live_coverage'));
    return super.deriveImportedDays(sub, profile, days, onDayDone: onDayDone);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('ingest-ordering-tail'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const profile = Profile();

  test(
    'NOOP step-only final day retains measured counts without inventing an HR day',
    () async {
      final engine = CaptureEngine();
      final ingest = NoopIngest(profile, engine);
      final start = localDayStartSec('2021-04-06')! + 3600;
      for (var i = 0; i < 3; i++) {
        expect(await ingest.offer(start + i), true);
        ingest.stepCounter(start + i, 100 + i * 6);
      }
      await ingest.finish();
      expect(ingest.rows, 3);
      expect(ingest.steps, 12);
      expect(ingest.days, 0);
      expect(engine.inputs, isEmpty);
      expect(engine.finalizations, 1);
      final rows = await (await LocalDb.instance).query('live_coverage');
      expect(rows, hasLength(1));
      expect(rows.single['start_ts'], start);
      // Twelve measured steps need at least three seconds at the existing
      // 240 steps/minute ceiling; the writer preserves that lower bound.
      expect(rows.single['end_ts'], start + 3);
      expect(rows.single['steps'], 12);
      expect(rows.single['source'], isNot('phone'));
      expect(
        await LocalDb.liveStepsForDay('2021-04-06'),
        0,
        reason: 'Retain the personal phone-only display policy',
      );
      final retry = NoopIngest(profile, CaptureEngine());
      for (var i = 0; i < 3; i++) {
        expect(await retry.offer(start + i), true);
        retry.stepCounter(start + i, 100 + i * 6);
      }
      await retry.finish();
      expect(retry.steps, 0);
      expect(await (await LocalDb.instance).query('live_coverage'), rows);
    },
  );

  test(
    'NOOP prior-day steps bank before its derive handoff and never count twice at finish',
    () async {
      final engine = BankObservationEngine();
      final progress = <int>[];
      final ingest = NoopIngest(profile, engine, onProgress: progress.add);
      final first = localDayStartSec('2021-04-06')! + 3600;
      final next = localDayStartSec('2021-04-07')! + 3600;
      for (var i = 0; i < 2; i++) {
        expect(await ingest.offer(first + i), true);
        ingest.hr(first + i, 70 + i);
        ingest.stepCounter(first + i, 200 + i * 7);
      }
      expect(await ingest.offer(next), true);
      expect(engine.bankedAtDerive, hasLength(1));
      expect(engine.bankedAtDerive.single.single['steps'], 7);
      ingest.hr(next, 80);
      await ingest.finish();
      expect(engine.dates, [
        {'2021-04-06'},
        {'2021-04-07'},
      ]);
      expect(engine.inputs.first.hr, [70, 71]);
      expect(engine.inputs.last.hr, [70, 71, 80]);
      expect(ingest.steps, 7);
      expect(ingest.days, 2);
      expect(progress, [1, 2]);
      expect(
        await (await LocalDb.instance).query('live_coverage'),
        hasLength(1),
      );
      expect(await (await LocalDb.instance).query('decoded_onehz'), isEmpty);
    },
  );

  test(
    'NOOP late rows cannot rewind or contaminate a day already handed to derivation',
    () async {
      final engine = CaptureEngine();
      final ingest = NoopIngest(profile, engine);
      final first = localDayStartSec('2021-04-06')! + 3600;
      final next = localDayStartSec('2021-04-07')! + 3600;
      expect(await ingest.offer(first), true);
      ingest.hr(first, 70);
      expect(await ingest.offer(next), true);
      ingest.hr(next, 80);
      for (final ts in [first, first + 1]) {
        expect(await ingest.offer(ts), false);
      }
      expect(ingest.rows, 2);
      expect(ingest.lateRows, 2);
      expect(ingest.strandedDates, isEmpty);
      await ingest.finish();
      expect(engine.dates, [
        {'2021-04-06'},
        {'2021-04-07'},
      ]);
      expect(engine.inputs.first.hr, [70]);
      expect(engine.inputs.last.hr, [70, 80]);
      expect(engine.finalizations, 1);
      expect(await (await LocalDb.instance).query('day_result'), isEmpty);
    },
  );

  test(
    'NOOP stranded step-only date keeps its ledger and explicit missing-day report',
    () async {
      final engine = CaptureEngine();
      final ingest = NoopIngest(profile, engine);
      final newer = localDayStartSec('2021-04-07')! + 3600;
      final older = localDayStartSec('2021-04-06')! + 3600;
      expect(await ingest.offer(newer), true);
      ingest.hr(newer, 80);
      for (var i = 0; i < 2; i++) {
        expect(await ingest.offer(older + i), true);
        ingest.stepCounter(older + i, 10 + i * 5);
      }
      await ingest.finish();
      expect(ingest.strandedDates, {'2021-04-06'});
      expect(ingest.lateRows, 0);
      expect(ingest.steps, 5);
      expect(engine.dates, [
        {'2021-04-07'},
      ]);
      expect(engine.inputs.single.hr, [80]);
      expect(
        (await (await LocalDb.instance).query('live_coverage')).single['steps'],
        5,
      );
    },
  );

  test(
    'StepRun value equality and diagnostics retain every source coordinate',
    () {
      const value = StepRun(100, 110, 12);
      const same = StepRun(100, 110, 12);
      expect(value, same);
      expect(value.hashCode, same.hashCode);
    expect(<StepRun>{}..addAll([value, same]), hasLength(1));
      for (final other in <Object>[
        const StepRun(101, 110, 12),
        const StepRun(100, 111, 12),
        const StepRun(100, 110, 13),
        'StepRun(100..110, 12)',
        12,
      ]) {
        expect(value == other, false);
      }
      expect(value.toString(), 'StepRun(100..110, 12)');
    },
  );
}
