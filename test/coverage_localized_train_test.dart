// Train's saved rows and detector proposals under the actual shipped delegates.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/screens/log_workout.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class TrainRepo extends LocalRepositoryImpl {
  TrainRepo(this.row) : super(getProfileMap: () => {'weight_kg': 70.0});
  final Map<String, dynamic> row;
  @override
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'}) async => {
    'workouts': [row],
  };
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async => {
    'points': [
      {'t': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'v': 5.0},
    ],
  };
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('localized-train');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final unknown in [false, true]) {
    testWidgets(
      'COV-44 Train expanded session keeps recorded zones and end provenance $unknown',
      (t) async {
        final at =
            DateTime.now()
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000;
        final app = AppState.forTesting()
          ..user = {'age': 30, 'sex': 'f', 'height_cm': 170, 'weight_kg': 70}
          ..repo = TrainRepo({
            'id': 'synthetic-cycling',
            'type': 'cycling',
            'start_ts': at,
            'end_ts': at + 1800,
            'status': 'done',
            'source': 'manual',
            'strain': 5.0,
            'avg_hr': 120,
            'max_hr': 150,
            'hrr60': 15,
            'steps': 2000,
            'zone_min': [2, 3, 4, 5, 6],
            'end_ts_fabricated': unknown,
          });
        addTearDown(app.dispose);
        await localizedPage(t, const Scaffold(body: WorkoutScreen()), app: app);
        final row = find.byWidgetPredicate(
          (w) =>
              w is Surface && w.semanticLabel?.startsWith('Cycling,') == true,
        );
        await reveal(t, row);
        await invokeControl(t, t.widget<Surface>(row).onTap);
        await t.pumpAndSettle();
        final content = (await readPage(t)).join(' ');
        expect(content, contains('TIME IN ZONES'));
        expect(content, contains('Z5 · 6m'));
        expect(content, contains('Fix the times'));
        if (unknown) expect(content, contains('Finish time unknown'));
        await reveal(t, find.byType(Scrubber).first);
        t.widget<Scrubber>(find.byType(Scrubber).first).onChanged(0);
        await t.pumpAndSettle();
        expect(t.widget<Scrubber>(find.byType(Scrubber).first).value, 0);
      },
    );
  }
  for (final populated in [false, true]) {
    testWidgets(
      'COV-44 localized detector proposals keep their actual window and peak $populated',
      (t) async {
        final at = DateTime(2021, 4, 6, 12).millisecondsSinceEpoch ~/ 1000;
        await localizedPage(
          t,
          WorkoutSuggestionScreen(
            preloaded: populated
                ? [
                    Suggestion(
                      id: 'synthetic-bout',
                      startTs: at,
                      endTs: at + 1200,
                      sport: 'cycling',
                      peakBpm: 150,
                      avgBpm: 120,
                    ),
                  ]
                : [],
          ),
        );
        final text = (await readPage(t)).join(' ');
        expect(text, contains(populated ? '20 min' : 'Nothing to review'));
        if (populated) {
          expect(text, contains('Peak HR'));
          expect(text, contains('150'));
          expect(text, contains('Not a workout'));
          expect(text, contains('Log it'));
        }
      },
    );
  }
}
