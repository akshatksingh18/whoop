// Build 90 (C3): every weigh-in is kept, and the day's weight is its FIRST
// reading. body_weight stays the one-row-per-day value every reader uses.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _day = '2026-10-12';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_weight_readings_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(() async => BodyLogDb.deleteWeight(_day));

  test(
    'a later reading is kept but the first stays the day\'s weight',
    () async {
      await BodyLogDb.putWeight(
        _day,
        79.4,
        'kg',
        at: DateTime(2026, 10, 12, 7, 2),
      );
      await BodyLogDb.putWeight(
        _day,
        80.3,
        'kg',
        at: DateTime(2026, 10, 12, 13, 40),
      );
      final readings = await BodyLogDb.readingsOn(_day);
      expect(readings.map((r) => r.kg), [79.4, 80.3]);
      expect((await BodyLogDb.weightOn(_day))?.kg, 79.4);
    },
  );

  test('an earlier reading entered later becomes the day\'s weight', () async {
    await BodyLogDb.putWeight(
      _day,
      80.3,
      'kg',
      at: DateTime(2026, 10, 12, 13, 40),
    );
    await BodyLogDb.putWeight(
      _day,
      79.4,
      'kg',
      at: DateTime(2026, 10, 12, 7, 2),
    );
    expect((await BodyLogDb.weightOn(_day))?.kg, 79.4);
  });

  test('correcting the first fixes it in place', () async {
    await BodyLogDb.putWeight(
      _day,
      97.4,
      'kg',
      at: DateTime(2026, 10, 12, 7, 2),
    );
    await BodyLogDb.putWeight(_day, 79.4, 'kg', correctFirst: true);
    final readings = await BodyLogDb.readingsOn(_day);
    expect(readings, hasLength(1));
    expect(readings.single.kg, 79.4);
    expect(
      readings.single.atTs,
      DateTime(2026, 10, 12, 7, 2).millisecondsSinceEpoch ~/ 1000,
    );
  });

  test('deleting the first makes the next reading the day\'s weight', () async {
    await BodyLogDb.putWeight(
      _day,
      79.4,
      'kg',
      at: DateTime(2026, 10, 12, 7, 2),
    );
    await BodyLogDb.putWeight(
      _day,
      80.3,
      'kg',
      at: DateTime(2026, 10, 12, 13, 40),
    );
    final first = (await BodyLogDb.readingsOn(_day)).first;
    await BodyLogDb.deleteReading(first.id);
    expect((await BodyLogDb.weightOn(_day))?.kg, 80.3);
    await BodyLogDb.deleteReading((await BodyLogDb.readingsOn(_day)).single.id);
    expect(await BodyLogDb.weightOn(_day), isNull);
  });

  test(
    'a re-imported record updates its reading instead of doubling it',
    () async {
      for (var i = 0; i < 2; i++) {
        await BodyLogDb.putWeight(
          _day,
          176.5,
          'lb',
          originId: 'akshatos:abc',
          historyOnly: true,
          at: DateTime(2026, 10, 12),
        );
      }
      expect(await BodyLogDb.readingsOn(_day), hasLength(1));
    },
  );

  test('a past day without a time is stamped on that day, not today', () async {
    await BodyLogDb.putWeight(_day, 79.4, 'kg');
    final r = (await BodyLogDb.readingsOn(_day)).single;
    final at = DateTime.fromMillisecondsSinceEpoch(r.atTs * 1000);
    expect((at.year, at.month, at.day), (2026, 10, 12));
    expect(r.historyOnly, isTrue);
  });
}
