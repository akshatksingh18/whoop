// The day a detail screen shows, and the day a chart point stands for.
//
// Both are arithmetic nobody sees until it is wrong: `pickDay` decides whether
// a screen honours the day it was opened with, and the slot→date walk is what
// turns "the fourteenth dot on a 30-day line" into a day you can open. Get the
// second one wrong by one and the tap opens the wrong night.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// The same walk `MetricDetail` does from a dense slot to a calendar day.
String dayOfSlot(int i, int len) {
  final n = DateTime.now();
  return dayLabelOf(DateTime(n.year, n.month, n.day - (len - 1 - i)));
}

void main() {
  group('pickDay', () {
    const days = ['2026-08-16', '2026-08-15', '2026-08-13'];

    test('no day asked for behaves exactly as the old inline resolve did', () {
      // The screen's own answer, when that day exists.
      expect(pickDay(days, null, '2026-08-15'), '2026-08-15');
      // …and the newest day when it does not.
      expect(pickDay(days, null, '2026-08-14'), '2026-08-16');
      expect(pickDay(days, null, null), '2026-08-16');
    });

    test('a day that exists is honoured over the screen’s own', () {
      expect(pickDay(days, '2026-08-13', '2026-08-16'), '2026-08-13');
    });

    test('a day with no record falls back rather than loading a hole', () {
      expect(pickDay(days, '2026-08-14', '2026-08-15'), '2026-08-16');
    });

    test('nothing derived at all: there is nothing to fall back to', () {
      expect(pickDay(const [], '2026-08-14', null), '2026-08-14');
      expect(pickDay(const [], null, null), isNull);
    });
  });

  group('a dense slot is a calendar day', () {
    test('the last slot is today and slot 0 is len-1 days behind it', () {
      expect(dayOfSlot(29, 30), todayLabel());
      final n = DateTime.now();
      expect(dayOfSlot(0, 30), dayLabelOf(DateTime(n.year, n.month, n.day - 29)));
    });

    test('every slot in a window is a distinct, consecutive day', () {
      final seen = {for (var i = 0; i < 40; i++) dayOfSlot(i, 40)};
      expect(seen, hasLength(40));
    });
  });

  group('DayNav', () {
    Widget frame(Widget child) => MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: child),
        );

    testWidgets('one day is nowhere to go, so it renders nothing',
        (tester) async {
      await tester.pumpWidget(frame(DayNav(
        day: '2026-08-16',
        days: const ['2026-08-16'],
        onDay: (_) {},
      )));
      expect(find.byType(Pressable), findsNothing);
    });

    testWidgets('the arrows walk the list, and the ends are dead',
        (tester) async {
      final picked = <String>[];
      // Newest first, which is what `availableDays()` returns.
      const days = ['2026-08-16', '2026-08-15', '2026-08-13'];
      await tester.pumpWidget(frame(DayNav(
        day: '2026-08-16',
        days: days,
        onDay: picked.add,
      )));

      // Newest day: forward is dead, back goes to the day before it — never to
      // 2026-08-14, which this install has no record of.
      await tester.tap(find.bySemanticsLabel('Next day'));
      expect(picked, isEmpty);
      await tester.tap(find.bySemanticsLabel('Previous day'));
      expect(picked, ['2026-08-15']);

      await tester.pumpWidget(frame(DayNav(
        day: '2026-08-13',
        days: days,
        onDay: picked.add,
      )));
      await tester.tap(find.bySemanticsLabel('Previous day'));
      expect(picked, ['2026-08-15'], reason: 'the oldest day has no day before');
      await tester.tap(find.bySemanticsLabel('Next day'));
      expect(picked.last, '2026-08-15');
    });

    testWidgets('a day off the list still steers — it does not strand you',
        (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(frame(DayNav(
        day: '1999-01-01',
        days: const ['2026-08-16', '2026-08-15'],
        onDay: picked.add,
      )));
      await tester.tap(find.bySemanticsLabel('Previous day'));
      expect(picked, ['2026-08-16']);
    });
  });
}
