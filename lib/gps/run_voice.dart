// Spoken updates during a run or walk: at every whole kilometre, the
// distance and that kilometre's pace, so the phone does not have to be held up
// to read it. Uses the iPhone's built-in voice (`SpeechBridge` in
// AppDelegate.swift); music is ducked, not stopped. On by default, switchable
// on the live screen.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/prefs.dart';

const MethodChannel _channel = MethodChannel('openstrap/speech');

/// The preference key for the live-screen switch.
const String kRunVoicePref = 'run.voice';

bool get runVoiceOn => Prefs.getBool(kRunVoicePref, true);
set runVoiceOn(bool v) => Prefs.setBool(kRunVoicePref, v);

/// What to say at kilometre [km] after a split of [splitSec] seconds, e.g.
/// "3 kilometres. Last kilometre 6 minutes 41."
String kmCue(int km, int splitSec) {
  final m = splitSec ~/ 60, s = splitSec % 60;
  final pace = s == 0 ? '$m minutes' : '$m minutes $s';
  return '$km ${km == 1 ? 'kilometre' : 'kilometres'}. Last kilometre $pace.';
}

/// Tracks the run's distance and speaks once per whole kilometre crossed.
class KmVoice {
  int _spoken = 0;
  int _lastMarkSec = 0;
  bool _primed = false;

  /// Feed the current [km] and [elapsedSec]; returns the line spoken, if any.
  ///
  /// The first reading only sets the starting point: a screen reopened
  /// mid-run (after a minimise or a relaunch) must not announce a kilometre it
  /// did not see begin, with a "split" that is really the whole run so far.
  String? update(double? km, int elapsedSec, {bool speak = true}) {
    if (km == null) return null;
    if (!_primed) {
      _primed = true;
      _spoken = km.floor();
      // A fresh run's first fix lands a few seconds in; its first kilometre
      // still started at 0:00.
      _lastMarkSec = km < 0.2 ? 0 : elapsedSec;
      return null;
    }
    if (km < _spoken + 1) return null;
    final whole = km.floor();
    final split = elapsedSec - _lastMarkSec;
    _spoken = whole;
    _lastMarkSec = elapsedSec;
    if (split <= 0) return null;
    final line = kmCue(whole, split);
    if (speak && runVoiceOn) say(line);
    return line;
  }
}

/// Speak [text]. Silent off iOS and on any platform failure.
Future<void> say(String text) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await _channel.invokeMethod<bool>('say', {'text': text});
  } catch (_) {
    // A missed cue is not worth interrupting a run for.
  }
}
