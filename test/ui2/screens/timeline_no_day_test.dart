// A repository with no derived day and no named today: the breakdown has no
// day to read and says so with an empty timeline. Authored fake only.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/screens/day_timeline.dart';

import '../../support/test_local_repository.dart';

class _Empty extends TestLocalRepository {
  @override
  Future<List<String>> availableDays() async => const [];
  @override
  Future<Map<String, dynamic>> getToday() async => const {};
}

void main() {
  test('no derived day and no today reads as no day', () async {
    final d = await TimelineData.load(_Empty());
    expect(d.day, isNull);
    expect(d.days, isEmpty);
    expect(d.moments, isEmpty);
  });
}
