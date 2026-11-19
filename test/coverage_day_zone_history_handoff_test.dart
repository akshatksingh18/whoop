import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/day_zone_store.dart';
import 'package:whoop_companion/data/db.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('day-zone-history-handoff'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final reverseArrivalOrder in [false, true]) {
    test(
      'the first observed zone hydrates earlier records before a later date jump: $reverseArrivalOrder',
      () async {
        int seconds(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;
        final oldStart = seconds(DateTime.utc(2021, 4, 5, 23, 15));
        final firstObservation = seconds(DateTime.utc(2021, 4, 6, 10));
        final arrival = seconds(DateTime.utc(2021, 4, 6, 17));
        const id = 'authored-before-zone-observation';
        await LocalDb.putSession({
          'id': id,
          'type': 'walking',
          'status': 'done',
          'start_ts': oldStart,
          'end_ts': oldStart + 120,
          'source': 'manual',
          'created_at': oldStart * 1000,
        });
        final saved = await LocalDb.session(id);
        final observations = [
          ZoneChange(firstObservation, 'Europe/London'),
          ZoneChange(arrival, 'Asia/Tokyo'),
        ];
        await DayZoneStore.observe(
          reverseArrivalOrder ? observations.reversed.toList() : observations,
          throughSec: arrival + 1,
        );
        final db = await LocalDb.instance;
        final zones = await db.query('day_zone', orderBy: 'start_ts');
        final changes = await db.query('zone_change', orderBy: 'at_ts');
        expect(changes, hasLength(2));
        expect(zones.map((zone) => zone['date']), ['2021-04-06', '2021-04-07']);

        DayClock.install([], []);
        await DayZoneStore.hydrate(db);
        expect(DayClock.zoneAt(oldStart), 'Europe/London');
        expect(DayClock.localAt(oldStart).hour, 0);
        expect(DayClock.localAt(oldStart).minute, 15);
        expect(dayLabelAtSec(oldStart), '2021-04-06');
        expect(dayLabelAtSec(arrival - 1), '2021-04-06');
        expect(dayLabelAtSec(arrival), '2021-04-07');
        expect(DayClock.zoneAt(arrival), 'Asia/Tokyo');
        expect(DayClock.at(arrival - 1)?.endSec, arrival);
        expect(DayClock.at(arrival)?.startSec, arrival);
        expect(await LocalDb.session(id), saved);
        await DayZoneStore.observe(observations, throughSec: arrival + 1);
        expect(await db.query('zone_change', orderBy: 'at_ts'), changes);
        expect(await db.query('day_zone', orderBy: 'start_ts'), zones);
        expect(await LocalDb.session(id), saved);
      },
    );
  }
}
