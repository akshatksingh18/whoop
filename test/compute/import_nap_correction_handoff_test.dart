// Real import coordinator -> saved nap edits -> shared day pipeline -> reader.
// Complete derivation controls run in cloud CI; all measurements are authored.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('import-nap-correction-handoff', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final mode in ['manual', 'rejected', 'both']) {
    test(
      'import coordinator keeps $mode nap correction without inventing an overnight result',
      () async {
        const day = '2021-04-06';
        final start = localDayStartSec(day)! + 12 * 3600;
        final manualStart = start + 3600, rejectedStart = start + 7200;
        if (mode != 'rejected') {
          await SleepNapStore.putEdit(
            dayId: day,
            startTs: manualStart,
            endTs: manualStart + 1800,
            source: 'manual',
          );
        }
        if (mode != 'manual') {
          await SleepNapStore.putEdit(
            dayId: day,
            startTs: rejectedStart,
            endTs: rejectedStart + 1800,
            source: 'rejected',
          );
        }
        await LocalDb.setCursor('authored-unrelated-retention', 'keep');
        final edits = await SleepNapStore.edits(day);
        const n = 720;
        final sub = Substrate(
          tsSec: [for (var i = 0; i < n; i++) start + i],
          hr: List.filled(n, 80),
          rrTsMs: [],
          rrMs: [],
          ax: [for (var i = 0; i < n; i++) i.isEven ? .4 : -.4],
          ay: List.filled(n, 0.0),
          az: List.filled(n, 1.0),
          spo2Red: List.filled(n, null),
          spo2Ir: List.filled(n, null),
          skinTemp: List.filled(n, null),
          skinContact: List.filled(n, null),
          deviceFamily: 'gen4',
        );
        final engine = DerivationEngine(background: true);
        final completed = <String>[];
        expect(
          await engine.deriveImportedDays(
            sub,
            const Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70),
            {day},
            onDayDone: completed.add,
          ),
          1,
        );
        expect(completed, [day]);
        expect(engine.running, false);
        final row = (await LocalDb.dayResult(day))!;
        final bundle = jsonDecode(row['payload_json'] as String) as Map;
        final db = await LocalDb.instance;
        final series = await db.query('metric_series');
        final repo = LocalRepositoryImpl(getProfileMap: () => null);
        final answer = await repo.getDayNaps(day);
        final naps = (answer['naps'] as List?) ?? const [];
        if (mode == 'rejected') {
          expect(naps, isEmpty);
          expect(answer['nap_min'], isNull);
          expect((bundle['scalars'] as Map)['nap_min'], isNull);
        } else {
          expect(naps, hasLength(1));
          expect(naps.single['start'], manualStart);
          expect(naps.single['end'], manualStart + 1800);
          expect(naps.single['source'], 'manual');
          expect(naps.single['duration_min'], 30);
          expect(answer['nap_min'], 30);
          expect((bundle['scalars'] as Map)['nap_min'], 30);
        }
        final rejected = answer['rejected'] as List;
        expect(rejected.length, mode == 'manual' ? 0 : 1);
        if (rejected.isNotEmpty) {
          expect(rejected.single['start_ts'], rejectedStart);
        }
        expect(row['readiness'], isNull);
        expect(row['rmssd'], isNull);
        expect(await SleepNapStore.edits(day), edits);
        expect(await LocalDb.dayResult(day), row);
        expect(await db.query('metric_series'), series);
        expect(await LocalDb.getCursor('authored-unrelated-retention'), 'keep');
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'raw_records'",
          ),
          isEmpty,
          reason: 'Import must not recreate the retired raw table',
        );
        expect(await db.query('raw_archive'), isEmpty);
        expect(await db.query('decoded_rr'), isEmpty);
        expect(await db.query('decoded_onehz'), isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }
}
