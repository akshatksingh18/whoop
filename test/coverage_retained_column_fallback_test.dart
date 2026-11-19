// Real selection -> independent SQLite retention -> shared preservation guard.
// Old bundle shapes must not erase indexed measurements or their saved detail.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('retained-column-fallback'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const older = '2021-04-06', newer = '2021-04-07';
  for (final entry in ['ordinary', 'rescan']) {
    for (final shape in ['missing', 'null']) {
      for (final anchor in ['rhr', 'rmssd', 'readiness']) {
        test(
          '$entry retains indexed $anchor with $shape legacy scalar detail',
          () async {
            final db = await LocalDb.instance;
            for (final (index, date) in [(1, older), (2, newer)]) {
              final ts = localDayStartSec(date)! + 12 * 3600;
              await LocalDb.putDayResult(
                dayId: date,
                algoVersion: kAlgoVersion,
                payloadJson: jsonEncode({
                  'date': date,
                  if (date == newer)
                    'scalars': {'rhr': 57, 'readiness': 72}
                  else if (shape != 'missing')
                    'scalars': null,
                  'legacy_detail': {
                    'note': 'retain banked measurement evidence',
                    'trace': [1, null, 3],
                  },
                }),
                windowJson: '{}',
                finalized: false,
                rhr: date == newer || anchor == 'rhr' ? 57 : null,
                rmssd: date == newer || anchor == 'rmssd' ? 41 : null,
                readiness: date == newer || anchor == 'readiness' ? 72 : null,
                series: date == newer
                    ? {'rhr': 57, 'rmssd': 41, 'readiness': 72}
                    : {
                        anchor: anchor == 'rhr'
                            ? 57.0
                            : anchor == 'rmssd'
                            ? 41.0
                            : 72.0,
                      },
              );
              await LocalDb.insertRecord(
                RawRecord(
                  counter: index,
                  packetType: 47,
                  hex: 'authored-column-fallback-$index',
                  recTs: ts,
                  capturedAt: ts * 1000,
                ),
                Sample(
                  tsEpoch: ts,
                  counter: index,
                  hr: 60,
                  ax: 0,
                  ay: 0,
                  az: 1,
                ),
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
            final latest = await db.query(
              'decoded_onehz',
              where: 'rec_ts>=?',
              whereArgs: [localDayStartSec(newer)!],
            );
            Future<int>? pruned;
            final completed = <String>[], logs = <String>[];
            void done(String date, int index, int total) {
              completed.add(date);
              expect(total, 2);
              expect(index, completed.length);
              if (date == newer) {
                // The real callback queues this write before sequential preparation
                // of the selected older day. No synthetic empty import is injected.
                pruned = db.delete(
                  'decoded_onehz',
                  where: 'rec_ts<?',
                  whereArgs: [localDayStartSec(newer)!],
                );
              }
            }

            final engine = DerivationEngine(background: true, log: logs.add);
            final count = entry == 'ordinary'
                ? await engine.run(
                    const Profile(),
                    heavy: true,
                    force: true,
                    onDayDone: done,
                  )
                : await engine.rescanRecent(const Profile(), onDayDone: done);
            expect(count, 2, reason: logs.join('\n'));
            expect(completed, [newer, older]);
            expect(pruned, isNotNull);
            expect(await pruned!, 1);
            expect(
              logs,
              contains(
                contains(
                  'derive $older: no substrate (raw pruned) — kept the existing result',
                ),
              ),
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
            expect(await db.query('decoded_onehz'), latest);
            expect(engine.running, false);
            expect(
              await engine.run(const Profile(), heavy: true, force: true),
              1,
            );
            expect(await LocalDb.dayResult(older), before);
            expect(await db.query('decoded_onehz'), latest);
            expect(engine.running, false);
          },
        );
      }
    }
  }
}
