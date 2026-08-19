// The band alarm's two pieces of real logic.
//
// The screen is otherwise a rendering of AppState, and its layout is covered by
// the profile goldens. What is worth a test is the arithmetic that decides WHEN
// the alarm is armed for, and the mapping that decides what the screen is
// allowed to claim about it.

import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/ui2/profile/alarm.dart';

void main() {
  group('nextAt', () {
    test('a time still ahead is today', () {
      final now = DateTime(2026, 8, 21, 5, 0);
      expect(AlarmScreenView.nextAt(6, 30, now), DateTime(2026, 8, 21, 6, 30));
    });

    test('a time already past rolls to tomorrow', () {
      final now = DateTime(2026, 8, 21, 22, 40);
      expect(AlarmScreenView.nextAt(6, 30, now), DateTime(2026, 8, 22, 6, 30));
    });

    test('the same minute is treated as past — never arm for right now', () {
      final now = DateTime(2026, 8, 21, 6, 30);
      expect(AlarmScreenView.nextAt(6, 30, now), DateTime(2026, 8, 22, 6, 30));
    });

    test('month and year rollover is calendar arithmetic', () {
      expect(AlarmScreenView.nextAt(6, 30, DateTime(2026, 8, 31, 23, 0)),
          DateTime(2026, 9, 1, 6, 30));
      expect(AlarmScreenView.nextAt(6, 30, DateTime(2026, 12, 31, 23, 0)),
          DateTime(2027, 1, 1, 6, 30));
    });

    test('the wall-clock time is preserved across a DST boundary', () {
      // 8 March 2026 is a US spring-forward. `add(Duration(days: 1))` from the
      // 7th is 24 ELAPSED hours, which is 07:30 local on the 8th, not 06:30 —
      // an alarm an hour late on the one morning nobody wants one.
      final armed = AlarmScreenView.nextAt(6, 30, DateTime(2026, 3, 7, 23, 0));
      expect(armed.day, 8);
      expect(armed.hour, 6);
      expect(armed.minute, 30);
    });
  });

  group('what the screen may claim', () {
    test('an unconfirmed alarm never says it will fire', () {
      // The band confirms separately (event 56) and might never do so; after a
      // relaunch there is no live confirmation at all, only the epoch on disk.
      for (final s in [AlarmArmState.unknown, AlarmArmState.pending]) {
        final view = AlarmScreenView(state: s, armedAt: DateTime(2026, 8, 22));
        expect(AlarmScreenView.stateLabel(s), isNot(contains('Confirmed')));
        expect(view.state, s);
      }
      expect(AlarmScreenView.stateLabel(AlarmArmState.confirmed),
          contains('Confirmed'));
    });
  });
}
