// Short authored import windows exercise the real frozen-floor transaction.
// These verify persistence/absence policy, not pedometer or physiological accuracy.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/series_codec.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('movement-floor-store'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';
  String shifted(int days) {
    final d = DateTime.parse(day);
    return dayLabelOf(DateTime(d.year, d.month, d.day + days));
  }

  Substrate input() {
    final ts = localDayStartSec(day)! + 12 * 3600;
    const n = 900;
    return Substrate(
      tsSec: [for (var i = 0; i < n; i++) ts + i],
      hr: List.filled(n, 100),
      rrTsMs: [],
      rrMs: [],
      ax: [for (var i = 0; i < n; i++) i.isEven ? .3 : -.3],
      ay: List.filled(n, .0),
      az: List.filled(n, 1.0),
      skinTemp: [for (var i = 0; i < n; i++) 3000 + i ~/ 300 * 100],
      spo2Red: List.filled(n, null),
      spo2Ir: List.filled(n, null),
      skinContact: List.filled(n, null),
      deviceFamily: 'gen5',
    );
  }

  for (final mode in [
    'enrolling',
    'first-freeze',
    'thin-refreeze',
    'backfill',
    'refreeze',
  ]) {
    test(
      'movement floor $mode preserves its owning date and history requirement',
      () async {
        final n = mode == 'enrolling' || mode == 'thin-refreeze' ? 4 : 14;
        for (var i = 1; i <= n; i++) {
          await LocalDb.putMetricSeriesValue(
            shifted(-(mode == 'backfill' ? i + 40 : i)),
            'dyn_p90',
            .1,
          );
        }
        if (mode == 'thin-refreeze' ||
            mode == 'refreeze' ||
            mode == 'backfill') {
          await LocalDb.putMovementFloor(
            floorG: .04,
            frozenOn: shifted(mode == 'backfill' ? 2 : -400),
            days: 14,
          );
        }
        final engine = DerivationEngine(background: true);
        final done = <String>[];
        expect(
          await engine.deriveImportedDays(
            input(),
            const Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70),
            {day},
            onDayDone: done.add,
          ),
          1,
        );
        expect(done, [day]);
        expect(engine.running, false);
        final stored = await LocalDb.getMovementFloor();
        if (mode == 'enrolling') {
          expect(stored, isNull);
        } else if (mode == 'thin-refreeze' || mode == 'backfill') {
          expect(stored!.floorG, .04);
          expect(stored.frozenOn, shifted(mode == 'backfill' ? 2 : -400));
        } else {
          expect(stored!.frozenOn, day);
          expect(stored.floorG, greaterThan(0));
          expect(stored.floorG, isNot(.04));
        }
        final row = (await LocalDb.dayResult(day))!;
        expect(row['partial'], 0);
        expect(row['finalized'], 1);
        final b = SeriesCodec.decodePayloadJson(row['payload_json'] as String)!;
        final curve = (b['series'] as Map)['skin_temp_day'] as List;
        expect(curve, hasLength(3));
        expect(curve.map((p) => p['v']), [-100.0, 0.0, 100.0]);
        expect(
          (b['movement'] as Map)['dyn_floor_g'],
          mode == 'enrolling' ? isNull : stored!.floorG,
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
