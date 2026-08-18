// What goes on a clock, and what does not. `dayMoments` and `dayNotes` are
// pure, so the placement rule is testable without a database or a frame.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/ui2/screens/day_timeline.dart';

final int _day = DateTime(2026, 8, 14).millisecondsSinceEpoch ~/ 1000;
int _at(int h, [int m = 0]) => _day + h * 3600 + m * 60;

void main() {
  group('the day timeline places only what carries a clock', () {
    test('everything is ordered by time and nothing else', () {
      final m = dayMoments(
        timeline: {
          'day_start': _day,
          // Deliberately out of order in the input.
          'sessions': [
            {'start_ts': _at(18), 'end_ts': _at(19), 'type': 'football'},
          ],
          'sleep': [
            {'onset_ts': _day - 3600, 'wake_ts': _at(6, 30)},
          ],
          'naps': [
            {'start': _at(14), 'end': _at(14, 40), 'duration_min': 40},
          ],
        },
      );
      expect([for (final x in m) x.at], [_day - 3600, _at(14), _at(18)]);
      // The night that ended this morning started yesterday, and the page says
      // so by putting it first rather than by clipping it to midnight.
      expect(m.first.at, lessThan(_day));
    });

    test('an off-wrist gap under the floor is a dropout, not an event', () {
      final m = dayMoments(
        timeline: {'day_start': _day},
        wear: {
          'segments': [
            {'on': true, 'start': _at(0), 'end': _at(20), 'len_min': 1200},
            {'on': false, 'start': _at(20), 'end': _at(21), 'len_min': 60},
            {'on': false, 'start': _at(22), 'end': _at(22, 3), 'len_min': 3},
          ],
        },
      );
      expect(m, hasLength(1));
      expect(m.single.at, _at(20));
      // A fact about the band, not about the person: no domain colour.
      expect(m.single.color, isNull);
    });

    test('a repeated band event produces one line', () {
      final m = dayMoments(timeline: {
        'day_start': _day,
        'events': [
          {'event_id': 7, 'ts': _at(20)},
          {'event_id': 7, 'ts': _at(20)},
          {'event_id': 7, 'ts': _at(20)},
          // A different id at the same instant is a different fact.
          {'event_id': 8, 'ts': _at(20)},
          // Not in the allow-list: a bond is about the strap, not the day.
          {'event_id': 31, 'ts': _at(20)},
        ],
      });
      expect(m, hasLength(2));
    });

    test('a meal with no time is never placed, and is not lost either', () {
      const timed = FoodEntry(
          id: 'a', date: '2026-08-14', meal: 'Lunch', label: 'Soup', kcal: 300);
      final withTime = FoodEntry(
          id: 'b',
          date: '2026-08-14',
          meal: 'Lunch',
          label: 'Soup',
          atTs: _at(13),
          kcal: 300);
      expect(
        dayMoments(
            timeline: {'day_start': _day}, meals: const [timed]),
        isEmpty,
      );
      expect(
        dayMoments(timeline: {'day_start': _day}, meals: [withTime]),
        hasLength(1),
      );
      expect(dayNotes(meals: const [timed]), hasLength(1));
      expect(dayNotes(meals: [withTime]), isEmpty);
    });

    test('a bare eating occasion carries no energy figure', () {
      final m = dayMoments(timeline: {
        'day_start': _day
      }, meals: [
        FoodEntry(
            id: 'a',
            date: '2026-08-14',
            meal: 'Snack',
            label: 'Apple',
            atTs: _at(16)),
      ]);
      expect(m.single.detail, isNot(contains('kcal')));
    });

    test('a timed journal field lands at its own minute, an untimed one below',
        () {
      final m = dayMoments(
        timeline: {'day_start': _day},
        journal: const {
          'caffeine': JournalMetricValue(3, atMinuteOfDay: 16 * 60 + 40),
          'alcohol': JournalMetricValue(2),
        },
        fields: kJournalFields,
      );
      expect(m, hasLength(1));
      expect(m.single.at, _at(16, 40));
      expect(
        dayNotes(
          journal: const {
            'caffeine': JournalMetricValue(3, atMinuteOfDay: 100),
            'alcohol': JournalMetricValue(2),
          },
          fields: kJournalFields,
        ),
        hasLength(1),
      );
    });

    test('a journal row is read off tags_json, not tags', () {
      final n = dayNotes(journalRows: const [
        {'date': '2026-08-14', 'tags_json': '["travel","late meal"]', 'note': ''},
      ]);
      expect(n.single.detail, 'travel · late meal');
    });
  });
}
