// Synthetic query profiling; opt-in so CI does not benchmark shared runners.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'profile actual readers over multi-year synthetic histories',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = (await t.runAsync(
        () => Directory.systemTemp.createTemp('whoop-synthetic-history-'),
      ))!;
      await t.runAsync(() => LocalDb.close());
      final oldName = LocalDb.dbName;
      LocalDb.dbName = '${root.path}/history.db';
      final app = AppState.forTesting();
      final repo = LocalRepositoryImpl(getProfileMap: () => null);
      app.repo = repo;
      late BuildContext context;
      await t.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      try {
        await t.runAsync(() async {
          final db = await LocalDb.instance;
          autoCountKcalGoal = 2400;
          final rows = <Map<String, dynamic>>[];
          var seeded = 0;
          final first = DateTime(2010);
          for (final years in [3, 10]) {
            final n = years * 365;
            await db.transaction((tx) async {
              final batch = tx.batch();
              for (var i = seeded; i < n; i++) {
                final day = first.add(Duration(days: i));
                final date = dayLabelOf(day);
                final ts = day.millisecondsSinceEpoch ~/ 1000;
                for (var meal = 0; meal < 4; meal++) {
                  batch.insert(
                    'food_entry',
                    FoodEntry(
                      id: 'synthetic-$i-$meal',
                      date: date,
                      meal: 'lunch',
                      label: 'Synthetic food $meal',
                      atTs: ts + (8 + meal * 3) * 3600,
                      kcal: 600,
                      proteinG: 30,
                      carbsG: 80,
                      fatG: 18,
                      fibreG: 8,
                    ).toRow(1),
                  );
                }
                batch.insert('body_weight', {
                  'date': date,
                  'kg': 70 + (i % 13) / 10,
                  'at_ts': ts,
                  'source': 'synthetic',
                  'history_only': 1,
                });
                for (final key in ['steps', 'sleep_min', 'readiness']) {
                  batch.insert('metric_series', {
                    'date': date,
                    'key': key,
                    'value': 70,
                  });
                }
                if (i % 7 < 3) {
                  batch.insert('sessions', {
                    'id': 'synthetic-$i',
                    'start_ts': ts + 3600,
                    'end_ts': ts + 7200,
                    'type': 'weightlifting',
                    'status': 'done',
                    'source': 'manual',
                    'created_at': 1,
                    'duration_min': 60,
                  });
                }
              }
              await batch.commit(noResult: true);
            });
            seeded = n;
            final measurements = <String, int>{};
            Future<T> time<T>(String key, Future<T> Function() read) async {
              final sw = Stopwatch()..start();
              final value = await read();
              measurements[key] = sw.elapsedMicroseconds;
              final status = File(
                'build/research-local/synthetic-history-progress.json',
              );
              await status.parent.create(recursive: true);
              await status.writeAsString(
                jsonEncode({
                  'synthetic_years': years,
                  'timings_microseconds': measurements,
                }),
              );
              return value;
            }

            await time(
              'counting_first_open_us',
              () => NutritionDb.freezeCounting(db),
            );
            await time('steps_chart_us', () => repo.getChart('steps'));
            final progress = await time(
              'progress_load_us',
              () => ProgressData.load(context),
            );
            expect(progress.readErrors, isEmpty);
            expect(progress.food.length, n);
            expect(progress.weights.length, n);
            await time(
              'progress_repeat_load_us',
              () => ProgressData.load(context),
            );
            final food = await time(
              'food_month_us',
              () => NutritionDb.month(db, '2011-02'),
            );
            expect(food.days.length, 28);
            await time(
              'food_day_us',
              () => NutritionDb.entriesForDay(db, '2011-02-05'),
            );
            final sessions = await time(
              'session_all_us',
              () => repo.getWorkouts(range: 'all'),
            );
            expect((sessions['workouts'] as List).length, greaterThan(0));
            await time(
              'session_month_us',
              () => repo.getWorkouts(range: 'month'),
            );
            await db.transaction((tx) async {
              final batch = tx.batch();
              for (var i = 0; i < n; i++) {
                final day = first.add(Duration(days: i));
                final ts = day.millisecondsSinceEpoch ~/ 1000;
                batch.insert('live_coverage', {
                  'start_ts': ts + 8 * 3600,
                  'end_ts': ts + 9 * 3600,
                  'steps': 4000,
                  'day': dayLabelOf(day),
                  'source': LocalDb.kStepSourcePhone,
                  'device_id': 'synthetic',
                });
              }
              await batch.commit(noResult: true);
            });
            await time(
              'steps_chart_daily_coverage_us',
              () => repo.getChart('steps'),
            );
            await time(
              'progress_daily_coverage_us',
              () => ProgressData.load(context),
            );
            await db.delete('live_coverage');
            rows.add({
              'synthetic_years': years,
              'daily_food_entries': 4,
              'sessions_per_week': 3,
              'timings_microseconds': measurements,
            });
          }
          final out = File(
            'build/research-local/synthetic-history-profile.json',
          );
          await out.parent.create(recursive: true);
          await out.writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'synthetic_only': true,
              'platform': 'Windows SQLite FFI, not phone timing',
              'scope':
                  'Current Codex checkout Progress reader; recheck merged Claude Progress',
              'measurements': rows,
            }),
          );
        });
      } finally {
        await t.pumpWidget(const SizedBox());
        app.dispose();
        await t.runAsync(() async {
          await LocalDb.close();
          LocalDb.dbName = oldName;
          await root.delete(recursive: true);
        });
      }
    },
    skip: Platform.environment['WHOOP_SYNTHETIC_PROFILE'] != '1',
  );
}
