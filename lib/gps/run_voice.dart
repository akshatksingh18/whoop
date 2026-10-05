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
  int _spoken;
  double _lastKm = 0, _lastSec = 0, _markSec = 0;
  bool _resume;
  KmVoice({int spoken = 0}) : _spoken = spoken, _resume = spoken > 0;
  int? lastSplitSec;
  int get spokenKm => _spoken;
  Map<String, dynamic> snapshot() => {
    'spoken': _spoken,
    'km': _lastKm,
    'seconds': _lastSec,
    'crossing': _markSec,
    'lastSplit': lastSplitSec,
  };
  static KmVoice restore(Map? saved, {int spoken = 0}) {
    final out = KmVoice(spoken: spoken);
    if (saved != null &&
        saved['km'] is num &&
        saved['seconds'] is num &&
        saved['crossing'] is num) {
      out._spoken = (saved['spoken'] as num?)?.toInt() ?? spoken;
      out._lastKm = (saved['km'] as num).toDouble();
      out._lastSec = (saved['seconds'] as num).toDouble();
      out._markSec = (saved['crossing'] as num).toDouble();
      out.lastSplitSec = (saved['lastSplit'] as num?)?.toInt();
      out._resume = false;
    }
    return out;
  }

  String? update(double? km, int elapsedSec, {bool speak = true}) {
    if (km == null || !km.isFinite || km < 0 || elapsedSec < 0) return null;
    if (_resume) {
      _lastKm = km;
      _lastSec = elapsedSec.toDouble();
      _markSec = _lastSec;
      _resume = false;
      return null;
    }
    if (km <= _lastKm || elapsedSec < _lastSec) return null;
    String? line;
    while (_spoken + 1 <= km) {
      final boundary = _spoken + 1;
      final crossing =
          _lastSec +
          (boundary - _lastKm) / (km - _lastKm) * (elapsedSec - _lastSec);
      final split = (crossing - _markSec).round();
      _spoken = boundary;
      _markSec = crossing;
      if (split > 0) {
        lastSplitSec = split;
        line = kmCue(boundary, split);
        if (speak && runVoiceOn) say(line);
      }
    }
    _lastKm = km;
    _lastSec = elapsedSec.toDouble();
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
