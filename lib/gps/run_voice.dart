// Spoken updates during a run or walk: at every whole kilometre (or mile,
// when Settings → Units → Distance says miles), the distance and that
// split's pace, so the phone does not have to be held up
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
Future<void> setRunVoiceOn(bool on) => Prefs.saveValues({kRunVoicePref: on});

/// Metres in a mile.
const double kVoiceMileMeters = 1609.344;

/// What to say at unit [n] after a split of [splitSec] seconds, e.g.
/// "3 kilometres. Last kilometre 6 minutes 41." or "2 miles. Last mile 9
/// minutes 30."
String kmCue(int n, int splitSec, {bool miles = false}) {
  final m = splitSec ~/ 60, s = splitSec % 60;
  final pace = s == 0 ? '$m minutes' : '$m minutes $s';
  final one = miles ? 'mile' : 'kilometre';
  return '$n ${n == 1 ? one : '${one}s'}. Last $one $pace.';
}

/// The distance unit the voice uses, from Settings → Units → Distance.
bool get voiceInMiles => Prefs.getString('units.distance', 'km') == 'mi';

/// Tracks the run's distance and speaks once per whole kilometre (or mile)
/// crossed. A session keeps the unit it started with.
class KmVoice {
  int _spoken;
  double _lastKm = 0, _lastSec = 0, _markSec = 0;
  bool _resume;
  final bool miles;
  KmVoice({int spoken = 0, this.miles = false})
    : _spoken = spoken,
      _resume = spoken > 0;
  int? lastSplitSec;

  /// Whole units spoken so far (kilometres, or miles).
  int get spokenKm => _spoken;
  Map<String, dynamic> snapshot() => {
    'spoken': _spoken,
    'km': _lastKm,
    'seconds': _lastSec,
    'crossing': _markSec,
    'lastSplit': lastSplitSec,
    if (miles) 'mi': true,
  };
  static KmVoice restore(Map? saved, {int spoken = 0, bool miles = false}) {
    final out = KmVoice(
      spoken: spoken,
      miles: saved == null ? miles : saved['mi'] == true,
    );
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

  String? update(double? distanceKm, int elapsedSec, {bool speak = true}) {
    if (distanceKm == null ||
        !distanceKm.isFinite ||
        distanceKm < 0 ||
        elapsedSec < 0) {
      return null;
    }
    // In the session's own unit from here on.
    final km = miles ? distanceKm * 1000 / kVoiceMileMeters : distanceKm;
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
        line = kmCue(boundary, split, miles: miles);
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
