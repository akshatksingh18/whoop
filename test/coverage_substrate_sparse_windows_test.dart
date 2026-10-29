// RR observations can exist between sparse 1 Hz samples. Exercise the real
// half-open slicing path without manufacturing HR, movement or optical values.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/substrate.dart';

void main() {
  Substrate source() => Substrate(
    tsSec: [100, 200],
    hr: [60, 70],
    ax: [0, 0],
    ay: [0, 0],
    az: [1, 1],
    spo2Red: [null, null],
    spo2Ir: [null, null],
    skinTemp: [null, null],
    skinContact: [null, null],
    rrTsMs: [149999, 150000, 159999, 160000],
    rrMs: [700, 710, 720, 730],
    deviceFamily: 'gen4',
  );
  test('a 1 Hz gap keeps only RR endpoints inside the half-open window', () {
    final original = source();
    final gap = original.slice(150, 160);
    expect(gap.isEmpty, true);
    expect(gap.firstTs, isNull);
    expect(gap.lastTs, isNull);
    expect(gap.hr, isEmpty);
    expect(gap.ax, isEmpty);
    expect(gap.spo2Red, isEmpty);
    expect(gap.deviceFamily, 'gen4');
    expect(gap.rrTsMs, [150000, 159999]);
    expect(gap.rrMs, [710, 720]);
    expect(original.rrMs, [700, 710, 720, 730]);
    expect(original.firstTs, 100);
    expect(original.lastTs, 200);
  });
  test('an empty gap does not substitute one of its neighboring samples', () {
    final gap = source().slice(170, 180);
    expect(gap.length, 0);
    expect(gap.rrMs, isEmpty);
    expect(gap.rrTsMs, isEmpty);
    expect(gap.deviceFamily, 'gen4');
  });
  test(
    'the next record and RR endpoint enter only when the window includes them',
    () {
      final slice = source().slice(160, 201);
      expect(slice.tsSec, [200]);
      expect(slice.hr, [70]);
      expect(slice.rrTsMs, [160000]);
      expect(slice.rrMs, [730]);
      expect(slice.spo2Ir, [null]);
      expect(slice.deviceFamily, 'gen4');
    },
  );
}
