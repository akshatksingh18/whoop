import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/compute/crossday_pipeline.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:timezone/timezone.dart' as tz;

int instant(String zone, int day, int hour, int minute) =>
    tz.TZDateTime(
      tz.getLocation(zone),
      2026,
      1,
      day,
      hour,
      minute,
    ).millisecondsSinceEpoch ~/
    1000;

void assertPartition(List<DayZone> days) {
  expect(days, isNotEmpty);
  for (var i = 1; i < days.length; i++) {
    expect(days[i].startSec, days[i - 1].endSec);
    expect(days[i].date.compareTo(days[i - 1].date), greaterThan(0));
  }
}

void main() {
  setUpAll(initializeDayZones);
  tearDown(() => DayClock.install([], []));

  for (final hour in [0, 23]) {
    test(
      'westward around midnight ($hour): no repeated label or overlapping instant',
      () {
        final start = instant('Asia/Tokyo', 1, 0, 0);
        final change = instant('Asia/Tokyo', 2, hour, 30);
        final changes = [
          ZoneChange(start, 'Asia/Tokyo'),
          ZoneChange(change, 'Pacific/Honolulu'),
        ];
        final days = buildDayZones(
          fromSec: start,
          throughSec: change + 3 * 86400,
          changes: changes,
        );
        assertPartition(days);
        DayClock.install(days, changes);
        expect(dayLabelAtSec(change), '2026-01-02');
        expect(
          days.firstWhere((d) => d.date == '2026-01-02').endSec -
              days.firstWhere((d) => d.date == '2026-01-02').startSec,
          greaterThan(86400),
        );
        expect(
          todayLabel(DateTime.fromMillisecondsSinceEpoch(change * 1000)),
          '2026-01-02',
        );
      },
    );
    test(
      'eastward around midnight ($hour): new date starts at the observed seam',
      () {
        final start = instant('Pacific/Honolulu', 1, 0, 0);
        final change = instant('Pacific/Honolulu', 2, hour, 30);
        final changes = [
          ZoneChange(start, 'Pacific/Honolulu'),
          ZoneChange(change, 'Asia/Tokyo'),
        ];
        final days = buildDayZones(
          fromSec: start,
          throughSec: change + 2 * 86400,
          changes: changes,
        );
        assertPartition(days);
        DayClock.install(days, changes);
        expect(
          DayClock.at(change - 1)!.date.compareTo(DayClock.at(change)!.date),
          hour == 0 ? 0 : lessThan(0),
        );
        expect(DayClock.at(change)!.zoneId, 'Asia/Tokyo');
      },
    );
  }
  test('east date-line crossing skips the date never lived', () {
    final start = instant('Pacific/Pago_Pago', 1, 0, 0);
    final change = instant('Pacific/Pago_Pago', 1, 23, 30);
    final changes = [
      ZoneChange(start, 'Pacific/Pago_Pago'),
      ZoneChange(change, 'Pacific/Kiritimati'),
    ];
    final days = buildDayZones(
      fromSec: start,
      throughSec: change + 86400,
      changes: changes,
    );
    assertPartition(days);
    expect(days.map((d) => d.date), isNot(contains('2026-01-02')));
    DayClock.install(days, changes);
    expect(dayLabelAtSec(change), '2026-01-03');
  });
  for (final (month, day, hours) in [(3, 8, 23), (11, 1, 25)]) {
    test(
      'Chicago DST $month/$day is $hours hours with both offsets stored',
      () {
        final start =
            tz.TZDateTime(
              tz.getLocation('America/Chicago'),
              2026,
              month,
              day,
            ).millisecondsSinceEpoch ~/
            1000;
        final changes = [ZoneChange(start, 'America/Chicago')];
        final days = buildDayZones(
          fromSec: start,
          throughSec: start,
          changes: changes,
        );
        expect(days.single.endSec - start, hours * 3600);
        expect(days.single.startOffsetSec, isNot(days.single.endOffsetSec));
        DayClock.install(days, changes);
        expect(localDayLengthSec(days.single.date), hours * 3600);
      },
    );
  }
  test(
    'return home and worker snapshot retain earlier boundaries and zone labels',
    () {
      final start = instant('Asia/Tokyo', 1, 0, 0);
      final changes = [
        ZoneChange(start, 'Asia/Tokyo'),
        ZoneChange(start + 12 * 3600, 'America/Chicago'),
      ];
      final first = buildDayZones(
        fromSec: start,
        throughSec: start + 2 * 86400,
        changes: changes,
      );
      changes.add(ZoneChange(start + 4 * 86400, 'Asia/Tokyo'));
      final returned = buildDayZones(
        fromSec: start,
        throughSec: start + 5 * 86400,
        changes: changes,
      );
      expect(
        returned.take(first.length).map((d) => d.toRow()),
        first.map((d) => d.toRow()),
      );
      DayClock.install(returned, changes);
      final snapshot = DayClock.snapshot();
      DayClock.install([], []);
      DayClock.restore(snapshot);
      expect(localDayStartSec(first.first.date), first.first.startSec);
      expect(
        DayClock.abbreviation(first.first.date, nowSec: start + 5 * 86400),
        isNotNull,
      );
    },
  );
  test(
    'night spanning travel keeps absolute duration and belongs to wake day',
    () {
      final start = instant('Asia/Tokyo', 2, 0, 0);
      final change = start + 3600;
      final changes = [
        ZoneChange(start - 86400, 'Asia/Tokyo'),
        ZoneChange(change, 'Pacific/Honolulu'),
      ];
      final days = buildDayZones(
        fromSec: start - 86400,
        throughSec: start + 2 * 86400,
        changes: changes,
      );
      DayClock.install(days, changes);
      final onset = start - 3600, wake = start + 7 * 3600;
      expect(DayClock.spansZoneChange(onset, wake), true);
      expect(wake - onset, 8 * 3600);
      expect(localDateLabel(wake), '2026-01-02');
      expect(localDayStartSec(localDateLabel(wake)), start);
    },
  );
  test(
    'regularity compares absolute instants across travel, DST and missing labels',
    () {
      const base = 1767225600;
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < 4; i++) {
        final start = base + i * 86400;
        rows.add({
          'date':
              '2026-01-${i == 0 ? '01' : (i + 2).toString().padLeft(2, '0')}',
          'worn_min': 1440,
          'day_zone': {'start_ts': start, 'end_ts': start + 86400},
          'hypnogram': [
            {'start': start, 'end': start + 8 * 3600, 'stage': 'light'},
          ],
        });
      }
      final bundle = buildCrossDayBundle(rows, {});
      final sri = (bundle['regularity'] as Map)['value'] as Map;
      expect(sri['sri'], 100);
      final pairs = sri['pairs'] as List;
      expect(
        (pairs.first as Map)['start_ts'] -
            (pairs.first as Map)['previous_start_ts'],
        86400,
      );
    },
  );
}
