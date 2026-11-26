// Shared production activity projection;missing body/sensor inputs stay absent.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/onehz_pipeline.dart' show needInputNote;
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/substrate.dart';

const _start = 1617714000;
Substrate _measured(
  String? family, {
  bool accel = true,
  bool heart = true,
  int n = 12 * 60,
}) {
  return Substrate(
    tsSec: [for (var i = 0; i < n; i++) _start + i],
    hr: [for (var i = 0; i < n; i++) heart ? 120 + i % 3 : 0],
    rrTsMs: const [],
    rrMs: const [],
    ax: [for (var i = 0; i < n; i++) accel ? .01 * (i % 7 - 3) : double.nan],
    ay: [for (var i = 0; i < n; i++) accel ? .01 * (i % 5 - 2) : double.nan],
    az: List.filled(n, accel ? 1.0 : double.nan),
    spo2Red: List<int?>.filled(n, null),
    spo2Ir: List<int?>.filled(n, null),
    skinTemp: List<int?>.filled(n, null),
    skinContact: List<int?>.filled(n, null),
    deviceFamily: family,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fullProfile = Profile.fromMap({
    'age': 30,
    'weight_kg': 70.25,
    'height_cm': 170.5,
    'sex': 'f',
  });
  Map<String, dynamic> project(
    Substrate sub, {
    Map<String, dynamic>? bundle,
    double? restingHr,
    List<List<int>> stepSpans = const [],
  }) => DerivationEngine.applyDayActivity(
    bundle: bundle ?? <String, dynamic>{},
    scalars: <String, dynamic>{},
    daySub: sub,
    profile: fullProfile,
    sleepOnsetSec: 0,
    sleepOffsetSec: 0,
    dayStartSec: _start,
    dayCalendarEndSec: _start + 24 * 3600,
    dataNowSec: _start + sub.length,
    restingHr: restingHr,
    stepSpans: stepSpans,
  );

  test('a day too short to smooth reports its raw peak and trough', () {
    final wake = project(_measured('gen5', n: 3), restingHr: 60);
    final stats = wake['hr_stats'] as Map;
    expect(stats['max'], 122);
    expect(stats['min'], 120);
  });

  test('measured walking cadence below the flex gate is priced and named', () {
    final bundle = <String, dynamic>{};
    // 120 spm over the first ten minutes; HR 120–122 sits under the flex gate
    // of a 100 bpm resting reference, so only the cadence term can price it.
    project(
      _measured('gen5'),
      bundle: bundle,
      restingHr: 100,
      stepSpans: [
        [_start, _start + 600, 1200],
      ],
    );
    final tdee = bundle['calories_total'] as Map;
    expect(tdee['inputs_used'], contains('live_coverage_pedometer'));
    expect(tdee['note'], contains('CADENCE-Adults'));
  });
  for (final family in ['gen4', 'gen5']) {
    for (final missing in [
      'age',
      'weight_kg',
      'sex',
      'height_cm',
      'all',
      'none',
    ]) {
      test(
        '$family shared wake projection keeps missing $missing explicit without body defaults',
        () {
          final fields = <String, dynamic>{
            'age': 30,
            'weight_kg': 70.25,
            'height_cm': 170.5,
            'sex': 'f',
          };
          if (missing == 'all') {
            fields.clear();
          } else if (missing != 'none') {
            fields.remove(missing);
          }
          final before = Map<String, dynamic>.of(fields);
          final sub = _measured(family);
          final ts = List<int>.of(sub.tsSec), hr = List<int>.of(sub.hr);
          final scalars = <String, dynamic>{'authored_unrelated': 123};
          final bundle = <String, dynamic>{};
          final wake = DerivationEngine.applyDayActivity(
            bundle: bundle,
            scalars: scalars,
            daySub: sub,
            profile: Profile.fromMap(fields),
            sleepOnsetSec: 0,
            sleepOffsetSec: 0,
            dayStartSec: _start,
            dayCalendarEndSec: _start + 24 * 3600,
            dataNowSec: _start + 12 * 60,
            // This measured waking fragment has no main-night RHR or manual RHR.
            restingHr: null,
          );
          expect(wake['calories'], isNull);
          expect(wake['calories_total'], isNull);
          expect(scalars['calories'], isNull);
          expect(scalars['calories_total'], isNull);
          final notes = wake['absent_notes'] as Map;
          if (missing != 'none') {
            final required = missing == 'all' ? 'age' : missing;
            expect(notes['calories'], needInputNote(required));
            expect(notes['calories_total'], needInputNote(required));
            expect(
              (bundle['absent_notes'] as Map)['calories'],
              notes['calories'],
            );
          } else {
            expect(
              notes['calories'],
              isNotEmpty,
              reason: 'No nocturnal reference cannot become a measured zero',
            );
          }
          expect(wake['strain'], isNull);
          expect(
            wake['strain_absent'],
            needInputNote(
              missing == 'age' || missing == 'all' ? 'age' : 'resting_hr',
            ),
          );
          expect(fields, before);
          expect(sub.tsSec, ts);
          expect(sub.hr, hr);
          expect(scalars['authored_unrelated'], 123);
        },
      );
    }
    for (final missing in ['accel', 'heart']) {
      test(
        '$family shared day projection preserves absent $missing and original aligned rows',
        () {
          final sub = _measured(
            family,
            accel: missing != 'accel',
            heart: missing != 'heart',
          );
          final profile = Profile.fromMap({
            'age': 30,
            'weight_kg': 70.25,
            'height_cm': 170.5,
            'sex': 'f',
          });
          final scalars = <String, dynamic>{'authored_unrelated': 123},
              bundle = <String, dynamic>{};
          final wake = DerivationEngine.applyDayActivity(
            bundle: bundle,
            scalars: scalars,
            daySub: sub,
            profile: profile,
            sleepOnsetSec: 0,
            sleepOffsetSec: 0,
            dayStartSec: _start,
            dayCalendarEndSec: _start + 24 * 3600,
            dataNowSec: _start + 12 * 60,
          );
          expect(wake['calories'], isNull);
          expect(wake['calories_total'], isNull);
          final reason = needInputNote(
            missing == 'accel' ? 'accel_1hz' : 'wake_hr',
          );
          expect((wake['absent_notes'] as Map)['calories'], reason);
          expect((wake['absent_notes'] as Map)['calories_total'], reason);
          expect(sub.length, 720);
          expect(sub.ax.length, sub.length);
          expect(sub.hr.length, sub.length);
          if (missing == 'accel') {
            expect(sub.ax.every((v) => v.isNaN), true);
          } else {
            expect(sub.hr.every((v) => v == 0), true);
          }
          expect(scalars['authored_unrelated'], 123);
        },
      );
    }
  }
}
