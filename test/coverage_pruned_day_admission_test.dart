// Real retention between scope selection and sequential day preparation.
// Tiny authored rows only; no selected-day API or empty import is manufactured.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/models.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('pruned-day-admission'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const older = '2021-04-06', newer = '2021-04-07';

  for (final entry in ['ordinary', 'rescan']) {
    for (final saved in ['provisional', 'finalized', 'prior algorithm']) {
      test(
        '$entry preserves $saved history under its actual refresh admission',
        () async {
          final db = await LocalDb.instance;
          final selected = entry != 'ordinary' || saved != 'finalized';
          for (final (index, day) in [(1, older), (2, newer)]) {
            final ts = localDayStartSec(day)! + 12 * 3600;
            await LocalDb.putDayResult(
              dayId: day,
              algoVersion: day == older && saved == 'prior algorithm'
                  ? kAlgoVersion - 1
                  : kAlgoVersion,
              payloadJson: jsonEncode({
                'date': day,
                'scalars': {'rhr': 55.0 + index, 'readiness': 70.0},
                'wear': {'fraction': .75},
                'series': {
                  'authored_detail': [1, 2, 3],
                },
              }),
              windowJson: '{}',
              finalized: day == older && saved != 'provisional',
              rhr: 55.0 + index,
              readiness: 70,
              series: {'rhr': 55.0 + index, 'readiness': 70},
            );
            await LocalDb.insertRecord(
              RawRecord(
                counter: index,
                packetType: 47,
                hex: 'authored-$entry-$saved-$day',
                recTs: ts,
                capturedAt: ts * 1000,
              ),
              Sample(tsEpoch: ts, counter: index, hr: 60, ax: 0, ay: 0, az: 1),
            );
          }
          final before = await LocalDb.dayResult(older);
          final series = await db.query(
            'metric_series',
            where: 'date=?',
            whereArgs: [older],
            orderBy: 'key',
          );
          final versions = await db.query(
            'metric_series_version',
            where: 'date=?',
            whereArgs: [older],
          );
          final allRaw = await db.query('decoded_onehz');
          final newestRaw = await db.query(
            'decoded_onehz',
            where: 'rec_ts >= ?',
            whereArgs: [localDayStartSec(newer)!],
          );
          final completed = <String>[], logs = <String>[];
          Future<int>? retention;
          final engine = DerivationEngine(background: true, log: logs.add);
          void onDay(String day, int index, int total) {
            completed.add(day);
            expect(index, completed.length);
            expect(total, selected ? 2 : 1);
            if (day == newer && selected) {
              // SQLite queues this actual independent retention write before
              // the next sequential lane's preparation queries.
              retention = db.delete(
                'decoded_onehz',
                where: 'rec_ts < ?',
                whereArgs: [localDayStartSec(newer)!],
              );
            }
          }

          final count = entry == 'ordinary'
              ? await engine.run(
                  const Profile(),
                  heavy: true,
                  force: true,
                  onDayDone: onDay,
                )
              : await engine.rescanRecent(const Profile(), onDayDone: onDay);
          if (selected) {
            expect(retention, isNotNull);
            expect(await retention!, 1);
          } else {
            expect(retention, isNull);
          }
          expect(count, selected ? 2 : 1, reason: logs.join('\n'));
          expect(completed, selected ? [newer, older] : [newer]);
          expect(
            logs.any(
              (s) => s.contains(
                'derive $older: no substrate (raw pruned) — kept the existing result',
              ),
            ),
            selected,
            reason:
                'The admitted older day must reach the shared guard; finalized ordinary days stay outside scope.\n${logs.join('\n')}',
          );
          expect(await LocalDb.dayResult(older), before);
          expect(
            await db.query(
              'metric_series',
              where: 'date=?',
              whereArgs: [older],
              orderBy: 'key',
            ),
            series,
          );
          expect(
            await db.query(
              'metric_series_version',
              where: 'date=?',
              whereArgs: [older],
            ),
            versions,
          );
          expect(
            await db.query('decoded_onehz'),
            selected ? newestRaw : allRaw,
          );
          expect(await db.query('sleep_override'), isEmpty);
          expect(await db.query('sleep_nap'), isEmpty);
          expect(engine.running, false);
          // A later actual command cannot turn the disappeared source into
          // measured zero or rewrite the retained prior-algorithm bundle.
          expect(
            await engine.run(const Profile(), heavy: true, force: true),
            1,
          );
          expect(await LocalDb.dayResult(older), before);
          expect(
            await db.query(
              'metric_series',
              where: 'date=?',
              whereArgs: [older],
              orderBy: 'key',
            ),
            series,
          );
          expect(
            await db.query('decoded_onehz'),
            selected ? newestRaw : allRaw,
          );
          expect(engine.running, false);
        },
        timeout: const Timeout(Duration(seconds: 35)),
      );
    }
  }
}
