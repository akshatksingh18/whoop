// A disable already accepted when the OS backgrounds the app;real SQLite refusal.
// Recalculation remains deferred in background,so this probe runs no heavy derive.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('phone-disable-storage'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final refused in [false, true]) {
    for (final bandRows in [false, true]) {
      test(
        'COV-64 accepted phone disable refusal=$refused bandRows=$bandRows preserves source ownership and retries',
        () async {
          const date = '2021-04-06';
          final start = DateTime(2021, 4, 6, 12).millisecondsSinceEpoch ~/ 1000;
          await LocalDb.replacePhoneCoverageForDay(date, [
            (startTs: start, endTs: start + 3600, steps: 100),
          ]);
          final db = await LocalDb.instance;
          if (bandRows) {
            await db.insert('live_coverage', {
              'start_ts': start,
              'end_ts': start + 3600,
              'steps': 40,
              'day': date,
              'source': 'band',
            });
          }
          await LocalDb.putMetricSeriesValue(date, 'steps', 100);
          final before = await db.query('live_coverage', orderBy: 'id');
          final band = before.where((r) => r['source'] == 'band').toList();
          final totals = await db.query('metric_series');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('phone_steps', true);
          final app = AppState.forTesting()
            ..phoneStepsEnabled = true
            ..phoneStepsToday = 100;
          try {
            if (refused) {
              await db.execute(
                "CREATE TRIGGER authored_refuse_phone_clear BEFORE DELETE ON live_coverage WHEN OLD.source='phone' BEGIN SELECT RAISE(ABORT,'authored phone clear refusal'); END",
              );
            }
            final disable = app.disablePhoneSteps();
            // A pending preference write lets the real lifecycle signal arrive
            // before its background re-derive request. No fake worker result.
            await app.pauseForBackground(isIOS: false);
            await disable;
            expect(app.phoneStepsEnabled, false);
            expect(prefs.getBool('phone_steps'), false);
            expect(app.phoneStepsToday, 0);
            expect(app.phoneStepsLastSyncedDays, isNull);
            expect(app.phoneStepsLastTotal, isNull);
            expect(app.reanalyzing, false);
            expect(app.deriving, false);
            expect(await db.query('day_result'), isEmpty);
            expect(await db.query('metric_series'), totals);
            expect(
              await db.query('live_coverage', orderBy: 'id'),
              refused ? before : band,
            );
            if (refused) {
              await db.execute('DROP TRIGGER authored_refuse_phone_clear');
              await app.disablePhoneSteps();
            }
            // Repeating the accepted disable must clear only phone windows.
            await app.disablePhoneSteps();
            expect(await db.query('live_coverage', orderBy: 'id'), band);
            expect(await db.query('metric_series'), totals);
            expect(await db.query('day_result'), isEmpty);
            expect(app.reanalyzing || app.deriving, false);
          } finally {
            app.dispose();
            await db.execute(
              'DROP TRIGGER IF EXISTS authored_refuse_phone_clear',
            );
          }
        },
      );
    }
  }
}
