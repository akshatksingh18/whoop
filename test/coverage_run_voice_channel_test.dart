// Real cue progression and restore state; authored native speech responses only.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/gps/run_voice.dart';
import 'package:whoop_companion/state/prefs.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/speech');
  late List<MethodCall> calls;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls = [];
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> drain() => Future<void>.delayed(Duration.zero);

  for (final miles in [false, true]) {
    for (final refusal in ['none', 'plugin', 'platform']) {
      test(
        'COV-59 ${miles ? 'mile' : 'km'} cues retain progression after $refusal speech response',
        () async {
          var refuse = refusal != 'none';
          binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
            call,
          ) async {
            calls.add(call);
            if (refuse && refusal == 'plugin') {
              throw MissingPluginException();
            }
            if (refuse) {
              throw PlatformException(code: 'authored-speech-refusal');
            }
            return true;
          });
          final voice = KmVoice(miles: miles);
          final unitKm = miles ? kVoiceMileMeters / 1000 : 1.0;
          final first = voice.update(unitKm, 300);
          await drain();
          expect(first, kmCue(1, 300, miles: miles));
          expect(voice.spokenKm, 1);
          expect(voice.lastSplitSec, 300);
          expect(calls.single.method, 'say');
          expect(calls.single.arguments, {'text': first});

          final saved = voice.snapshot();
          final restored = KmVoice.restore(saved);
          expect(restored.snapshot(), saved);
          expect(restored.update(unitKm, 301), isNull);
          await drain();
          expect(calls, hasLength(1), reason: 'Restore cannot replay a cue');
          refuse = false;
          final next = restored.update(unitKm * 2, 600);
          await drain();
          expect(next, kmCue(2, 300, miles: miles));
          expect(restored.spokenKm, 2);
          expect(restored.lastSplitSec, 300);
          expect(calls, hasLength(2));
          expect(calls.last.arguments, {'text': next});
          expect(runVoiceOn, true);
        },
      );
    }
  }

  test(
    'COV-59 muted cues advance without replay when voice is re-enabled',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      await setRunVoiceOn(false);
      final voice = KmVoice();
      expect(voice.update(2, 600), kmCue(2, 300));
      await drain();
      expect(calls, isEmpty);
      expect(voice.spokenKm, 2);
      await setRunVoiceOn(true);
      expect(voice.update(3, 900), kmCue(3, 300));
      await drain();
      expect(calls.single.arguments, {'text': kmCue(3, 300)});
    },
  );

  test(
    'COV-59 unsupported speech host preserves cue state without a native call',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      final voice = KmVoice();
      expect(voice.update(1, 300), kmCue(1, 300));
      await drain();
      expect(calls, isEmpty);
      expect(voice.spokenKm, 1);
      expect(voice.lastSplitSec, 300);
    },
  );

  test(
    'COV-59 invalid movement cannot replace the last accepted cue snapshot',
    () async {
      final voice = KmVoice();
      expect(voice.update(.5, 150, speak: false), isNull);
      final before = voice.snapshot();
      for (final distance in [null, double.nan, double.infinity, -1.0]) {
        expect(voice.update(distance, 151), isNull);
        expect(voice.snapshot(), before);
      }
      expect(voice.update(.6, -1), isNull);
      expect(voice.update(.6, 149), isNull);
      expect(voice.snapshot(), before);
      expect(voice.update(1, 300, speak: false), kmCue(1, 300));
    },
  );
}
