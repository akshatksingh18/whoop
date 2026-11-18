// Active read-only destinations over real authored SQLite. Only reader latency
// and refusal are substituted; no private data, fabricated metric or native claim.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/day_strain.dart';
import 'package:whoop_companion/ui2/screens/day_steps.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/week_card.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class ControlledReader extends LocalRepositoryImpl {
  ControlledReader() : super(getProfileMap: () => {'age': 30});
  String kind = '';
  final refusals = <int>{};
  Completer<void>? first;
  int calls = 0;
  Future<void> gate() async {
    final call = ++calls;
    final denied = refusals.contains(call);
    if (call == 1 && first != null) await first!.future;
    if (denied) throw StateError('authored read refusal');
  }

  @override
  Future<List<String>> availableDays() async {
    if (kind == 'steps') await gate();
    return super.availableDays();
  }

  @override
  Future<Map<String, dynamic>> getChart(
    String key, {
    int? from,
    int? to,
  }) async {
    if (kind == 'metric') await gate();
    return super.getChart(key, from: from, to: to);
  }

  @override
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'}) async {
    // Week summaries deliberately tolerate optional chart enrichment failure.
    // Exercise their mandatory movement read, not that best-effort average.
    if (kind == 'week') await gate();
    return super.getWorkouts(range: range);
  }

  @override
  Future<Map<String, dynamic>> getDayHrv(String day) async {
    if (kind == 'daily') await gate();
    return super.getDayHrv(day);
  }

  @override
  Future<Map<String, dynamic>> getDayStrain(String day) async {
    if (kind == 'strain') await gate();
    return super.getDayStrain(day);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('reader-lifecycle-batch');
  });
  late ControlledReader reader;
  late AppState app;
  setUp(() async {
    await resetCoverageStore();
    reader = ControlledReader();
    app = AppState.forTesting()..repo = reader;
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  const errors = {
    'steps': 'Steps could not load',
    'strain': 'Strain could not load',
    'metric': 'This metric could not load',
    'daily': 'Daily chart could not load',
    'week': 'Week summary unavailable',
  };
  Widget page(String kind) => switch (kind) {
    'steps' => DayStepsDetail(day: todayLabel()),
    'strain' => DayStrainDetail(day: todayLabel()),
    'metric' => const MetricDetail('resting_hr', range: 1),
    'daily' => const TodaySignalDetail('hrv'),
    _ => const WeekCard(),
  };
  Future<void> open(WidgetTester t, String kind) async {
    reader.kind = kind;
    await localizedPage(t, Scaffold(body: page(kind)), app: app, settle: false);
    if (reader.first == null) await io(t);
  }

  void expectNoFailure(String kind) {
    expect(find.text(errors[kind]!), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  }

  for (final kind in errors.keys) {
    testWidgets(
      '$kind loader refuses honestly, retries and rereads a durable revision',
      (t) async {
        reader.refusals.add(1);
        await open(t, kind);
        expect(find.text(errors[kind]!), findsOneWidget);
        final retry = find.byWidgetPredicate(
          (w) => w is StatusCard && w.what == errors[kind],
        );
        reader.refusals.clear();
        await invokeControl(t, t.widget<StatusCard>(retry).onFix);
        await io(t);
        expectNoFailure(kind);
        final before = reader.calls;
        app.bumpInsights();
        await io(t);
        expect(reader.calls, greaterThan(before));
        expectNoFailure(kind);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('day_result'),
          ),
          isEmpty,
        );
      },
    );
    testWidgets(
      '$kind missing repository does not turn missing input into a score or error',
      (t) async {
        app.repo = null;
        await open(t, kind);
        expectNoFailure(kind);
        expect(reader.calls, 0);
      },
    );
    for (final oldFails in [false, true]) {
      testWidgets(
        '$kind newer read owns the page after a late ${oldFails ? 'refusal' : 'result'}',
        (t) async {
          final first = Completer<void>();
          reader.first = first;
          reader.refusals.add(oldFails ? 1 : 2);
          await open(t, kind);
          expect(reader.calls, 1);

          app.bumpInsights();
          await io(t);
          if (oldFails) {
            expectNoFailure(kind);
          } else {
            expect(find.text(errors[kind]!), findsOneWidget);
          }
          first.complete();
          await io(t);
          if (oldFails) {
            expectNoFailure(kind);
          } else {
            expect(find.text(errors[kind]!), findsOneWidget);
          }
          expect(t.takeException(), isNull);
        },
      );
      testWidgets(
        '$kind disposal ignores its pending ${oldFails ? 'refusal' : 'result'} and detaches revision',
        (t) async {
          final first = Completer<void>();
          reader.first = first;
          reader.refusals.add(oldFails ? 1 : 2);
          await open(t, kind);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          first.complete();
          await io(t);
          expect(t.takeException(), isNull);
          final before = reader.calls;
          app.bumpInsights();
          await io(t);
          expect(reader.calls, before);
        },
      );
    }
  }
}
