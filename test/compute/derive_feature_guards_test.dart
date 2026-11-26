// Each optional day feature that throws costs only itself: it is named in the
// log and its fallback answers. The failures are authored (a read-only bundle,
// a short accelerometer column), not a recording.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/nap_edits.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/day_label.dart';

const _day = '2021-04-06';

Substrate _day120({bool accel = true}) {
  final start = localDayStartSec(_day)! + 14 * 3600;
  const n = 120;
  final g = accel ? List<double>.filled(n, 0.0) : <double>[];
  return Substrate(
    tsSec: [for (var i = 0; i < n; i++) start + i],
    hr: List<int>.filled(n, 60),
    rrTsMs: const [],
    rrMs: const [],
    ax: g,
    ay: g,
    az: accel ? List<double>.filled(n, 1.0) : <double>[],
    spo2Red: List<int?>.filled(n, null),
    spo2Ir: List<int?>.filled(n, null),
    skinTemp: List<int?>.filled(n, null),
    skinContact: List<int?>.filled(n, 1),
  );
}

void main() {
  final printed = <String>[];
  late DebugPrintCallback original;
  setUp(() {
    printed.clear();
    original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
  });
  tearDown(() => debugPrint = original);

  test('steps/energy and wrist orientation fail closed on their own', () {
    final readOnly = Map<String, dynamic>.unmodifiable(<String, dynamic>{});
    DerivationEngine.stepsAndEnergy(readOnly, _day120());
    DerivationEngine.wristOrientation(readOnly, _day120());
    expect(readOnly, isEmpty);
    expect(
      printed
          .where((m) => m.contains('FAILED/skipped'))
          .map((m) => m.split(' FAILED').first),
      ['[derive] steps/energy', '[derive] wrist-orientation'],
      reason: printed.join(' | '),
    );
  });

  test('a failed nap detection still publishes the logged nap', () {
    final s = _day120(accel: false);
    final bundle = <String, dynamic>{};
    final rows = DerivationEngine.attachNaps(bundle, s, [
      NapEdit(
        kind: NapEditKind.added,
        startSec: s.tsSec.first,
        endSec: s.tsSec.first + 1800,
      ),
    ]);
    expect(rows, hasLength(1));
    expect(
      (bundle['naps'] as Map)['note'],
      'nap detection failed for this day — showing what you logged',
    );
    expect(printed.single, startsWith('[derive] naps FAILED/skipped: '));
  });

  test('a short motion column costs only the workout pass', () {
    DerivationEngine.workouts(_day120(accel: false), const [], _day);
    expect(
      printed.single,
      startsWith('[derive] auto-workout/HRR FAILED/skipped: '),
      reason: printed.join(' | '),
    );
  });
}
