// Three tiny authored rows exercise real conversion and compare-and-set races.
// Complete-night derivation and the full suite remain cloud-only.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/series_codec.dart';
import 'day_result_reencode_test.dart' show bundleFor, seedLegacy;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const t0 = 1617667200;
  setUpAll(() => coverageStore('reencode-cursor-boundaries'));
  setUp(() async {
    await resetCoverageStore();
    final db = await LocalDb.instance;
    for (var day = 4; day <= 6; day++) {
      await seedLegacy(db, '2021-04-0$day', t0 + day * 86400);
    }
  });
  tearDown(() => LocalDb.debugAfterReencodePrepare = null);
  tearDownAll(LocalDb.close);
  Future<Map<String, Object?>> row(String day) async =>
      (await (await LocalDb.instance).query(
        'day_result',
        where: 'day_id = ? AND algo_version = ?',
        whereArgs: [day, 47],
      )).single;
  Future<Map<String, dynamic>> cursor() async =>
      jsonDecode(
            (await LocalDb.computeFreshness(
                  LocalDb.kReencodeCursorKey,
                ))!['payload_json']
                as String,
          )
          as Map<String, dynamic>;

  test(
    'a legacy day-only cursor converts strictly older rows without touching the cursor day',
    () async {
      final original = await row('2021-04-06');
      await LocalDb.putComputeFreshness(
        LocalDb.kReencodeCursorKey,
        jsonEncode({'cursor': '2021-04-06', 'done': false}),
      );
      expect(await LocalDb.reencodeLegacyDayResults(limit: 3), 2);
      expect(await row('2021-04-06'), original);
      for (var day = 4; day <= 5; day++) {
        final converted = await row('2021-04-0$day');
        expect(
          SeriesCodec.needsReencode(converted['payload_json'] as String),
          false,
        );
        expect(
          SeriesCodec.decodePayloadJson(converted['payload_json']),
          bundleFor(t0 + day * 86400),
        );
        expect(converted['computed_at'], 1234567);
        expect(converted['finalized'], 1);
      }
      expect(await cursor(), containsPair('done', true));
      expect(await LocalDb.reencodeLegacyDayResults(limit: 3), 0);
    },
  );

  for (final resumed in [false, true]) {
    test(
      'a competing ${resumed ? 'first resumed' : 'middle'} row is preserved and converted on retry',
      () async {
        if (resumed) {
          await LocalDb.putComputeFreshness(
            LocalDb.kReencodeCursorKey,
            jsonEncode({
              'cursor': '2021-04-06',
              'cursor_version': 47,
              'done': false,
            }),
          );
        }
        final original = await row('2021-04-05');
        final fresh = bundleFor(t0 + 1234);
        LocalDb.debugAfterReencodePrepare = () async {
          await (await LocalDb.instance).update(
            'day_result',
            {'payload_json': jsonEncode(fresh)},
            where: 'day_id = ? AND algo_version = ?',
            whereArgs: ['2021-04-05', 47],
          );
        };
        expect(
          await LocalDb.reencodeLegacyDayResults(limit: 3),
          resumed ? 1 : 2,
        );
        expect(
          SeriesCodec.decodePayloadJson(
            (await row('2021-04-05'))['payload_json'],
          ),
          fresh,
        );
        expect(await cursor(), containsPair('cursor', '2021-04-06'));
        expect(await cursor(), containsPair('cursor_version', 47));
        expect(await cursor(), containsPair('done', false));
        LocalDb.debugAfterReencodePrepare = null;
        expect(await LocalDb.reencodeLegacyDayResults(limit: 3), 1);
        final converted = await row('2021-04-05');
        expect(
          SeriesCodec.needsReencode(converted['payload_json'] as String),
          false,
        );
        expect(SeriesCodec.decodePayloadJson(converted['payload_json']), fresh);
        expect(
          {...converted}..remove('payload_json'),
          {...original}..remove('payload_json'),
        );
        expect(await cursor(), containsPair('done', true));
        expect(await LocalDb.reencodeLegacyDayResults(limit: 3), 0);
      },
    );
  }
}
