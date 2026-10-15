import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/burst_diagnostics.dart';
import 'package:openstrap_edge/sync/wake_timing.dart';
import 'package:openstrap_edge/sync/ios_bg_task.dart';
import 'package:openstrap_edge/ble/ios_ble_restore.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/route_tracker.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/theme.dart';

GpsSample fix(int second, {double? accuracy = .5}) => GpsSample(
  lat: 0,
  lng: second * 3 / 111319.49,
  tsMs: second * 1000,
  speed: 3,
  speedAccuracy: accuracy,
);

void main() {
  test('burst continuity separates contiguous, gaps, replay and unknown', () {
    final d = BurstDiagnostics();
    String next((int, int)? range) => d.observe(
      announced: 20,
      traffic: 18,
      historical: 17,
      records: 17,
      range: range,
    );
    expect(next((100, 116)), contains('continuity=unknown'));
    expect(next((117, 133)), contains('continuity=contiguous'));
    expect(next((140, 156)), contains('delta_sec=7 continuity=gap'));
    expect(next((140, 156)), contains('continuity=overlap_or_replay'));
    expect(next(null), contains('first_ts=unknown'));
    expect(next((200, 216)), contains('continuity=unknown'));
  });
  test(
    'wake stages share one ID and always end, including errors and expiry',
    () async {
      final lines = <String>[];
      await expectLater(
        WakeTiming.run<void>('bg_task', () async {
          final t = WakeTiming.current!;
          t.event('transfer_start');
          await WakeTiming.run('nested', () async {
            expect(WakeTiming.current, same(t));
            await Future<void>.value();
            t.event('commit', records: 7);
          });
          WakeTiming.expire({'bg_task'});
          throw StateError('synthetic interruption');
        }, log: lines.add),
        throwsStateError,
      );
      expect(lines, hasLength(5));
      expect(
        lines.map((l) => RegExp(r'id=([^ ]+)').firstMatch(l)!.group(1)).toSet(),
        hasLength(1),
      );
      expect(lines[3], contains('stage=expiry'));
      expect(lines.last, contains('stage=end'));
      expect(lines.last, contains('committed_records=7'));
      expect(WakeTiming.forTransfer, isNull);
      // The platform handlers compile with the same shared timing implementation.
      expect(IosBgTask.init, isNotNull);
      expect(IosBleRestore.init, isNotNull);
    },
  );
  test('diagnostic sink failure cannot interrupt the action', () async {
    expect(
      await WakeTiming.run(
        'synthetic',
        () async => 42,
        log: (_) => throw StateError('log unavailable'),
      ),
      42,
    );
  });
  test(
    'invalid/unknown speed accuracy never becomes position-derived speed',
    () async {
      final source = StreamController<GpsSample>();
      final tracker = RouteTracker(sink: (_) async {});
      tracker.start(source.stream);
      source.add(fix(0));
      source.add(fix(5));
      await pumpEventQueue();
      expect(tracker.freshSpeedMps(5000), 3);
      source.add(fix(10, accuracy: -1));
      await pumpEventQueue();
      expect(tracker.freshSpeedMps(10000), isNull);
      expect(tracker.freshSpeedAccuracyMps(10000), isNull);
      expect(tracker.acceptedPoints, hasLength(3));
      source.add(fix(15, accuracy: null));
      await pumpEventQueue();
      expect(tracker.freshSpeedMps(15000), isNull);
      source.add(fix(20, accuracy: 3));
      await pumpEventQueue();
      expect(tracker.freshSpeedAccuracyMps(20000), 3);
      expect(tracker.freshSpeedAccuracyMps(31000), isNull);
      await tracker.stop();
      await source.close();
      tracker.dispose();
    },
  );
  testWidgets('live speed names a large platform uncertainty', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: LiveMeasured(
          allActivities.firstWhere((a) => a.typeKey == 'walking'),
          feed: () => const LiveFeed(
            gpsActive: true,
            distanceKm: 1,
            currentSpeedMps: 1.5,
            currentSpeedAccuracyMps: 3,
          ),
        ),
      ),
    );
    await t.pump();
    expect(find.textContaining('Latest GPS speed ±10.8 km/h'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
