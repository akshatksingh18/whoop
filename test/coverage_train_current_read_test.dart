// Train and saved-session readers over authored SQLite, not native recording.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/run_history.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_session_destination_boundaries_test.dart' show io, profile;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class _App extends AppState {
  _App() : super.forTesting();
  int pulls = 0;
  @override
  Future<String?> pullRefresh({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    pulls++;
    return 'Authored refresh finished';
  }
}

class _Reader extends LocalRepositoryImpl {
  _Reader() : super(getProfileMap: () => profile.toMap());
  bool refuseChart = true;
  @override
  Future<Map<String, dynamic>> getChart(String key, {int? from, int? to}) {
    if (refuseChart && key == 'strain') {
      throw StateError('Authored strain read refusal');
    }
    return super.getChart(key, from: from, to: to);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('train-current-read');
  });
  setUp(() async {
    await resetCoverageStore();
    runsChanged();
  });
  tearDownAll(LocalDb.close);

  testWidgets(
    'a missing repository retries, and pull refresh recovers a refused strain chart',
    (t) async {
      final app = _App();
      addTearDown(app.dispose);
      await localizedPage(
        t,
        const Scaffold(body: WorkoutScreen()),
        app: app,
        settle: false,
      );
      await io(t);
      final failed = find.byWidgetPredicate(
        (w) => w is StatusCard && w.what == 'Training history could not load',
      );
      expect(failed, findsOneWidget);
      final repo = _Reader();
      app.repo = repo;
      await invokeControl(t, t.widget<StatusCard>(failed).onFix);
      await io(t);
      expect(failed, findsNothing);
      final chart = find.byWidgetPredicate(
        (w) => w is Scrubber && w.label == 'Strain, last 7 days',
      );
      final before = (await readPage(t)).join(' ');
      expect(before, contains('No sessions recorded yet'));
      expect(
        chart,
        findsNothing,
        reason: 'An unread strain chart must not invent a measured zero',
      );
      repo.refuseChart = false;
      await t.runAsync(
        () => LocalDb.putMetricSeriesValue(todayLabel(), 'strain', 3.5),
      );
      await invokeControl(
        t,
        t
            .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
            .onRefresh,
      );
      await io(t);
      await reveal(t, chart);
      expect(t.widget<Scrubber>(chart).describe(1), contains('3.5'));
      expect(app.pulls, 1);
      expect(
        await t.runAsync(
          () async => (await LocalDb.instance).query('sessions'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'opening a saved route retains its rating and actual recorded geometry',
    (t) async {
      final app = _App()..user = profile.toMap();
      addTearDown(app.dispose);
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      final start = DateTime(2021, 4, 6, 8);
      final ts = start.millisecondsSinceEpoch ~/ 1000;
      await LocalDb.putSession({
        'id': 'authored-route',
        'type': 'running',
        'start_ts': ts,
        'end_ts': ts + 130,
        'created_at': 1,
        'source': 'manual',
        'status': 'done',
      });
      await (await LocalDb.instance).update(
        'sessions',
        {'rpe': 8.5},
        where: 'id = ?',
        whereArgs: ['authored-route'],
      );
      final points = [
        for (var i = 0; i <= 12; i++)
          RoutePoint(
            seq: i,
            tsMs: (ts + i * 10) * 1000,
            lat: 0,
            lng: i * .0002,
            accuracy: 3,
            speed: 2 + i / 10,
          ),
      ];
      await LocalDb.appendRoutePoints('authored-route', [
        for (final p in points) p.toRow('authored-route'),
      ]);
      await LocalDb.commitSyncBatch(
        [
          for (var i = 0; i < 130; i++)
            RawRecord(
              counter: i,
              packetType: 47,
              hex: 'authored',
              capturedAt: (ts + i) * 1000,
              recTs: ts + i,
            ),
        ],
        [
          for (var i = 0; i < 130; i++)
            Sample(counter: i, tsEpoch: ts + i, hr: 120 + i ~/ 30),
        ],
        deviceFamily: 'gen4',
      );
      await localizedPage(
        t,
        const SessionDestination('authored-route'),
        app: app,
        settle: false,
      );
      await io(t);
      final result = t
          .widget<ActivitySummary>(find.byType(ActivitySummary))
          .result;
      expect(result.sessionId, 'authored-route');
      expect(result.rpe, 8.5);
      expect(result.start, start);
      expect(result.duration, const Duration(seconds: 130));
      expect(
        result.track.map((p) => (p.tsMs, p.lat, p.lng)),
        points.map((p) => (p.tsMs, p.lat, p.lng)),
      );
      final row = (await t.runAsync(() => LocalDb.session('authored-route')))!;
      expect(row['rpe'], 8.5);
      expect(row['start_ts'], ts);
      expect(row['end_ts'], ts + 130);
    },
  );
}
