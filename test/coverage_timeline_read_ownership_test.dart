// Actual active day screen, scripted read latency/refusal, isolated saved store.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/day_timeline.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const newer = '2021-04-06', older = '2021-04-05';

class TimelineReader extends LocalRepositoryImpl {
  TimelineReader() : super(getProfileMap: () => {});
  final refused = <String>{};
  final pending = <String, Completer<Map<String, dynamic>>>{};
  final reads = <String>[];
  bool nap = false;
  @override
  Future<List<String>> availableDays() async => [newer, older];
  @override
  Future<Map<String, dynamic>> getToday() async => {
    'status': {'today_day': newer},
  };
  @override
  Future<Map<String, dynamic>> getDayWear(String day) async => {};
  @override
  Future<Map<String, dynamic>> getDayTimeline(String day) async {
    reads.add(day);
    final gate = pending[day];
    if (gate != null) return gate.future;
    if (refused.contains(day)) throw StateError('authored read refusal');
    return contents(day, nap: nap);
  }

  Map<String, dynamic> contents(String day, {bool nap = false}) {
    final start = localDayStartSec(day)!;
    return {
      'day_start': start,
      'sleep': [
        if (!nap) {'onset_ts': start, 'wake_ts': start + 6 * 3600},
      ],
      'naps': [
        if (nap)
          {
            'start': start + 14 * 3600,
            'end': start + 14 * 3600 + 1200,
            'duration_min': 20,
          },
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TimelineReader reader;
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('timeline-read-ownership');
  });
  setUp(() async {
    await resetCoverageStore();
    reader = TimelineReader();
    app = AppState.forTesting()..repo = reader;
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t) async {
    await localizedPage(
      t,
      const DayTimelineScreen(day: newer),
      app: app,
      settle: false,
    );
    await io(t);
  }

  Future<void> retry(WidgetTester t) async {
    final card = t.widget<StatusCard>(find.byType(StatusCard));
    expect(card.onFix, isNotNull);
    card.onFix!();
    await io(t);
  }

  Future<void> pendingRead(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pump(const Duration(milliseconds: 50));
    expect(t.takeException(), isNull);
  }

  Future<void> unchangedStore(WidgetTester t) async {
    final rows = await t.runAsync(
      () async => (await LocalDb.instance).query('day_result'),
    );
    expect(rows, isEmpty);
  }

  testWidgets(
    'initial refusal offers Retry and publishes only the accepted read',
    (t) async {
      reader.refused.add(newer);
      await open(t);
      expect(find.text('This day could not load'), findsOneWidget);
      expect(find.text('Asleep'), findsNothing);
      reader.refused.clear();
      await retry(t);
      expect(find.text('This day could not load'), findsNothing);
      expect(find.text('Asleep'), findsOneWidget);
      expect(t.widget<DayNav>(find.byType(DayNav)).day, newer);
      await unchangedStore(t);
    },
  );

  testWidgets(
    'same-day refresh refusal retains old evidence then retries fresh evidence',
    (t) async {
      await open(t);
      expect(find.text('Asleep'), findsOneWidget);
      reader.refused.add(newer);
      app.bumpInsights();
      await io(t);
      expect(find.text('Could not refresh this day'), findsOneWidget);
      expect(find.text('Asleep'), findsOneWidget);
      expect(find.text('Showing what was read before.'), findsOneWidget);
      reader.refused.clear();
      reader.nap = true;
      await retry(t);
      expect(find.text('Could not refresh this day'), findsNothing);
      expect(find.text('Asleep'), findsNothing);
      expect(find.text('Nap'), findsOneWidget);
      await unchangedStore(t);
    },
  );

  testWidgets(
    'failed day switch keeps navigation but never retains another day beneath it',
    (t) async {
      await open(t);
      reader.refused.add(older);
      t.widget<DayNav>(find.byType(DayNav)).onDay(older);
      await io(t);
      expect(find.text('This day could not load'), findsOneWidget);
      expect(find.text('Asleep'), findsNothing);
      expect(t.widget<DayNav>(find.byType(DayNav)).day, older);
      reader.refused.clear();
      await retry(t);
      expect(find.text('Asleep'), findsOneWidget);
      expect(t.widget<DayNav>(find.byType(DayNav)).day, older);
      expect(reader.reads.last, older);
      await unchangedStore(t);
    },
  );

  for (final lateFailure in [false, true]) {
    testWidgets(
      'latest selected day owns a late ${lateFailure ? 'refusal' : 'result'}',
      (t) async {
        await open(t);
        final late = Completer<Map<String, dynamic>>();
        reader.pending[older] = late;
        t.widget<DayNav>(find.byType(DayNav)).onDay(older);
        await pendingRead(t);
        reader.nap = true;
        t.widget<DayNav>(find.byType(DayNav)).onDay(newer);
        await io(t);
        expect(find.text('Nap'), findsOneWidget);
        if (lateFailure) {
          late.completeError(StateError('authored late refusal'));
        } else {
          late.complete(reader.contents(older));
        }
        await io(t);
        expect(t.widget<DayNav>(find.byType(DayNav)).day, newer);
        expect(find.text('Nap'), findsOneWidget);
        expect(find.text('Asleep'), findsNothing);
        expect(find.byType(StatusCard), findsNothing);
        await unchangedStore(t);
      },
    );
  }

  testWidgets(
    'disposed screen ignores a completing read without changing the store',
    (t) async {
      await open(t);
      final late = Completer<Map<String, dynamic>>();
      reader.pending[older] = late;
      t.widget<DayNav>(find.byType(DayNav)).onDay(older);
      await pendingRead(t);
      await t.pumpWidget(const SizedBox());
      late.complete(reader.contents(older));
      await io(t);
      expect(find.byType(DayTimelineScreen), findsNothing);
      await unchangedStore(t);
    },
  );
}
