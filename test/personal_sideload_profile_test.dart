import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/build_profile.dart';
import 'package:openstrap_edge/health/health_export.dart';
import 'package:openstrap_edge/live/breathing_live_activity.dart';
import 'package:openstrap_edge/live/live_activity.dart';
import 'package:openstrap_edge/sync/ios_bg_task.dart';
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
}
