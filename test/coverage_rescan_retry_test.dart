// A failed recent-day refresh must leave its baseline change pending.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory(
      'build/coverage-audit/rescan',
    ).create(recursive: true);
    LocalDb.dbName = '${root.absolute.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    SharedPreferences.setMockInitialValues({});
    db = await LocalDb.instance;
  });
  tearDownAll(LocalDb.close);
  test(
    'a refused day refresh retries even when its baseline stays the same',
    () async {
      final at = DateTime(2026, 1, 20, 12).millisecondsSinceEpoch ~/ 1000;
      await LocalDb.insertRecord(
        RawRecord(
          counter: 1,
          packetType: 47,
          hex: 'synthetic',
          capturedAt: at * 1000,
          recTs: at,
        ),
        Sample(
          tsEpoch: at,
          counter: 1,
          hr: 60,
          rrIntervalsMs: const [],
          ax: 0,
          ay: 0,
          az: 1,
        ),
      );
      await db.execute(
        "CREATE TRIGGER synthetic_rescan_refusal BEFORE INSERT ON day_result BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
      );
      final log = <String>[];
      final engine = DerivationEngine(log: log.add, background: true);
      try {
        expect(await engine.rescanRecent(const Profile()), 0);
        expect(log.any((s) => s.contains('FAILED/skipped')), isTrue);
        expect(
          await LocalDb.getCursor('baseline_sig'),
          isNull,
          reason:
              'An unsuccessful day must not acknowledge the baseline change',
        );
      } finally {
        await db.execute('DROP TRIGGER synthetic_rescan_refusal');
      }
      expect(await engine.rescanRecent(const Profile()), 1);
      expect(await LocalDb.getCursor('baseline_sig'), isNotNull);
      expect(await engine.rescanRecent(const Profile()), 0);
      expect(engine.running, isFalse);
    },
  );
}
