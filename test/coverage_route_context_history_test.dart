// Authored straight-line route and historical sessions; no map/provider traffic.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/run_analysis.dart' show runMix;
import 'package:whoop_companion/gps/run_history.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/run_detail.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/activity/workout_context.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

final start = DateTime(2021, 4, 6, 8);
const profile = Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70);
ActivityResult result({
  String type = 'Hiking',
  String? id = 'synthetic-route',
  bool thin = false,
}) {
  final track = [
    for (var i = 0; i <= 180; i++)
      RoutePoint(
        seq: i,
        tsMs: start.millisecondsSinceEpoch + i * 10000,
        lat: i * .0003,
        lng: 0,
        alt: 20.0,
      ),
  ];
  return ActivityResult(
    activityByName(type)!,
    sessionId: id,
    start: start,
    duration: const Duration(minutes: 30),
    calculationProfile: profile,
    hr: [
      for (var i = 0; i < 30; i++)
        thin && i > 10 ? null : (i < 15 ? 120.0 : 130.0),
    ],
    distanceKm: 6,
    movingSec: 1800,
    phoneSteps: 5000,
    steps: 4990,
    cadence: 170,
    cadenceSeries: List<double>.filled(30, 170),
    mix: runMix(track),
    track: track,
    route: [for (var i = 0; i < track.length; i++) Offset(i / 180, i / 180)],
    routePace: [for (var i = 0; i < track.length; i++) .5],
    splits: const [KmSplit(1, 300), KmSplit(.5, 150)],
  );
}

class App extends AppState {
  App() : super.forTesting();
  int changes = 0;
  @override
  void publishSessionChange() {
    changes++;
    super.publishSessionChange();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('route-context');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<App> seed() async {
    final app = App()..user = profile.toMap();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    await LocalDb.putSession({
      'id': 'synthetic-route',
      'type': 'hiking',
      'start_ts': start.millisecondsSinceEpoch ~/ 1000,
      'end_ts':
          start.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000,
      'created_at': 1,
      'status': 'done',
      'source': 'manual',
    });
    await WorkoutClock(
      'synthetic-route',
      start,
      end: start.add(const Duration(minutes: 30)),
      profile: profile,
    ).persist();
    return app;
  }

  for (final thin in [false, true]) {
    testWidgets(
      'journey summary ${thin ? 'withholds sparse' : 'describes comparable'} within-session HR drift',
      (t) async {
        final app = (await t.runAsync(seed))!;
        addTearDown(app.dispose);
        await localizedPage(t, ActivitySummary(result(thin: thin)), app: app);
        final text = (await readPage(t)).join(' ');
        expect(text, contains('Heart-rate drift'));
        expect(
          text,
          contains(
            thin
                ? 'Not enough comparable data'
                : '+10.0 bpm at similar recorded pace',
          ),
        );
        expect(
          text,
          contains('This does not change calories or diagnose fitness.'),
        );
      },
    );
  }
  testWidgets(
    'saved context changes persist, invalidate drift and leave energy unchanged',
    (t) async {
      final app = (await t.runAsync(seed))!;
      addTearDown(app.dispose);
      final r = result();
      final calories = r.calories;
      await localizedPage(t, ActivitySummary(r), app: app);
      await reveal(t, find.byType(WorkoutContextSelector));
      t
          .widget<WorkoutContextSelector>(find.byType(WorkoutContextSelector))
          .onChanged(['hills']);
      await t.runAsync(WorkoutClock.flushWrites);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pumpAndSettle();
      expect(WorkoutClock.read('synthetic-route', start).results['context'], [
        'hills',
      ]);
      expect(app.changes, 1);
      final text = (await readPage(t)).join(' ');
      expect(text, contains('Not enough comparable data in both halves'));
      expect(r.calories, calories);
      await reveal(t, find.byType(WorkoutContextSelector));
      expect(
        t
            .widget<WorkoutContextSelector>(find.byType(WorkoutContextSelector))
            .tags,
        ['hills'],
      );
    },
  );
  for (final rank in [1, 2, 3]) {
    testWidgets(
      'record rank $rank reaches the route pins and best-effort description',
      (t) async {
        final view = RunView(result(type: 'Running', id: null));
        expect(view.efforts, contains('1K'));
        final earlier = [
          for (var i = 0; i < 3; i++)
            RunSummary(
              'synthetic-$i',
              start.subtract(Duration(days: i + 1)),
              6000,
              1800,
              {
                for (final e in view.efforts.entries)
                  e.key: e.value + (i < rank - 1 ? -10 : 10),
              },
            ),
        ];
        final medals = runMedals(view, earlier);
        expect(medals, isNotEmpty);
        expect(medals.every((m) => m.rank == rank), isTrue);
        final label = rank == 1
            ? 'Fastest 1K'
            : '${rank == 2 ? '2nd' : '3rd'} best 1K';
        expect(medals.map((m) => m.label), contains(label));
        await localizedPage(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  RunMapCard(view, cursor: .5, medals: medals),
                  BestEffortsCard(view, earlier),
                ],
              ),
            ),
          ),
        );
        final text = (await readPage(t)).join(' ');
        expect(text, contains(label));
        expect(
          text,
          contains(
            rank == 1 ? '00:10 faster' : (rank == 2 ? '2nd best' : '3rd best'),
          ),
        );
      },
    );
  }
  testWidgets(
    'walking charts use chosen miles, measured cadence and linked cursor',
    (t) async {
      final view = RunView(result(type: 'Walking', id: null));
      final units = UnitsController.seed(UnitSystem.imperial);
      addTearDown(units.dispose);
      final cursor = ValueNotifier<double?>(null);
      addTearDown(cursor.dispose);
      await localizedPage(
        t,
        ChangeNotifierProvider<UnitsController>.value(
          value: units,
          child: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<double?>(
                valueListenable: cursor,
                builder: (_, f, _) => Column(
                  children: [
                    RunStatsGrid(view),
                    RunSplitsCard(view.r),
                    RunCharts(
                      view,
                      cursor: f,
                      onCursor: (v) => cursor.value = v,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final scrub = find.byWidgetPredicate(
        (w) =>
            w is Scrubber &&
            w.label == 'Pace, heart rate and elevation through the run',
      );
      await reveal(t, scrub);
      t.widget<Scrubber>(scrub).onChanged(.5);
      await t.pumpAndSettle();
      final text = (await readPage(t)).join(' ');
      expect(text, contains('mph'));
      expect(text, contains('170 spm'));
      expect(text, contains('km splits (as recorded)'));
      expect(text, contains('5,000'));
      expect(cursor.value, .5);
    },
  );
}
