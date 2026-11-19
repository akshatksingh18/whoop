// Public command with tiny real SQLite input; no full-night local computation.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const days = ['2021-04-05', '2021-04-06'];
  late AppState app;
  setUpAll(() => coverageStore('reanalysis-command-recovery'));
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting();
    for (var i = 0; i < days.length; i++) {
      final day = days[i], start = localDayStartSec(days[i])!;
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'date': day,
          'device_family': 'gen4',
          'scalars': {'rhr': 55.0 + i},
          'wear': {'fraction': .75},
        }),
        windowJson: jsonEncode({
          'value': {
            'onset_ms': (start + 3600) * 1000,
            'offset_ms': (start + 3 * 3600) * 1000,
          },
        }),
        rhr: 55.0 + i,
        finalized: false,
        series: {'rhr': 55.0 + i},
      );
      await LocalDb.insertRecord(
        RawRecord(
          counter: i + 1,
          packetType: 47,
          hex: 'authored-command-$day',
          recTs: start + 43200,
          capturedAt: (start + 43200) * 1000,
        ),
        Sample(
          tsEpoch: start + 43200,
          counter: i + 1,
          hr: 60,
          ax: 0,
          ay: 0,
          az: 1,
        ),
      );
    }
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);

  test(
    'COV-48 real reanalysis publishes day progress and coalesces a concurrent command',
    () async {
      final db = await LocalDb.instance;
      final saved = [for (final day in days) await LocalDb.dayResult(day)];
      final raw = await db.query('decoded_onehz', orderBy: 'rec_ts');
      final series = await db.query('metric_series', orderBy: 'date,key');
      final events = <({bool busy, String progress})>[];
      Future<int>? concurrent;
      var tried = false;
      app.addListener(() {
        events.add((busy: app.reanalyzing, progress: app.reanalyzeProgress));
        if (app.reanalyzing && !tried) {
          tried = true;
          concurrent = app.reanalyzeAll();
        }
      });
      final revision = app.insightsRevision.value;
      expect(await app.reanalyzeAll(), 2, reason: app.logLines.join('\n'));
      expect(tried, true);
      expect(await concurrent!, 0);
      expect(events.first, (busy: true, progress: 'Analyzing…'));
      expect(events, contains((busy: true, progress: 'Analyzing 1/2')));
      expect(events, contains((busy: true, progress: 'Analyzing 2/2')));
      expect(events.last, (busy: false, progress: ''));
      expect(app.reanalyzing, false);
      expect(app.reanalyzeProgress, '');
      expect(app.insightsRevision.value, revision + 1);
      expect([for (final day in days) await LocalDb.dayResult(day)], saved);
      expect(await db.query('decoded_onehz', orderBy: 'rec_ts'), raw);
      expect(await db.query('metric_series', orderBy: 'date,key'), series);
    },
  );

  test(
    'COV-48 failed reanalysis releases progress and retries without replacing saved nights',
    () async {
      final db = await LocalDb.instance;
      final saved = [for (final day in days) await LocalDb.dayResult(day)];
      final raw = await db.query('decoded_onehz', orderBy: 'rec_ts');
      final revision = app.insightsRevision.value;
      await db.execute(
        'ALTER TABLE decoded_onehz RENAME TO authored_decoded_retained',
      );
      try {
        expect(await app.reanalyzeAll(), 0);
        expect(app.reanalyzing, false);
        expect(app.reanalyzeProgress, '');
        expect(app.insightsRevision.value, revision);
        expect(
          app.logLines.any((s) => s.contains('[derive] reanalyze failed:')),
          true,
        );
        expect([for (final day in days) await LocalDb.dayResult(day)], saved);
        expect(
          await db.query('authored_decoded_retained', orderBy: 'rec_ts'),
          raw,
        );
      } finally {
        await db.execute(
          'ALTER TABLE authored_decoded_retained RENAME TO decoded_onehz',
        );
      }
      expect(await app.reanalyzeAll(), 2, reason: app.logLines.join('\n'));
      expect(app.reanalyzing, false);
      expect(app.reanalyzeProgress, '');
      expect(app.insightsRevision.value, revision + 1);
      expect([for (final day in days) await LocalDb.dayResult(day)], saved);
      expect(await db.query('decoded_onehz', orderBy: 'rec_ts'), raw);
    },
  );
}
