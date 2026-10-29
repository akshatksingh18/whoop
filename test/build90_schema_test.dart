import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/day_zone_store.dart';
import 'package:whoop_companion/import/backup_crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late String path;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('b90_schema_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tmp.path,
        );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalDb.dbName = 'synthetic_build90_schema.db';
    path = p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName);
    await LocalDb.close();
    await databaseFactory.deleteDatabase(path);
  });
  tearDown(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(path);
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await tmp.delete(recursive: true);
  });

  test(
    'v49 migration preserves weight metadata once; repair does not resurrect a deletion',
    () async {
      await LocalDb.instance;
      await LocalDb.close();
      final old = await openDatabase(path);
      // The simulated v49 database must not retain the new travel-aware view.
      await old.execute('DROP VIEW v_sessions');
      for (final t in [
        'body_weight_reading',
        'food_day_count',
        'day_zone',
        'zone_change',
      ]) {
        await old.execute('DROP TABLE $t');
      }
      await old.execute('ALTER TABLE food_entry DROP COLUMN logged_at');
      await old.delete(
        'sync_cursor',
        where: 'name = ?',
        whereArgs: ['b90_body_reading_seed'],
      );
      await old.insert('body_weight', {
        'date': '2025-02-10',
        'kg': 80.0,
        'at_ts': 1739188800,
        'unit': 'lb',
        'entered': 176.37,
        'source': 'synthetic-import',
        'origin_id': 'source-1',
        'history_only': 1,
      });
      await old.execute('PRAGMA user_version = 49');
      await old.close();
      var db = await LocalDb.instance;
      final r = (await db.query('body_weight_reading')).single;
      expect(r['id'], 'legacy:2025-02-10');
      expect(r['at_ts'], 1739188800);
      expect(r['source'], 'synthetic-import');
      expect(r['history_only'], 1);
      expect(r['unit'], 'lb');
      expect(r['entered'], 176.37);
      expect(r['origin_id'], 'source-1');
      expect(await db.getVersion(), 50);
      expect(
        (await db.rawQuery(
          'PRAGMA table_info(food_entry)',
        )).any((c) => c['name'] == 'logged_at'),
        isTrue,
      );
      await db.delete('body_weight_reading');
      await LocalDb.close();
      db = await LocalDb.instance;
      expect(await db.query('body_weight_reading'), isEmpty);
      expect(await db.query('body_weight'), hasLength(1));
    },
  );

  test(
    'new stores survive encrypted full export/import and are all wiped',
    () async {
      var db = await LocalDb.instance;
      await db.insert('day_zone', {
        'date': '2025-03-09',
        'zone_id': 'America/Chicago',
        'start_offset_sec': -21600,
        'end_offset_sec': -18000,
        'start_ts': 1741500000,
        'end_ts': 1741582800,
      });
      await db.insert('zone_change', {
        'at_ts': 1741500000,
        'zone_id': 'America/Chicago',
      });
      await db.insert('body_weight_reading', {
        'id': 'synthetic-1',
        'date': '2025-03-09',
        'at_ts': 1741510000,
        'kg': 75.0,
        'source': 'test',
        'history_only': 1,
        'created_at': 1741510000,
      });
      await db.insert('food_day_count', {
        'date': '2025-03-09',
        'calorie_goal': 2400.0,
        'basis': 'marked',
        'counted': 1,
        'frozen_at': 1741510000,
        'updated_at': 1741510000,
      });
      await db.insert('food_entry', {
        'id': 'food-1',
        'date': '2025-03-09',
        'at_ts': 1741510000,
        'logged_at': 1741511000,
        'meal': 'breakfast',
        'label': 'Synthetic food',
        'source': 'manual',
        'created_at': 1741511000,
        'updated_at': 1741511000,
      });
      final expected = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'day_zone',
        'zone_change',
        'body_weight_reading',
        'food_day_count',
        'food_entry',
      ]) {
        expect(LocalDb.importTablesForTest, contains(table));
        expect(LocalDb.salvageTablesForTest, contains(table));
        expected[table] = await db.query(table);
      }
      final snapshot = File(await LocalDb.exportCopy());
      final sealed = File(p.join(tmp.path, 'synthetic.osbk'));
      final restored = File(p.join(tmp.path, 'restored.db'));
      await encryptBackupFile(
        snapshot,
        sealed,
        'synthetic-password',
        iterations: 1000,
      );
      await decryptBackupFile(sealed, restored, 'synthetic-password');
      await LocalDb.wipeAll();
      for (final table in expected.keys) {
        expect(await db.query(table), isEmpty);
      }
      await LocalDb.importFromDbFile(restored.path);
      db = await LocalDb.instance;
      for (final table in expected.keys) {
        expect(await db.query(table), expected[table]);
      }
      expect(DayClock.forDate('2025-03-09')?.zoneId, 'America/Chicago');
      expect(localDayLengthSec('2025-03-09'), 23 * 3600);
    },
  );

  test(
    'zone observations persist travel and reopen the same boundaries',
    () async {
      const start = 1767225600;
      await DayZoneStore.observe([
        ZoneChange(start, 'Etc/UTC'),
      ], throughSec: start);
      await DayZoneStore.observe([
        ZoneChange(start + 3600, 'America/Chicago'),
      ], throughSec: start + 2 * 86400);
      final before = DayClock.days.map((d) => d.toRow()).toList();
      await LocalDb.close();
      expect(DayClock.days, isEmpty);
      await LocalDb.instance;
      expect(DayClock.days.map((d) => d.toRow()), before);
      final db = await LocalDb.instance;
      expect(await db.query('zone_change'), hasLength(2));
      await db.insert('sessions', {
        'id': 'synthetic-zone-session',
        'start_ts': start + 3 * 3600,
        'end_ts': start + 4 * 3600,
        'type': 'walking',
        'status': 'done',
        'created_at': start + 3 * 3600,
      });
      expect((await db.query('v_sessions')).single['date'], '2026-01-01');
      expect((await LocalDb.dataHistoryDays()).single['day_id'], '2026-01-01');
      await DayZoneStore.observe([
        ZoneChange(start + 3 * 86400, 'America/Chicago'),
      ], throughSec: start + 3 * 86400);
      expect(await db.query('zone_change'), hasLength(2));
    },
  );

  test(
    'restoring a pre-reading export seeds its weight without duplicating it',
    () async {
      final legacyPath = p.join(tmp.path, 'legacy.db');
      await databaseFactory.deleteDatabase(legacyPath);
      final legacy = await openDatabase(legacyPath);
      await legacy.execute(
        'CREATE TABLE body_weight (date TEXT PRIMARY KEY, '
        'kg REAL NOT NULL, at_ts INTEGER NOT NULL)',
      );
      await legacy.insert('body_weight', {
        'date': '2025-01-01',
        'kg': 72.0,
        'at_ts': 1735722000,
      });
      await legacy.close();
      await LocalDb.instance;
      await LocalDb.importFromDbFile(legacyPath);
      await LocalDb.importFromDbFile(legacyPath);
      final readings = await (await LocalDb.instance).query(
        'body_weight_reading',
      );
      expect(readings, hasLength(1));
      expect(readings.single['at_ts'], 1735722000);
      expect(readings.single['kg'], 72.0);
    },
  );

  test(
    'day export carries new scoped tables and the preceding zone event',
    () async {
      final db = await LocalDb.instance;
      final start = DateTime(2025, 4, 2).millisecondsSinceEpoch ~/ 1000;
      final end = DateTime(2025, 4, 3).millisecondsSinceEpoch ~/ 1000;
      await db.insert('zone_change', {
        'at_ts': start - 100,
        'zone_id': 'Etc/UTC',
      });
      await db.insert('zone_change', {
        'at_ts': end + 100,
        'zone_id': 'Asia/Tokyo',
      });
      await db.insert('day_zone', {
        'date': '2025-04-02',
        'zone_id': 'Etc/UTC',
        'start_offset_sec': 0,
        'end_offset_sec': 0,
        'start_ts': start,
        'end_ts': end,
      });
      await db.insert('body_weight_reading', {
        'id': 'reading-1',
        'date': '2025-04-02',
        'at_ts': start + 3600,
        'kg': 73.0,
        'source': 'test',
        'created_at': start + 3600,
      });
      await db.insert('food_day_count', {
        'date': '2025-04-02',
        'calorie_goal': 2000.0,
        'frozen_at': start,
        'updated_at': start,
      });
      final exported = await openDatabase(
        await LocalDb.exportDaysDb({'2025-04-02'}),
        readOnly: true,
      );
      try {
        for (final table in [
          'day_zone',
          'body_weight_reading',
          'food_day_count',
        ]) {
          expect(await exported.query(table), await db.query(table));
        }
        expect(
          (await exported.query('zone_change')).single['at_ts'],
          start - 100,
        );
      } finally {
        await exported.close();
      }
    },
  );
}
