// The rules that make nutrition and medication honest, tested without a
// database — every one of them is a pure function on purpose.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/med_store.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';

FoodEntry _entry({
  required String date,
  double? kcal,
  double? protein,
  int hour = 12,
  String meal = 'lunch',
  FoodSource source = FoodSource.manual,
  bool confirmed = false,
}) {
  final parts = date.split('-').map(int.parse).toList();
  return FoodEntry(
    id: 'e$hour$meal',
    date: date,
    meal: meal,
    label: 'Something',
    atTs:
        DateTime(parts[0], parts[1], parts[2], hour).millisecondsSinceEpoch ~/
        1000,
    kcal: kcal,
    proteinG: protein,
    source: source,
    confirmed: confirmed,
  );
}

void main() {
  const yesterday = '2026-08-14';
  const today = '2026-08-15';

  group('null is not zero', () {
    test('a nutrient nobody reported is null, not a zero total', () {
      final d = rollupDay(yesterday, [
        _entry(date: yesterday, kcal: 500),
      ], today: today);
      expect(d.kcal.value, 500);
      // No entry carried protein, so the day does not claim zero grams.
      expect(d.protein.value, isNull);
      expect(d.protein.complete, isFalse);
    });

    test('a total that summed past an unknown is a FLOOR, not a total', () {
      final d = rollupDay(yesterday, [
        _entry(date: yesterday, kcal: 500, hour: 8, meal: 'breakfast'),
        _entry(date: yesterday, hour: 19, meal: 'dinner'),
      ], today: today);
      expect(d.kcal.value, 500);
      expect(d.kcal.isFloor, isTrue);
      expect(d.kcal.complete, isFalse);
    });
  });

  group('an eating occasion is a complete log', () {
    test('a one-tap entry with no numbers is valid and counted as logged', () {
      final d = rollupDay(yesterday, [
        _entry(date: yesterday),
      ], today: today);
      expect(d.logged, isTrue);
      expect(d.entries.single.isBareOccasion, isTrue);
      // …but it cannot feed an energy average, because there is no energy.
      expect(d.countsTowardAverages, isFalse);
    });
  });

  group('partial days are automatic, and excluded', () {
    test('today is in progress — never judged incomplete while it runs', () {
      final d = rollupDay(today, [
        _entry(date: today, kcal: 300, hour: 8),
      ], today: today);
      expect(d.state, DayLogState.inProgress);
      expect(d.countsTowardAverages, isFalse);
    });

    test('a finished day with an unknown energy is partial', () {
      final d = rollupDay(yesterday, [
        _entry(date: yesterday, kcal: 300, hour: 8),
        _entry(date: yesterday, hour: 19),
      ], today: today);
      expect(d.state, DayLogState.partial);
    });

    test('a finished day that never reaches the evening is partial', () {
      final d = rollupDay(yesterday, [
        _entry(date: yesterday, kcal: 300, hour: 8),
        _entry(date: yesterday, kcal: 600, hour: 13),
      ], today: today);
      expect(d.state, DayLogState.partial);
    });

    test('a day with energy everywhere and an evening occasion is complete', () {
      final d = rollupDay(yesterday, [
        _entry(date: yesterday, kcal: 300, hour: 8),
        _entry(date: yesterday, kcal: 900, hour: 19),
      ], today: today);
      expect(d.state, DayLogState.complete);
      expect(d.kcal.value, 1200);
    });

    test('an empty day is none, not zero kcal', () {
      final d = rollupDay(yesterday, const [], today: today);
      expect(d.state, DayLogState.none);
      expect(d.kcal.value, isNull);
    });

    test('the average excludes partial days rather than being dragged by them', () {
      final complete = rollupDay(yesterday, [
        _entry(date: yesterday, kcal: 2000, hour: 8),
        _entry(date: yesterday, kcal: 400, hour: 19),
      ], today: today);
      final partial = rollupDay('2026-08-13', [
        _entry(date: '2026-08-13', kcal: 200, hour: 8),
      ], today: today);
      final w = NutritionWindow([partial, complete]);
      expect(w.daysLogged, 2);
      expect(w.daysExcluded, 1);
      // 2400, not (2400 + 200) / 2 — the partial day would have halved it.
      expect(w.meanKcal.value, 2400);
      expect(w.meanKcal.days, 1);
    });

    test('a macro that is only a floor on a counted day is left out of its own '
        'mean, and says how many days it lost', () {
      // Both days qualify on ENERGY (complete kcal + an evening occasion), so
      // `countsTowardAverages` is true for both. Only one reports protein on
      // every occasion; the other summed past an occasion with no protein
      // figure, which makes its total a lower bound.
      final full = rollupDay(yesterday, [
        _entry(date: yesterday, kcal: 2000, hour: 8, protein: 100),
        _entry(date: yesterday, kcal: 400, hour: 19, protein: 40),
      ], today: today);
      final floored = rollupDay('2026-08-13', [
        _entry(date: '2026-08-13', kcal: 2000, hour: 8, protein: 20),
        _entry(date: '2026-08-13', kcal: 400, hour: 19),
      ], today: today);
      expect(full.countsTowardAverages, isTrue);
      expect(floored.countsTowardAverages, isTrue);
      expect(floored.protein.isFloor, isTrue);

      final w = NutritionWindow([floored, full]);
      // 140, not (140 + 20) / 2 = 80 — the floor would have understated the
      // mean by 60 g/day and the screen showed it as an exact figure.
      expect(w.meanProtein.value, 140);
      expect(w.meanProtein.days, 1);
      expect(w.meanProtein.floorDays, 1);
      // Energy is untouched by the per-nutrient gate: both days are complete.
      expect(w.meanKcal.value, 2400);
      expect(w.meanKcal.days, 2);
    });

    test('a macro no complete day reported is absent, not zero, and not a '
        'floor', () {
      final d = rollupDay(yesterday, [
        _entry(date: yesterday, kcal: 2000, hour: 8),
        _entry(date: yesterday, kcal: 400, hour: 19),
      ], today: today);
      final w = NutritionWindow([d]);
      expect(w.meanFibre.value, isNull);
      expect(w.meanFibre.days, 0);
      // Nothing reported fibre at all, so nothing was EXCLUDED as a floor —
      // the screen renders "not recorded", not "not counted".
      expect(w.meanFibre.floorDays, 0);
    });
  });

  group('a photo never emits a calorie total', () {
    test('an unconfirmed photo entry loses every number it was handed', () {
      final e = FoodEntry(
        id: 'p1',
        date: yesterday,
        meal: 'lunch',
        label: 'Rice, chicken, greens',
        kcal: 720,
        proteinG: 40,
        source: FoodSource.photo,
      ).sanitised;
      expect(e.kcal, isNull);
      expect(e.proteinG, isNull);
      expect(e.label, 'Rice, chicken, greens'); // the identification survives
      expect(e.isBareOccasion, isTrue);
    });

    test('a confirmed portion keeps its numbers', () {
      final e = FoodEntry(
        id: 'p2',
        date: yesterday,
        meal: 'lunch',
        label: 'Rice',
        kcal: 300,
        source: FoodSource.photo,
        confirmed: true,
      ).sanitised;
      expect(e.kcal, 300);
    });
  });

  test('provenance, not popularity: only a manufacturer panel is verified', () {
    expect(isVerified(FoodSource.verified), isTrue);
    for (final s in [
      FoodSource.manual,
      FoodSource.photo,
      FoodSource.repeat,
    ]) {
      expect(isVerified(s), isFalse, reason: '$s must not read as verified');
    }
  });

  group('medication adherence states its window and forgives the future', () {
    final def = MedDef(
      key: 'custom_d',
      label: 'Vitamin D',
      schedule: const [
        MedSchedule(8 * 60, [1, 2, 3, 4, 5, 6, 7]),
        MedSchedule(21 * 60, [1, 2, 3, 4, 5, 6, 7]),
      ],
    );

    test('a slot still ahead of you today is in no denominator', () {
      final now = DateTime(2026, 8, 15, 12);
      final slots = slotsForDay([def], todayLabel(now), const {}, now: now);
      expect(slots.map((s) => s.state), [
        DoseState.missed, // 08:00 has passed untaken
        DoseState.upcoming, // 21:00 has not
      ]);
      final a = adherence(slots);
      expect(a, (taken: 0, of: 1));
    });

    test('a taken dose counts, and an inactive medication does not', () {
      final now = DateTime(2026, 8, 15, 22);
      final date = todayLabel(now);
      final slots = slotsForDay(
        [
          def,
          MedDef(
            key: 'custom_off',
            label: 'Stopped',
            active: false,
            schedule: const [
              MedSchedule(9 * 60, [1, 2, 3, 4, 5, 6, 7]),
            ],
          ),
        ],
        date,
        {
          'custom_d': {
            8 * 60: {'taken_ts': 1, 'skipped': 0},
          },
        },
        now: now,
      );
      expect(slots, hasLength(2));
      expect(adherence(slots), (taken: 1, of: 2));
    });

    test('no slot exists before the medication did', () {
      // Added today at 15:00. The 08:00 dose today, and every dose on every
      // earlier day, was never an opportunity — resolving them as misses put a
      // fabricated denominator ("0 of 7") on the Adherence card the moment a
      // medication was saved.
      final now = DateTime(2026, 8, 15, 23);
      final added = MedDef(
        key: 'custom_new',
        label: 'Just added',
        createdAt: DateTime(2026, 8, 15, 15).millisecondsSinceEpoch,
        schedule: const [
          MedSchedule(8 * 60, [1, 2, 3, 4, 5, 6, 7]),
          MedSchedule(21 * 60, [1, 2, 3, 4, 5, 6, 7]),
        ],
      );
      expect(
        slotsForDay([added], '2026-08-14', const {}, now: now),
        isEmpty,
        reason: 'the day before it existed',
      );
      final todaySlots = slotsForDay([added], '2026-08-15', const {}, now: now);
      expect(todaySlots.map((s) => s.slotMin), [21 * 60]);
      expect(adherence(todaySlots), (taken: 0, of: 1));
    });

    test('a dose already recorded against a pre-creation slot is still shown',
        () {
      // deleteDef keeps dose history and a re-added key picks it back up. A
      // recorded dose is real data whatever the creation stamp says.
      final now = DateTime(2026, 8, 15, 23);
      final readded = MedDef(
        key: 'custom_d',
        label: 'Vitamin D',
        createdAt: DateTime(2026, 8, 15, 15).millisecondsSinceEpoch,
        schedule: const [
          MedSchedule(8 * 60, [1, 2, 3, 4, 5, 6, 7]),
        ],
      );
      final slots = slotsForDay([readded], '2026-08-15', {
        'custom_d': {
          8 * 60: {'taken_ts': 1, 'skipped': 0},
        },
      }, now: now);
      expect(slots.single.state, DoseState.taken);
    });

    test('a schedule that skips a weekday emits no slot that day', () {
      // 2026-08-15 is a Saturday (weekday 6).
      final now = DateTime(2026, 8, 15, 23);
      final weekdaysOnly = MedDef(
        key: 'custom_w',
        label: 'Weekdays',
        schedule: const [
          MedSchedule(8 * 60, [1, 2, 3, 4, 5]),
        ],
      );
      expect(
        slotsForDay([weekdaysOnly], todayLabel(now), const {}, now: now),
        isEmpty,
      );
    });
  });
}
