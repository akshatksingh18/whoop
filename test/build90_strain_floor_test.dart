// Build 90: the Build 89 day-strain floor must reach the STORED strain.
//
// The floor ("a day is never less strained than the workouts inside it") was
// applied to the wake features after `_applyWakeDayFeatures` had already
// copied strain into the day's scalars, so `scalars['strain']` — what
// metric_series, Today and Trends read — kept the unfloored 0.0 beside a
// finished walk. These tests read the scalar, not only the wake map.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/substrate.dart';

const _profile = Profile(
  ageYears: 34,
  weightKg: 72,
  heightCm: 178,
  sex: 'm',
  restingHrManual: 55,
);

const _dayStart = 1767225600;
const _sleepOffset = _dayStart + 2 * 3600;
const _dayEnd = _dayStart + 10 * 3600;

/// Two hours asleep, then eight quiet waking hours just above resting: a day
/// whose own strain nets to about zero against the quiet baseline.
Substrate _quietDay() {
  final ts = <int>[], hr = <int>[];
  final ax = <double>[], ay = <double>[], az = <double>[];
  for (var t = _dayStart; t < _dayEnd; t++) {
    ts.add(t);
    hr.add(t < _sleepOffset ? 52 : 60 + (t ~/ 60) % 3);
    ax.add(0.01 * ((t % 7) - 3));
    ay.add(0.01 * ((t % 5) - 2));
    az.add(1.0);
  }
  final n = ts.length;
  return Substrate(
    tsSec: ts,
    hr: hr,
    rrTsMs: const [],
    rrMs: const [],
    ax: ax,
    ay: ay,
    az: az,
    spo2Red: List<int>.filled(n, 0),
    spo2Ir: List<int>.filled(n, 0),
    skinTemp: List<int>.filled(n, 0),
    skinContact: List<int>.filled(n, 0),
    deviceFamily: 'gen4',
  );
}

({Map<String, dynamic> wake, Map<String, dynamic> scalars}) _run(
  List<Map<String, dynamic>> sessions,
) {
  final scalars = <String, dynamic>{};
  final daySub = _quietDay();
  final wake = DerivationEngine.applyDayActivity(
    bundle: <String, dynamic>{},
    scalars: scalars,
    daySub: daySub,
    profile: _profile,
    sleepOnsetSec: _dayStart,
    sleepOffsetSec: _sleepOffset,
    dayStartSec: daySub.tsSec.first,
    dayCalendarEndSec: daySub.tsSec.last + 1,
    dataNowSec: daySub.tsSec.last + 1,
    restingHr: 55,
    sessions: sessions,
  );
  return (wake: wake, scalars: scalars);
}

void main() {
  test('the quiet day alone has a strain below the walk inside it', () {
    final out = _run(const []);
    final s = (out.scalars['strain'] as num?)?.toDouble();
    expect(s, isNotNull, reason: 'the fixture must produce a day strain');
    expect(s!, lessThan(5.0));
  });

  test('a finished walk floors the STORED day strain, not only the wake map',
      () {
    final out = _run([
      {'status': 'done', 'strain': 5.0, 'type': 'walking'},
    ]);
    final stored = (out.scalars['strain'] as num).toDouble();
    expect(stored, closeTo(5.0, 1e-9));
    expect((out.wake['strain'] as num).toDouble(), closeTo(stored, 1e-9));
    expect(out.wake['strain_session_floor'], isTrue);
  });

  test('two workouts add as net TRIMP, not as strain', () {
    final out = _run([
      {'status': 'done', 'strain': 4.0, 'type': 'walking'},
      {'status': 'done', 'strain': 4.0, 'type': 'walking'},
    ]);
    final expected = ana.strainFromNetTrimp(2 * ana.netTrimpFromStrain(4.0));
    expect((out.scalars['strain'] as num).toDouble(), closeTo(expected, 1e-9));
    expect(expected, lessThan(8.0));
  });

  test('an unfinished session never raises the day', () {
    final base = _run(const []).scalars['strain'];
    final out = _run([
      {'status': 'live', 'strain': 9.0, 'type': 'walking'},
    ]);
    expect(out.scalars['strain'], base);
  });
}
