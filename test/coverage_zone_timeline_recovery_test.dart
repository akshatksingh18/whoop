// Small authored date ranges and the real SQLite timeline. These do not
// reconstruct travel before observation or certify delivery of native changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_zone_rules.dart';
import 'package:whoop_companion/data/day_zone_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

int epoch(int day) =>
    DateTime.utc(2021, 4, day, 12).millisecondsSinceEpoch ~/ 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('zone-timeline-recovery'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'Zone ensureRange without observations keeps the identifier and history unknown',
    () async {
      await DayZoneStore.ensureRange(epoch(6), epoch(7));
      final db = await LocalDb.instance;
      expect(await db.query('zone_change'), isEmpty);
      expect(await db.query('day_zone'), isEmpty);
      expect(DayClock.changes, isEmpty);
      expect(DayClock.at(epoch(6)), isNull);
    },
  );
  test(
    'An invalid zone observation cannot mutate chronology or poison a valid retry',
    () async {
      await LocalDb.setCursor('authored-unrelated', 'keep');
      final db = await LocalDb.instance;
      final before = await db.query('sync_cursor');
      await expectLater(
        DayZoneStore.observe([
          ZoneChange(epoch(6), 'Authored/Unknown'),
        ], throughSec: epoch(7)),
        throwsArgumentError,
      );
      expect(await db.query('zone_change'), isEmpty);
      expect(await db.query('day_zone'), isEmpty);
      expect(DayClock.snapshot(), {'days': [], 'changes': []});
      await DayZoneStore.observe(
        [ZoneChange(epoch(6), 'UTC')],
        fromSec: epoch(6),
        throughSec: epoch(7),
      );
      expect(DayClock.at(epoch(6))!.zoneId, 'UTC');
      expect(DayClock.at(epoch(7))!.zoneId, 'UTC');
      expect(await db.query('sync_cursor'), before);
    },
  );
  test(
    'Initial zone context extends to the oldest retained label and instant without rewriting evidence',
    () async {
      final db = await LocalDb.instance;
      await LocalDb.putDayResult(
        dayId: '2021-04-04',
        algoVersion: 101,
        payloadJson: '{}',
        windowJson: '{}',
      );
      await LocalDb.putMetricSeriesValue('2021-04-03', 'rhr', 55);
      await db.insert('sessions', {
        'id': 'authored-older-session',
        'type': 'other',
        'start_ts': epoch(2),
        'status': 'done',
        'created_at': 1,
      });
      final days = await db.query('day_result');
      final series = await db.query('metric_series');
      final sessions = await db.query('sessions');
      await DayZoneStore.observe([
        ZoneChange(epoch(6), 'UTC'),
      ], throughSec: epoch(6));
      expect(DayClock.days.first.date, '2021-04-02');
      expect(DayClock.days.last.date, '2021-04-06');
      expect(DayClock.changes.single.atSec, epoch(6));
      expect(DayClock.changes.single.zoneId, 'UTC');
      expect(await db.query('day_result'), days);
      expect(await db.query('metric_series'), series);
      expect(await db.query('sessions'), sessions);
    },
  );
  test(
    'Zone range hydration and extension retain existing dates and the sole observed change',
    () async {
      await DayZoneStore.observe([
        ZoneChange(epoch(6), 'UTC'),
      ], throughSec: epoch(6));
      final db = await LocalDb.instance;
      final old = await db.query('day_zone');
      final changes = await db.query('zone_change');
      DayClock.install([], []);
      await DayZoneStore.ensureRange(epoch(5), epoch(7));
      expect(DayClock.at(epoch(5))!.date, '2021-04-05');
      expect(DayClock.at(epoch(7))!.date, '2021-04-07');
      expect(await db.query('zone_change'), changes);
      final extended = await db.query('day_zone');
      for (final row in old) {
        expect(extended, contains(equals(row)));
      }
      await DayZoneStore.ensureRange(epoch(5), epoch(7));
      expect(await db.query('day_zone'), extended);
    },
  );
  test(
    'A restored day without a change ledger still supplies its existing local zone',
    () {
      DayClock.install([
        DayZone(
          date: '2021-04-06',
          zoneId: 'UTC',
          startSec: epoch(6) - 43200,
          endSec: epoch(6) + 43200,
          startOffsetSec: 0,
          endOffsetSec: 0,
        ),
      ], []);
      expect(DayClock.zoneAt(epoch(6)), 'UTC');
      expect(DayClock.localAt(epoch(6)).hour, 12);
      expect(DayClock.zoneAt(epoch(7)), isNull);
    },
  );
  test(
    'A malformed restored date has no chart anchor instead of inventing a calendar label',
    () {
      DayClock.install([
        DayZone(
          date: 'authored-invalid-date',
          zoneId: 'UTC',
          startSec: epoch(6),
          endSec: epoch(7),
          startOffsetSec: 0,
          endOffsetSec: 0,
        ),
      ], []);
      expect(DayClock.chartAnchor('authored-invalid-date'), isNull);
      expect(DayClock.chartAnchor('2021-04-06'), isNull);
    },
  );
}
