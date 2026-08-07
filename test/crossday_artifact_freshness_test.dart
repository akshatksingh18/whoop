// HONESTY REGRESSION — a day-relative stamp must not outlive its day.
//
// `_refreshCrossDayInputArtifact` marks the most recent record `is_today: true`
// so today-scoped reads (`_todayNum`) can tell "today abstained" from "today has
// no row yet". That stamp is a fact ABOUT A DAY stored as a bare boolean, and it
// is written into the DURABLE `crossday_input` baseline row.
//
// `_crossDayInputDays()` prefers that cached row whenever it parses. So a cache
// written yesterday hands back a series whose last record still claims
// `is_today: true` — and `_todayNum` then reports YESTERDAY's strain and nap
// minutes as today's, landing them inside `need_sec`. That is precisely the
// imputation the stamp exists to prevent (AGENTS §3.3), re-entering through the
// cache rather than through `_lastNum`.
//
// Today the four `_runCrossDay` call sites each refresh the artifact immediately
// beforehand, so the stale read is not reachable in practice. That is an
// unenforced ordering coincidence, not a guarantee: one new caller, or one early
// return inside `_refreshBaselines`, makes it live and silent. The envelope now
// carries the day it was built for, and this predicate is the only thing allowed
// to declare a cached artifact reusable.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';

void main() {
  Map<String, dynamic> envelope(String? builtFor) => <String, dynamic>{
        'algo_version': 56,
        'built_for_day': ?builtFor,
        'days': [
          {'date': '2024-03-01', 'strain': 14.0},
          {'date': '2024-03-02', 'strain': 18.0, 'is_today': true},
        ],
      };

  group('crossDayArtifactUsableToday', () {
    test('an artifact built today is reusable', () {
      expect(
        DerivationEngine.crossDayArtifactUsableToday(envelope('2024-03-02'), '2024-03-02'),
        isTrue,
      );
    });

    test("an artifact built YESTERDAY is not reusable today", () {
      // The whole bug: its last record still says `is_today: true`, and that
      // record is yesterday's.
      expect(
        DerivationEngine.crossDayArtifactUsableToday(envelope('2024-03-02'), '2024-03-03'),
        isFalse,
        reason: "a stamp that says 'today' must not be believed on a later "
            "day — that is how yesterday's strain becomes tonight's sleep need",
      );
    });

    test('an artifact with no day stamped is not reusable', () {
      // Written before `built_for_day` existed. It cannot be SHOWN to be fresh,
      // so it is rebuilt rather than assumed fresh.
      expect(DerivationEngine.crossDayArtifactUsableToday(envelope(null), '2024-03-02'), isFalse);
    });

    test('a malformed or empty envelope is not reusable', () {
      expect(DerivationEngine.crossDayArtifactUsableToday(null, '2024-03-02'), isFalse);
      expect(DerivationEngine.crossDayArtifactUsableToday('not a map', '2024-03-02'), isFalse);
      expect(
        DerivationEngine.crossDayArtifactUsableToday(
          {'built_for_day': '2024-03-02'}, // no `days`
          '2024-03-02',
        ),
        isFalse,
      );
      expect(
        DerivationEngine.crossDayArtifactUsableToday(
          {'built_for_day': '', 'days': const []},
          '2024-03-02',
        ),
        isFalse,
      );
    });
  });
}
