// CV-04a — the band's own HR-validity flag reaches Substrate, and gen4's NULL
// means ABSENT, not false.
//
// This is the whole risk of the change. `hr_valid` is a gen5 column: gen4's R24
// has no such field, so every gen4 second is NULL, and a `?? 0` anywhere on the
// path would tell every downstream reader that a whole generation's beats had
// been REJECTED BY THE BAND. Two gates enforce it — the -1 array sentinel and
// `device_family`, because a row with no device stamp cannot be shown to have
// come from a band that reports the flag at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/substrate.dart';

Substrate _sub({
  required String? family,
  required List<int> hrValid,
}) => Substrate(
  tsSec: [for (var i = 0; i < hrValid.length; i++) 1000 + i],
  hr: List<int>.filled(hrValid.length, 60),
  rrTsMs: const [],
  rrMs: const [],
  ax: List<double>.filled(hrValid.length, 0.1),
  ay: List<double>.filled(hrValid.length, 0.2),
  az: List<double>.filled(hrValid.length, 0.95),
  spo2Red: List<int>.filled(hrValid.length, 0),
  spo2Ir: List<int>.filled(hrValid.length, 0),
  skinTemp: List<int>.filled(hrValid.length, 0),
  skinContact: List<int>.filled(hrValid.length, 0),
  hrValid: hrValid,
  deviceFamily: family,
);

void main() {
  test('gen5 reports the flag; 0 is a real "not trustworthy"', () {
    final s = _sub(family: 'gen5', hrValid: const [1, 0, 1]);
    expect(s.hrValidAt(0), isTrue);
    expect(s.hrValidAt(1), isFalse); // the band's own verdict, not an absence
    expect(s.hrValidAt(2), isTrue);
  });

  test('gen4 is ABSENT, never false', () {
    final s = _sub(family: 'gen4', hrValid: const [-1, -1]);
    expect(s.hrValidAt(0), isNull);
    expect(s.hrValidAt(1), isNull);
  });

  test('unknown provenance refuses even when the array carries values', () {
    // A pre-schema-41 row, an import or a raw replay has no device stamp. The
    // column belongs to gen5, so an unstamped substrate cannot claim it.
    final s = _sub(family: null, hrValid: const [1, 1]);
    expect(s.hrValidAt(0), isNull);
  });

  test('an out-of-range index is absent, not a crash and not false', () {
    final s = _sub(family: 'gen5', hrValid: const [1]);
    expect(s.hrValidAt(5), isNull);
    expect(s.hrValidAt(-1), isNull);
  });

  test('slicing and the isolate round-trip both keep it 1:1 with the seconds',
      () {
    final s = _sub(family: 'gen5', hrValid: const [1, 0, 1, 0, 1]);
    final cut = s.slice(1001, 1004);
    expect(cut.length, 3);
    expect(cut.hrValidAt(0), isFalse);
    expect(cut.hrValidAt(2), isFalse);

    final back = Substrate.fromJson(s.toJson());
    expect(back.hrValid, s.hrValid);
    expect(back.hrValidAt(1), isFalse);
  });

  test('a payload written before the array existed reads as absent, not false',
      () {
    final json = _sub(family: 'gen5', hrValid: const [1, 1, 1]).toJson()
      ..remove('hr_valid');
    final back = Substrate.fromJson(json);
    expect(back.length, 3);
    // -1 filled, not 0 — the same discipline stepCount uses.
    expect(back.hrValidAt(0), isNull);
  });
}
