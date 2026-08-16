// checkSyncStaleness must not spend its 48-hour cooldown on a notification the
// shared gate dropped.
//
// The "your band hasn't synced" event is NotifCategory.device / normal
// priority, so NotificationCenter.emit refuses it whenever the device category
// is off or the wake lands inside quiet hours — and emit DROPS, it never
// queues. Writing the cooldown before the emit meant the backstop went silent
// for another 48 hours over a notification nobody ever saw. The headless wake
// this runs from is typically an overnight one, i.e. exactly the refused case.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/sync/background_sync.dart';

const _kCooldown = 'last_staleness_notified_ms';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_bgsync_staleness_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('a dropped staleness alert leaves the cooldown unspent', () async {
    // Device notifications switched off — the same early return quiet hours
    // takes, without depending on the wall clock the test happens to run at.
    SharedPreferences.setMockInitialValues({'notif_device': false});
    // Four days since the last record: well past the notify tier.
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.setCursor('rec_ts_hw', '${nowSec - 4 * 24 * 3600}');

    await checkSyncStaleness();

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getInt(_kCooldown), isNull,
        reason: 'the cooldown belongs to an alert that was actually shown');
  });

  test('a band that has never synced is not stale', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.setCursor('rec_ts_hw', '0');
    await checkSyncStaleness();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getInt(_kCooldown), isNull);
  });
}
