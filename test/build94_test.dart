// Build 94: Claude's end-to-end audit of Build 93 (register in
// build/research-local/claude-e2e-audit-build93.md). Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';

void main() {
  group('SL01: a corrected bedtime stays on the detected night', () {
    test('after midnight, from a detected 11:30 PM', () {
      final (start, end) = correctedSleepWindow(
        DateTime(2026, 10, 17, 23, 30),
        const TimeOfDay(hour: 0, minute: 30),
        const TimeOfDay(hour: 7, minute: 0),
      );
      expect(start, DateTime(2026, 10, 18, 0, 30));
      expect(end, DateTime(2026, 10, 18, 7, 0));
    });

    test('before midnight, from a detected 12:20 AM', () {
      final (start, end) = correctedSleepWindow(
        DateTime(2026, 10, 18, 0, 20),
        const TimeOfDay(hour: 23, minute: 50),
        const TimeOfDay(hour: 7, minute: 0),
      );
      expect(start, DateTime(2026, 10, 17, 23, 50));
      expect(end, DateTime(2026, 10, 18, 7, 0));
    });

    test('same side of midnight is unchanged', () {
      final (start, end) = correctedSleepWindow(
        DateTime(2026, 10, 17, 23, 30),
        const TimeOfDay(hour: 22, minute: 45),
        const TimeOfDay(hour: 6, minute: 30),
      );
      expect(start, DateTime(2026, 10, 17, 22, 45));
      expect(end, DateTime(2026, 10, 18, 6, 30));
    });
  });

  test('one 12-hour clock format', () {
    expect(formatClock(DateTime(2026, 10, 18, 0, 5)), '12:05 AM');
    expect(formatClock(DateTime(2026, 10, 18, 12, 0)), '12:00 PM');
    expect(formatClock(DateTime(2026, 10, 18, 19, 5)), '7:05 PM');
    expect(formatMinuteOfDay(14 * 60), '2:00 PM');
  });
}
