// Actual band-alarm lifecycle -> preference boundary refusal -> later retry.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import '../ble/durable_boundary_test.dart' show until;
import '../data/settings_controls_test.dart' show Store;
import '../support/coverage_store.dart';

class _RemoveFault extends Store {
  bool rejecting = true;
  int removals = 0;
  @override
  Future<bool> remove(String key) async {
    if (key == 'flutter.alarm_epoch') {
      removals++;
      if (rejecting) {
        throw PlatformException(code: 'authored_alarm_remove_refusal');
      }
    }
    return super.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform original;
  late _RemoveFault store;
  final oldPresent = NotificationCenter.instance.presentSink;
  setUpAll(() => coverageStore('alarm-remove-refusal', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    original = SharedPreferencesStorePlatform.instance;
    store = _RemoveFault()
      ..values.addAll({
        'flutter.alarm_epoch': 1617714000,
        'flutter.authored-unrelated-setting': 'keep',
      });
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    NotificationCenter.instance.presentSink =
        (e, {bool allowPermissionPrompt = true}) async => false;
  });
  tearDown(() async {
    NotificationCenter.instance.presentSink = oldPresent;
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  tearDownAll(LocalDb.close);
  for (final id in [57, 58, 59]) {
    test(
      'alarm event $id exposes a refused native removal and clears only its own durable key on retry',
      () async {
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        app.device.alarmEpoch = 1617714000;
        app.debugHandleAlarmEvent(id);
        await until(
          () => app.logLines.any(
            (s) => s.contains('clearing the persisted epoch failed'),
          ),
        );
        expect(app.alarmEpoch, isNull);
        expect(app.device.alarmEpoch, isNull);
        expect(store.values['flutter.alarm_epoch'], 1617714000);
        expect(store.values['flutter.authored-unrelated-setting'], 'keep');
        expect(store.removals, 1);
        expect(
          app.logLines.join('\n'),
          contains('authored_alarm_remove_refusal'),
        );
        store.rejecting = false;
        // A later real Disabled reply uses the same shared clear path.
        app.debugHandleAlarmEvent(59);
        await until(() => !store.values.containsKey('flutter.alarm_epoch'));
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(prefs.getInt('alarm_epoch'), isNull);
        expect(store.removals, 2);
        expect(store.values['flutter.authored-unrelated-setting'], 'keep');
        expect(app.alarmEpoch, isNull);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );
  }
}
