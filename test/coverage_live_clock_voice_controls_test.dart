// Scripted active-clock readings drive real interval timers and persisted UI choices.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/run_voice.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_settings_controls_test.dart' show Store;
import 'coverage_live_typed_detail_test.dart' show action, io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class ActiveClock extends WorkoutClock {
  ActiveClock(super.id, super.start);
  int seconds = 0;
  @override
  int activeSeconds([DateTime? until]) => seconds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SharedPreferencesStorePlatform previous;
  late Store store;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('live-clock-voice');
  });
  setUp(() async {
    await resetCoverageStore();
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues({});
    store = Store()..values['flutter.run.voice'] = true;
    SharedPreferencesStorePlatform.instance = store;
    await Prefs.ensureLoaded();
    LiveDraft.clear();
    await LiveDraft.retrySave();
  });
  tearDown(() async {
    LiveDraft.clear();
    await LiveDraft.retrySave();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    );
    SharedPreferencesStorePlatform.instance = previous;
  });
  tearDownAll(LocalDb.close);

  testWidgets(
    'interval HR samples deduplicate a second, retain pauses and announce phase changes before finish',
    (t) async {
      final activity = activityByName('HIIT')!,
          start = DateTime(2021, 4, 6, 12);
      final clock = ActiveClock('synthetic-interval', start)..seconds = 10;
      WorkoutClock.current = clock;
      final draft = LiveDraft.begin(activity, startedAt: start);
      var hr = 120;
      ActivityResult? handed;
      final announcements = <Object?>[], haptics = <MethodCall>[];
      messenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        (m) async {
          announcements.add(m);
          return null;
        },
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        haptics.add(c);
        return null;
      });
      await localizedPage(
        t,
        LiveInterval(
          activity,
          feed: () => LiveFeed(hr: hr),
          onFinish: (r) async {
            handed = r;
            return r;
          },
        ),
      );
      Future<void> tick(int second) async {
        clock.seconds = second;
        await t.pump(const Duration(seconds: 1));
        await io(t);
      }

      await tick(10);
      await tick(10);
      expect(draft.data['interval_hr'], {
        '0': [120, 1],
      });
      hr = 140;
      await tick(11);
      expect(draft.data['interval_hr'], {
        '0': [260, 2],
      });
      draft.setPaused(true);
      hr = 200;
      await tick(11);
      expect(draft.data['interval_hr'], {
        '0': [260, 2],
      });
      draft.setPaused(false);
      hr = 100;
      await tick(45);
      expect(find.text('REST'), findsOneWidget);
      expect(announcements.toString(), contains('Rest'));
      await tick(75);
      expect(find.text('ROUND 2'), findsOneWidget);
      expect(find.text('WORK'), findsOneWidget);
      expect(announcements.toString(), contains('Work'));
      expect(
        haptics.where((c) => c.method == 'HapticFeedback.vibrate'),
        hasLength(2),
      );
      // Missing HR cannot become another zero-valued sample in the next round.
      hr = 0;
      await tick(76);
      expect(draft.data['interval_hr'], {
        '0': [360, 3],
        '1': [100, 1],
      });
      await reveal(t, action('Finish session'));
      await t.tap(action('Finish session'));
      await t.pumpAndSettle();
      await t.tap(find.text('Finish').last);
      await io(t);
      await t.pumpAndSettle();
      expect(handed!.rounds, hasLength(1));
      expect(handed!.rounds.single.avgHr, 120);
      expect(handed!.rounds.single.workSec, 45);
      expect(handed!.rounds.single.restSec, 30);
      expect(LiveDraft.current, isNull);
    },
  );

  testWidgets(
    'live spoken-distance toggle retains its prior choice on refused storage and retries',
    (t) async {
      final activity = activityByName('Running')!;
      LiveDraft.begin(activity);
      await localizedPage(t, LiveMeasured(activity));
      Future<void> toggle(bool on) async {
        final f = action('Voice each kilometre, ${on ? 'on' : 'off'}');
        await reveal(t, f);
        await invokeControl(t, t.widget<Pressable>(f).onTap);
        await io(t);
      }

      store.refuse = 'flutter.run.voice';
      await toggle(true);
      expect(
        find.text('The voice setting could not be saved. Try again.'),
        findsOneWidget,
      );
      expect(runVoiceOn, true);
      expect(action('Voice each kilometre, on'), findsOneWidget);
      store.refuse = null;
      await toggle(true);
      expect(runVoiceOn, false);
      expect(store.values['flutter.run.voice'], false);
      await toggle(false);
      expect(runVoiceOn, true);
      expect(store.values['flutter.run.voice'], true);
    },
  );
}
