// Finding is an active immutable value. Operator dispatch/hash collection
// behavior is not inferred from zero direct inbound static-call metadata.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/findings.dart';

void main() {
  for (final kind in FindingKind.values) {
    test('$kind equality retains exact kind,source day and direction', () {
      final direction = kind == FindingKind.rhrShift ? true : null;
      final first = Finding(kind, '2021-04-06', risen: direction);
      final copy = Finding(kind, '2021-04-06', risen: direction);
      expect(identical(first, copy), false);
      expect(first, copy);
      expect(first.hashCode, copy.hashCode);
      expect(first == Finding(kind, '2021-04-07', risen: direction), false);
      final otherKind =
          FindingKind.values[(kind.index + 1) % FindingKind.values.length];
      expect(
        first == Finding(otherKind, '2021-04-06', risen: direction),
        false,
      );
      final Object unrelated = 'Authored unrelated value';
      expect(first == unrelated, false);
      expect(copy.date, '2021-04-06');
    });
  }
  test(
    'hash-based membership deduplicates only the same source-day and direction',
    () {
      const kind = FindingKind.rhrShift, day = '2021-04-06';
      final values = <Finding>{
        Finding(kind, day, risen: true),
        Finding(kind, day, risen: true),
        Finding(kind, day, risen: false),
        Finding(kind, day),
        Finding(kind, '2021-04-07', risen: true),
      };
      expect(values, hasLength(4));
      expect(values.contains(Finding(kind, day, risen: true)), true);
      expect(values.contains(Finding(kind, day, risen: false)), true);
      expect(values.contains(Finding(kind, day)), true);
      expect(values.contains(Finding(kind, '2021-04-08', risen: true)), false);
    },
  );
}
