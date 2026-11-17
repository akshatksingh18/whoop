// Authored native messages through the real zone transaction and ACK bridge.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_zone_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('whoop/day_zone');
  const timezone = MethodChannel('flutter_timezone');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  List<dynamic>? inbox;
  late int at;
  var refuseEvents = false, refuseAck = false, refuseZone = false;
  final calls = <MethodCall>[];
  setUpAll(() => coverageStore('native-zone-inbox'));
  setUp(() async {
    await resetCoverageStore();
    at = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600;
    inbox = [
      {'at_ts': at, 'zone_id': 'Asia/Tokyo'},
    ];
    calls.clear();
    refuseEvents = refuseAck = refuseZone = false;
    messenger.setMockMethodCallHandler(timezone, (_) async {
      if (refuseZone) {
        throw PlatformException(code: 'authored zone unavailable');
      }
      return 'UTC';
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      if (call.method == 'events') {
        if (refuseEvents) {
          throw PlatformException(code: 'authored inbox unavailable');
        }
        return inbox;
      }
      if (call.method == 'ack') {
        final db = await LocalDb.instance;
        expect(
          await db.query('zone_change', where: 'at_ts=?', whereArgs: [at]),
          hasLength(1),
        );
        expect(
          await db.query('day_zone'),
          isNotEmpty,
          reason: 'Native ACK follows the committed SQLite day timeline',
        );
        expect(call.arguments, at);
        if (refuseAck) throw PlatformException(code: 'authored ACK refusal');
        inbox = [];
      }
      return null;
    });
  });
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_zone_refusal',
    );
    await FileLog.write('Authored zone callback barrier');
    messenger.setMockMethodCallHandler(timezone, null);
    messenger.setMockMethodCallHandler(native, null);
  });
  tearDownAll(LocalDb.close);
  Future<void> signal(String method) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      'whoop/day_zone',
      codec.encodeMethodCall(MethodCall(method)),
      (reply) {
        if (reply != null) codec.decodeEnvelope(reply);
        done.complete();
      },
    );
    await done.future;
  }

  test('COV-65 zone inbox commits ordered observations before ACK', () async {
    inbox = [
      null,
      'ignored',
      {'at_ts': at, 'zone_id': 'Asia/Tokyo'},
      {'at_ts': at - 3600, 'zone_id': 'Europe/London'},
    ];
    await DayZoneStore.check('foreground', isIOS: true);
    expect(calls.map((c) => c.method), ['events', 'ack']);
    expect(inbox, isEmpty);
    final rows = await (await LocalDb.instance).query(
      'zone_change',
      orderBy: 'at_ts',
    );
    expect(rows.map((r) => r['zone_id']), [
      'Europe/London',
      'Asia/Tokyo',
      'UTC',
    ]);
  });
  test(
    'COV-65 actual changed callback drains once and ignores other methods',
    () async {
      inbox = [];
      await DayZoneStore.check('install', isIOS: true);
      calls.clear();
      await signal('unrelated');
      expect(calls, isEmpty);
      inbox = [
        {'at_ts': at, 'zone_id': 'Asia/Tokyo'},
      ];
      await signal('changed');
      expect(calls.map((c) => c.method), ['events', 'ack']);
      calls.clear();
      await signal('changed');
      expect(calls.map((c) => c.method), ['events']);
      expect(
        await (await LocalDb.instance).query(
          'zone_change',
          where: 'at_ts=?',
          whereArgs: [at],
        ),
        hasLength(1),
      );
    },
  );
  for (final empty in [true, false]) {
    test(
      'COV-65 ${empty ? 'empty' : 'null'} native inbox keeps current zone without ACK',
      () async {
        inbox = empty ? [] : null;
        await DayZoneStore.check('empty', isIOS: true);
        expect(calls.map((c) => c.method), ['events']);
        expect(
          (await (await LocalDb.instance).query(
            'zone_change',
          )).single['zone_id'],
          'UTC',
        );
      },
    );
  }
  test('COV-65 refused native read preserves inbox and retries', () async {
    refuseEvents = true;
    final retained = List.of(inbox!);
    await DayZoneStore.check('refused', isIOS: true);
    expect(inbox, retained);
    expect(await (await LocalDb.instance).query('zone_change'), isEmpty);
    refuseEvents = false;
    await DayZoneStore.check('retry', isIOS: true);
    expect(calls.map((c) => c.method), ['events', 'events', 'ack']);
    expect(inbox, isEmpty);
  });
  test(
    'COV-65 refused SQLite commit never ACKs and identical retry commits once',
    () async {
      final db = await LocalDb.instance;
      await db.execute(
        "CREATE TRIGGER authored_zone_refusal BEFORE INSERT ON zone_change BEGIN SELECT RAISE(ABORT,'authored refusal'); END",
      );
      final retained = List.of(inbox!);
      await DayZoneStore.check('refused store', isIOS: true);
      expect(calls.map((c) => c.method), ['events']);
      expect(inbox, retained);
      expect(await db.query('zone_change'), isEmpty);
      expect(await db.query('day_zone'), isEmpty);
      await db.execute('DROP TRIGGER authored_zone_refusal');
      await DayZoneStore.check('store retry', isIOS: true);
      expect(calls.map((c) => c.method), ['events', 'events', 'ack']);
      expect(
        await db.query('zone_change', where: 'at_ts=?', whereArgs: [at]),
        hasLength(1),
      );
    },
  );
  test(
    'COV-65 refused ACK preserves committed history and redelivery is idempotent',
    () async {
      refuseAck = true;
      final retained = List.of(inbox!);
      await DayZoneStore.check('refused ack', isIOS: true);
      final db = await LocalDb.instance;
      final before = await db.query('zone_change', orderBy: 'at_ts');
      final days = await db.query('day_zone', orderBy: 'start_ts');
      expect(inbox, retained);
      refuseAck = false;
      await DayZoneStore.check('ack retry', isIOS: true);
      expect(await db.query('zone_change', orderBy: 'at_ts'), before);
      expect(await db.query('day_zone', orderBy: 'start_ts'), days);
      expect(inbox, isEmpty);
      expect(calls.map((c) => c.method), ['events', 'ack', 'events', 'ack']);
    },
  );
  test(
    'COV-65 missing current native timezone does not discard native inbox',
    () async {
      refuseZone = true;
      final retained = List.of(inbox!);
      await DayZoneStore.check('timezone unavailable', isIOS: true);
      expect(calls, isEmpty);
      expect(inbox, retained);
      expect(await (await LocalDb.instance).query('day_zone'), isEmpty);
      refuseZone = false;
      await DayZoneStore.check('timezone retry', isIOS: true);
      expect(inbox, isEmpty);
    },
  );
  test(
    'COV-65 other host records current zone without native inbox IPC',
    () async {
      final retained = List.of(inbox!);
      await DayZoneStore.check('other host', isIOS: false);
      expect(calls, isEmpty);
      expect(inbox, retained);
      expect(
        (await (await LocalDb.instance).query('zone_change')).single['zone_id'],
        'UTC',
      );
    },
  );
}
