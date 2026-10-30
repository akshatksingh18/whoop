// Signal inspection and correction controls with authored measured/missing windows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/models/metric.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/day_timeline.dart'
    show DayHeartCard;
import 'coverage_nutrition_root_test.dart' show io;
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class SignalRepo extends LocalRepository {
  bool fail = false;
  late int ts;
  bool emptyHeart = false;
  final heartDates = <String>[];
  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) async {
    heartDates.add(date);
    if (fail) throw StateError('synthetic pulse read refusal');
    return {
      'date': date,
      'day_start': localDayStartSec(date),
      'hr': [
        if (!emptyHeart) ...[
          {'t': ts, 'v': 60},
          {'t': ts + 120, 'v': 80},
        ],
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getDayHrv(String date) async {
    if (fail) throw StateError('synthetic read refusal');
    return {
      'date': date,
      'timeline': [
        {'t': ts, 'v': 40},
        {'t': ts + 120, 'v': 50},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getDayWear(String date) async {
    if (fail) throw StateError('synthetic read refusal');
    return {
      'date': date,
      'segments': [
        {'start': ts, 'end': ts + 7200, 'on': true},
        {'start': ts + 10800, 'end': ts + 14400, 'on': false},
      ],
    };
  }
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('signal-interactions');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final refuse in [false, true]) {
    testWidgets(
      'COV-48 daily pulse read refusal=$refuse retries and invalidates its curve on revision',
      (t) async {
        final repo = SignalRepo()
          ..fail = refuse
          ..ts = localDayStartSec(todayLabel())! + 3600;
        final app = AppState.forTesting()..repo = repo;
        addTearDown(app.dispose);
        await localizedPage(
          t,
          const Scaffold(body: TodaySignalDetail('resting_hr')),
          app: app,
        );
        await io(t);
        if (refuse) {
          expect(find.text('Daily chart could not load'), findsOneWidget);
          expect(find.byType(DayHeartCard), findsNothing);
          repo.fail = false;
          await invokeControl(
            t,
            t.widget<StatusCard>(find.byType(StatusCard)).onFix,
          );
        }
        expect(find.byType(DayHeartCard), findsOneWidget);
        final graph = t.widget<DayHeartCard>(find.byType(DayHeartCard)).g;
        expect(graph.hr.whereType<double>().toList(), [60.0, 80.0]);
        expect(graph.hr[61], isNull);
        expect(repo.heartDates, everyElement(todayLabel()));
        repo.emptyHeart = true;
        final before = repo.heartDates.length;
        app.bumpInsights();
        await io(t);
        expect(repo.heartDates.length, greaterThan(before));
        expect(find.byType(DayHeartCard), findsNothing);
        expect(find.text('Daily chart could not load'), findsNothing);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('decoded_onehz'),
          ),
          isEmpty,
        );
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );
  }
  for (final key in ['hrv', 'wear'])
    for (final fail in [false, true]) {
      testWidgets(
        'COV-44 current-day $key chart retains holes and retries reads $fail',
        (t) async {
          final repo = SignalRepo()
            ..fail = fail
            ..ts = localDayStartSec(todayLabel())!;
          final app = AppState.forTesting()..repo = repo;
          addTearDown(app.dispose);
          await localizedPage(
            t,
            Scaffold(body: TodaySignalDetail(key)),
            app: app,
          );
          if (fail) {
            expect(find.text('Daily chart could not load'), findsOneWidget);
            repo.fail = false;
            final card = t.widget<StatusCard>(find.byType(StatusCard));
            await invokeControl(t, card.onFix);
          }
          final scrub = find.byType(Scrubber);
          expect(scrub, findsOneWidget);
          final s = t.widget<Scrubber>(scrub);
          s.onChanged(key == 'hrv' ? .5 : 0);
          await t.pumpAndSettle();
          final texts = t
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data ?? '')
              .join(' ');
          expect(
            t.widget<ChartFrame>(find.byType(ChartFrame)).readout,
            contains(key == 'hrv' ? 'not recorded' : '60 min'),
          );
          expect(
            texts,
            contains(key == 'hrv' ? 'HRV through the night' : 'Wear by hour'),
          );
        },
        timeout: const Timeout(Duration(seconds: 25)),
      );
    }
  for (final gap in [false, true]) {
    testWidgets(
      'COV-44 sleep scrubber reports measured signals and stage gaps $gap',
      (t) async {
        const day = '2021-04-06';
        final at = DateTime(2021, 4, 6, 1).millisecondsSinceEpoch ~/ 1000;
        final data = SleepData(
          day: day,
          days: [day],
          night: {
            'duration_min': 420,
            'in_bed_min': 480,
            'efficiency': .875,
            'onset_ts': at,
            'wake_ts': at + 28800,
            'deep_min': 80,
            'light_min': 240,
            'rem_min': 100,
            'hypnogram': [
              {'t': at, 'stage': 'light'},
              {'t': at + 7200, 'stage': gap ? 'unobserved_gap' : 'deep'},
              {'t': at + 14400, 'stage': 'rem'},
              {'t': at + 28800, 'stage': 'wake'},
            ],
          },
          timeline: {
            'hr': [
              {'t': at, 'v': 50},
              {'t': at + 28800, 'v': 60},
            ],
            'hrv': [
              {'t': at, 'v': 45},
            ],
          },
          naps: [
            {
              'start': at + 43200,
              'end': at + 45000,
              'duration_min': 30,
              'source': 'manual',
            },
          ],
        );
        await localizedPage(t, SleepDetail(data: data));
        await reveal(t, find.byType(Scrubber).first);
        t.widget<Scrubber>(find.byType(Scrubber).first).onChanged(.3);
        await t.pumpAndSettle();
        final scrub = t.widget<Scrubber>(find.byType(Scrubber).first);
        expect(scrub.value, .3);
        expect(scrub.describe(.3), contains(gap ? 'not measured' : 'Deep'));
        scrub.onChanged(0);
        await t.pumpAndSettle();
        expect(
          t.widget<Scrubber>(find.byType(Scrubber).first).describe(0),
          contains('Light'),
        );
      },
    );
  }
  for (final scored in [false, true]) {
    testWidgets(
      'COV-44 localized Recovery retains unused inputs and explanation disclosure $scored',
      (t) async {
        final data = ReadinessData(
          readiness: scored
              ? const Metric(
                  value: 65,
                  confidence: .8,
                  tier: MetricTier.estimate,
                )
              : Metric.empty,
          inputsUsed: 2,
          hrvNote: 'Synthetic thin baseline',
          breakdown: [
            {'label': 'hrv', 'used': false, 'weight': .35},
            {
              'label': 'resp',
              'used': true,
              'weight': .12,
              'weighted_contribution': -2.0,
              'past_mdc': true,
              'z': 1.5,
            },
            {
              'label': 'sleep',
              'used': true,
              'weight': .2,
              'weighted_contribution': 5.0,
              'past_mdc': false,
              'z': 0.0,
            },
          ],
          series: [40, null, 65],
        );
        await localizedPage(t, ReadinessDetail(data: data));
        final content = (await readPage(t)).join(' ');
        expect(content, contains('Synthetic thin baseline'));
        final toggle = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'How it is worked out',
        );
        await reveal(t, toggle);
        await t.tap(toggle);
        await t.pumpAndSettle();
        expect(
          (await readPage(t)).join(' '),
          contains('2 of 3 inputs were available'),
        );
      },
    );
  }
}
