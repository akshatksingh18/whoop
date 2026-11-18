// Authored sessions exercise Train's retained disclosures and navigation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/day_strain.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/screens/log_workout.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_session_destination_boundaries_test.dart' show io;
import 'coverage_workout_history_actions_test.dart' show action;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class Reader extends LocalRepositoryImpl {
  Reader() : super(getProfileMap: () => profile);
  bool refuse = false;
  @override
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'}) {
    if (refuse) throw StateError('synthetic history read refusal');
    return super.getWorkouts(range: range);
  }
}

const profile = {'age': 30, 'sex': 'f', 'weight_kg': 70.0, 'height_cm': 170.0};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late Reader repo;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('train-retained-history');
  });
  setUp(() async {
    await resetCoverageStore();
    repo = Reader();
    app = AppState.forTesting()..user = profile;
    app.repo = repo;
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, Widget page) async {
    await localizedPage(t, page, app: app, settle: false);
    await io(t);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await io(t);
  }

  Future<void> session({bool old = false, bool unknown = false}) async {
    final at = old
        ? DateTime(2021, 4, 6, 8)
        : DateTime.now().subtract(const Duration(minutes: 40));
    final ts = at.millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'synthetic-saved',
      'type': 'running',
      'start_ts': ts,
      'end_ts': ts + 1200,
      'status': 'done',
      'source': 'manual',
      'created_at': 1,
      'steps': 1200,
      'end_ts_fabricated': unknown ? 1 : 0,
    });
  }

  for (final n in [1, 2]) {
    testWidgets('Train discloses $n unconfirmed efforts without logging them', (
      t,
    ) async {
      final at = DateTime(2021, 4, 6, 8).millisecondsSinceEpoch ~/ 1000;
      for (var i = 0; i < n; i++) {
        await LocalDb.putWorkoutSuggestion({
          'id': 'synthetic-effort-$i',
          'date': '2021-04-06',
          'start_ts': at + i * 3600,
          'end_ts': at + i * 3600 + 900,
          'sport': 'Running',
          'avg_bpm': 120,
          'peak_bpm': 140,
          'created_at': 1,
        });
      }
      await open(t, const WorkoutScreen());
      final card = find.byWidgetPredicate(
        (w) => w is StatusCard && w.what.contains('spotted'),
      );
      expect(card, findsOneWidget);
      expect(t.widget<StatusCard>(card).what, contains('$n effort'));
      t.widget<StatusCard>(card).onFix!();
      await io(t);
      final review = t.widget<WorkoutSuggestionScreen>(
        find.byType(WorkoutSuggestionScreen),
      );
      expect(
        review.preloaded!.map((s) => s.id),
        containsAll([for (var i = 0; i < n; i++) 'synthetic-effort-$i']),
      );
      expect(
        await t.runAsync(
          () async => (await LocalDb.instance).query('sessions'),
        ),
        isEmpty,
      );
      Navigator.of(t.element(find.byType(WorkoutSuggestionScreen))).pop();
      await io(t);
      expect(
        (await t.runAsync(LocalDb.activeWorkoutSuggestions))!,
        hasLength(n),
      );
    });
  }
  testWidgets(
    'Train history link preserves its weight context and return route',
    (t) async {
      await session();
      await open(t, const WorkoutScreen());
      await tap(t, find.text('All workouts'));
      expect(
        t
            .widget<WorkoutHistoryScreen>(find.byType(WorkoutHistoryScreen))
            .weightKg,
        70,
      );
      Navigator.of(t.element(find.byType(WorkoutHistoryScreen))).pop();
      await io(t);
      expect(find.byType(WorkoutScreen), findsOneWidget);
    },
  );
  testWidgets('a selected strain day reaches that day rather than today', (
    t,
  ) async {
    await LocalDb.putMetricSeriesValue(todayLabel(), 'strain', 3.5);
    await open(t, const WorkoutScreen());
    final chart = find.byWidgetPredicate(
      (w) => w is Scrubber && w.label == 'Strain, last 7 days',
    );
    await reveal(t, chart);
    t.widget<Scrubber>(chart).onChanged(0);
    await t.pumpAndSettle();
    final surface = find.byWidgetPredicate(
      (w) =>
          w is Surface &&
          w.semanticLabel == 'Strain, last 7 days. Opens the day.',
    );
    t.widget<Surface>(surface).onTap!();
    await io(t);
    final expected = DateTime.parse(todayLabel());
    expect(
      t.widget<DayStrainDetail>(find.byType(DayStrainDetail)).day,
      dayLabelOf(DateTime(expected.year, expected.month, expected.day - 6)),
    );
  });
  testWidgets('history read refusal keeps Retry and recovers its saved month', (
    t,
  ) async {
    await session(old: true);
    repo.refuse = true;
    await open(t, const WorkoutHistoryScreen());
    final card = find.byWidgetPredicate(
      (w) => w is StatusCard && w.what == 'Workouts could not load',
    );
    expect(card, findsOneWidget);
    repo.refuse = false;
    await invokeControl(t, t.widget<StatusCard>(card).onFix);
    await io(t);
    expect(find.text('April 2021'), findsOneWidget);
    expect(card, findsNothing);
    final month = find
        .ancestor(of: find.text('April 2021'), matching: find.byType(Pressable))
        .first;
    await tap(t, month);
    expect(action('Open Running session'), findsOneWidget);
    await tap(t, month);
    expect(action('Open Running session'), findsNothing);
  });
  testWidgets(
    'expanded history keeps the calorie methods and opens its stored session',
    (t) async {
      await session();
      await open(t, const WorkoutHistoryScreen());
      final row = find.byWidgetPredicate(
        (w) =>
            w is Surface &&
            w.semanticLabel?.endsWith('tap for details') == true,
      );
      t.widget<Surface>(row).onTap!();
      await io(t);
      final text = (await readPage(t)).join(' ');
      expect(
        text,
        contains('Active calories above resting; counted once in maintenance.'),
      );
      await tap(t, action('Open this session'));
      expect(
        t
            .widget<ActivitySummary>(find.byType(ActivitySummary))
            .result
            .sessionId,
        'synthetic-saved',
      );
    },
  );
  testWidgets(
    'an interrupted history row reaches correction and cancel preserves the unknown end',
    (t) async {
      await session(unknown: true);
      await open(t, const WorkoutHistoryScreen());
      await tap(t, action('Open Running session'));
      expect(find.byType(SessionDestination), findsOneWidget);
      expect(find.text('Finish time unknown'), findsOneWidget);
      expect(find.byType(ActivitySummary), findsNothing);
    },
  );
}
