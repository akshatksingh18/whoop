// Authored rollups + real SQLite through the import-finalization entry point.
// These verify delivery contracts, not physiological detector validity or OS delivery.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/findings.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/fired_keys.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final center = NotificationCenter.instance;
  final originalSink = center.presentSink;
  final events = <NotificationEvent>[];
  final logs = <String>[];
  late String today;
  late DateTime calendar;
  late DerivationEngine engine;
  String label(int offset) => dayLabelOf(
    DateTime(calendar.year, calendar.month, calendar.day + offset),
  );
  setUpAll(() => coverageStore('derivation-notifications'));
  setUp(() async {
    await resetCoverageStore();
    today = todayLabel();
    calendar = DateTime.parse(today);
    events.clear();
    logs.clear();
    engine = DerivationEngine(log: logs.add);
    await const NotificationPrefs(quietEnabled: false).save();
    center.presentSink = (e, {bool allowPermissionPrompt = true}) async {
      events.add(e);
      return true;
    };
  });
  tearDown(() => center.presentSink = originalSink);
  tearDownAll(LocalDb.close);
  Map<String, dynamic> bundle({
    String? date,
    bool illness = false,
    bool anomaly = false,
    bool temp = false,
    List<Map<String, dynamic>>? recent,
  }) => {
    'recent':
        recent ??
        [
          {'date': date ?? today, 'unsettled': false},
        ],
    'illness': {'date': date ?? today, 'state': illness ? 'red' : 'green'},
    'anomaly': {'date': date ?? today, 'flagged': anomaly},
    'temp_illness': {
      'date': date ?? today,
      'flag': temp ? 'elevated' : 'normal',
    },
  };
  Future<void> run(Map<String, dynamic>? rollup) async {
    if (rollup != null) {
      await LocalDb.putBaseline('crossday', jsonEncode(rollup));
    }
    await engine.finalizeImport(const Profile());
    // No derived nights are fabricated to get into notification orchestration.
    expect(
      jsonDecode(
        (await LocalDb.baseline('crossday_status'))!['payload_json'] as String,
      )['kind'],
      'needs_history',
    );
  }

  const fired = FiredKeyStore();
  for (final kind in [
    FindingKind.illness,
    FindingKind.anomaly,
    FindingKind.tempElevated,
    FindingKind.lowReadiness,
  ]) {
    test(
      'COV-46 import finalization emits the shared $kind finding once',
      () async {
        if (kind == FindingKind.lowReadiness) {
          await LocalDb.putMetricSeriesValue(today, 'readiness', 20);
        }
        final rollup = bundle(
          illness: kind == FindingKind.illness,
          anomaly: kind == FindingKind.anomaly,
          temp: kind == FindingKind.tempElevated,
        );
        await run(rollup);
        final event = events.single;
        final expected = Finding(kind, today);
        expect(event.title, expected.title);
        expect(event.body, expected.detail);
        expect(event.date, today);
        expect(event.route, '/heart');
        expect(event.priority, NotifPriority.normal);
        expect(event.category, NotifCategory.health);
        expect(
          event.dedupeKey,
          expected.medical ? '$today:exception:medical' : '$today:exception',
        );
        await run(rollup);
        expect(events, hasLength(1));
      },
    );
  }
  test(
    'COV-46 correlated findings aggregate and medical deescalation stays silent',
    () async {
      await LocalDb.putMetricSeriesValue(today, 'readiness', 20);
      await run(bundle(illness: true, anomaly: true, temp: true));
      expect(events.single.title, '4 things to look at');
      for (final kind in [
        FindingKind.illness,
        FindingKind.anomaly,
        FindingKind.tempElevated,
        FindingKind.lowReadiness,
      ]) {
        expect(events.single.body, contains(Finding(kind, today).title));
      }
      expect(await fired.hasFired('$today:exception'), true);
      expect(await fired.hasFired('$today:exception:medical'), true);
      await run(bundle());
      expect(events, hasLength(1));
    },
  );
  test(
    'COV-46 low readiness does not consume a later medical escalation',
    () async {
      await LocalDb.putMetricSeriesValue(today, 'readiness', 20);
      await run(bundle());
      expect(events.single.dedupeKey, '$today:exception');
      await run(bundle(illness: true));
      expect(events, hasLength(2));
      expect(events.last.dedupeKey, '$today:exception:medical');
      await run(bundle(illness: true, temp: true));
      expect(events, hasLength(2));
    },
  );
  for (final outcome in ['false', 'throws']) {
    test(
      'COV-46 refused OS handoff $outcome leaves both severity classes retryable',
      () async {
        center.presentSink = (e, {bool allowPermissionPrompt = true}) async {
          events.add(e);
          if (outcome == 'throws') {
            throw StateError('synthetic present refusal');
          }
          return false;
        };
        await run(bundle(illness: true));
        expect(await fired.hasFired('$today:exception:medical'), false);
        expect(await fired.hasFired('$today:exception'), false);
        center.presentSink = (e, {bool allowPermissionPrompt = true}) async {
          events.add(e);
          return true;
        };
        await run(bundle(illness: true));
        expect(events, hasLength(2));
        expect(await fired.hasFired('$today:exception:medical'), true);
        expect(await fired.hasFired('$today:exception'), true);
      },
    );
  }
  for (final offset in [0, -1, -2, 1]) {
    test(
      'COV-46 import notification date offset $offset uses the local freshness window',
      () async {
        final date = label(offset);
        await run(bundle(date: date, illness: true));
        expect(events, hasLength(offset == 0 || offset == -1 ? 1 : 0));
        if (events.isNotEmpty) expect(events.single.date, date);
        expect(
          await fired.hasFired('$date:exception:medical'),
          offset == 0 || offset == -1,
        );
      },
    );
  }
  for (final source in ['illness', 'anomaly', 'temp_illness']) {
    test('COV-46 an absent recent date falls back to $source', () async {
      final rollup = <String, dynamic>{
        'recent': [
          null,
          {'unsettled': true},
        ],
        source: {
          'date': today,
          if (source == 'illness') 'state': 'red',
          if (source == 'anomaly') 'flagged': true,
          if (source == 'temp_illness') 'flag': 'elevated',
        },
      };
      await run(rollup);
      expect(events.single.date, today);
    });
  }
  test(
    'COV-46 missing rollup/date and benign signals never fabricate an alert',
    () async {
      await run(null);
      await run({
        'illness': {'state': 'red'},
      });
      await LocalDb.putMetricSeriesValue(today, 'readiness', 26);
      await LocalDb.putMetricSeriesValue(today, 'irregular_rhythm', 1);
      await run(bundle());
      expect(events, isEmpty);
      expect(await fired.hasFired('$today:exception'), false);
    },
  );
  test(
    'COV-46 malformed notification artifact is logged and a corrected one retries',
    () async {
      await run({
        'recent': [
          {'date': 123},
        ],
        'illness': {'state': 'red'},
      });
      expect(logs.any((s) => s.contains('notifications FAILED/skipped')), true);
      expect(events, isEmpty);
      await run(bundle(illness: true));
      expect(events, hasLength(1));
    },
  );
  test(
    'COV-46 muting findings changes only the delivered aggregate and dedupe class',
    () async {
      await LocalDb.putMetricSeriesValue(today, 'readiness', 20);
      await const NotificationPrefs(
        quietEnabled: false,
        mutedFindings: {'illness', 'anomaly', 'tempElevated', 'lowReadiness'},
      ).save();
      final rollup = bundle(illness: true, anomaly: true, temp: true);
      await run(rollup);
      expect(events, isEmpty);
      expect(await fired.hasFired('$today:exception:medical'), false);
      await const NotificationPrefs(
        quietEnabled: false,
        mutedFindings: {'illness', 'anomaly', 'tempElevated'},
      ).save();
      await run(rollup);
      expect(
        events.single.title,
        Finding(FindingKind.lowReadiness, today).title,
      );
      expect(events.single.dedupeKey, '$today:exception');
      await const NotificationPrefs(quietEnabled: false).save();
      await run(rollup);
      expect(events, hasLength(2));
      expect(events.last.title, '4 things to look at');
      expect(
        jsonDecode(
          (await LocalDb.baseline('crossday'))!['payload_json'] as String,
        ),
        rollup,
      );
    },
  );
  for (final gate in ['health-off', 'quiet']) {
    test(
      'COV-46 $gate suppression keeps the finalization alert retryable',
      () async {
        final now = DateTime.now();
        await NotificationPrefs(
          healthEnabled: gate != 'health-off',
          quietEnabled: gate == 'quiet',
          quietStartMin: now.hour * 60,
          quietEndMin: (now.hour * 60 + 120) % 1440,
        ).save();
        await run(bundle(illness: true));
        expect(events, isEmpty);
        expect(await fired.hasFired('$today:exception:medical'), false);
        await const NotificationPrefs(quietEnabled: false).save();
        await run(bundle(illness: true));
        expect(events, hasLength(1));
      },
    );
  }
  for (final variant in [
    'rise',
    'fall',
    'unsettled',
    'old-shift',
    'gap',
    'flat',
    'short',
  ]) {
    test(
      'COV-46 resting-HR $variant respects current-date and evidence gates',
      () async {
        final recent = <Map<String, dynamic>>[
          for (var i = 0; i < 10; i++)
            {
              'date': label(i - (variant == 'gap' ? 20 : 10)),
              'rhr': variant == 'flat' ? 50 : 50 + i % 2,
            },
          {
            'date': variant == 'old-shift' ? label(-1) : today,
            'rhr': variant == 'fall' ? 25 : 90,
            'unsettled': variant == 'unsettled',
          },
          if (variant == 'old-shift') {'date': today, 'rhr': null},
        ];
        if (variant == 'short') recent.removeAt(0);
        await run(bundle(recent: recent));
        expect(
          events,
          hasLength(variant == 'rise' || variant == 'fall' ? 1 : 0),
        );
        if (events.isNotEmpty) {
          expect(
            events.single.title,
            Finding(FindingKind.rhrShift, today).title,
          );
          expect(
            events.single.body,
            contains(variant == 'rise' ? 'risen' : 'fallen'),
          );
          expect(events.single.dedupeKey, '$today:exception');
        }
      },
    );
  }
}
