import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart' show kOura;
import 'package:openstrap_edge/build_profile.dart';
import 'package:openstrap_edge/health/health_export.dart';
import 'package:openstrap_edge/live/breathing_live_activity.dart';
import 'package:openstrap_edge/live/live_activity.dart';
import 'package:openstrap_edge/sync/ios_bg_task.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart' show kPairableSensors;
import 'package:openstrap_edge/widget/widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('personal build gates native extension and HealthKit seams', () async {
    if (!kPersonalSideload) return;

    expect(kPersonalSideload, isTrue);
    expect(
      await HealthExporter.exportWorkoutId('must-not-read-the-database'),
      isFalse,
    );
    expect(
      await HealthExporter.shared.exportWorkout(const {'status': 'complete'}),
      isFalse,
    );
    await HealthExporter.deleteWorkoutWindow(0, 1);
    expect(await HealthExporter.shared.exportAll(), 0);

    await IosBgTask.init();
    await WidgetService.init();
    await WidgetService.clear();
    expect(await WidgetService.consumeEndSessionFlag(), isFalse);
    expect(await WidgetService.consumePendingRoute(), isNull);
    expect(await WidgetService.consumeEndBreathingFlag(), isFalse);

    await LiveActivity.end();
    await BreathingLiveActivity.end();
  });

  test('personal GPS and pairing surfaces match the declared profile', () {
    if (!kPersonalSideload) return;

    expect(
      kPairableSensors.map((sensor) => sensor.entry.id),
      isNot(contains(kOura.id)),
      reason: 'Oura is retained in source but unsupported in the personal UI',
    );

    final source = File('lib/state/app_state.dart').readAsStringSync();
    final start = source.indexOf(
      'Future<void> _maybeStartRouteTracking(String id, String type) async',
    );
    final end = source.indexOf('Future<void> retryRouteTracking()', start);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final routeStart = source.substring(start, end);
    expect(routeStart, isNot(contains('kPersonalSideload')));
    expect(routeStart, contains('GpsSource.ensurePermission()'));
    expect(routeStart, contains('tracker.start(GpsSource.stream())'));
  });
}
