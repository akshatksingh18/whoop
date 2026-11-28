// Real event envelopes/persistence and AppState write ownership;no sensor capture.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import '../ble/durable_boundary_test.dart' show until;
import '../support/coverage_store.dart';

Future<void> event(int id, int ts) async {
  final bytes = Uint8List(12)..[0] = 0x30;
  ByteData.sublistView(bytes)
    ..setUint16(2, id, Endian.little)
    ..setUint32(4, ts, Endian.little);
  final decoded = p.parseEvent(bytes)!;
  expect(decoded.eventId, id);
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  await LocalDb.insertEvent(id, ts, hex);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('live-battery-toggle-history', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final charging in [false, true]) {
    for (final shape in ['prior', 'inside', 'later-close', 'zero-edge']) {
      test(
        'retained ${charging ? 'charging' : 'wrist-off'} $shape closes only at an observed boundary',
        () async {
          const lo = 1617714000, hi = lo + 100;
          final off = charging ? p.EventId.chargingOn : p.EventId.wristOff;
          final on = charging ? p.EventId.chargingOff : p.EventId.wristOn;
          final prior = shape == 'prior' || shape == 'zero-edge';
          await event(off, prior ? lo - 10 : lo + 10);
          if (shape == 'later-close') await event(on, hi + 10);
          if (shape == 'zero-edge') await event(on, lo);
          final db = await LocalDb.instance;
          final raw = await db.query('events', orderBy: 'ts');
          final mirror = await db.query('band_events', orderBy: 'ts');
          Future<List<List<int>>> read(int a, int b) => charging
              ? StepCoverageStore.chargingSpans(a, b)
              : StepCoverageStore.wristOffSpans(a, b);
          expect(
            await read(lo, hi),
            shape == 'zero-edge'
                ? <List<int>>[]
                : [
                    [prior ? lo : lo + 10, hi],
                  ],
          );
          if (shape == 'later-close') {
            expect(await read(hi, hi + 20), [
              [hi, hi + 10],
            ]);
          }
          expect(await read(lo, lo), isEmpty);
          expect(await read(hi, lo), isEmpty);
          expect(await db.query('events', orderBy: 'ts'), raw);
          expect(await db.query('band_events', orderBy: 'ts'), mirror);
        },
      );
    }
  }
  for (final newOwner in [false, true]) {
    test(
      'refused live battery write preserves prior evidence and publishes only a later durable sample;new owner=$newOwner',
      () async {
        final db = await LocalDb.instance;
        await LocalDb.insertBandBatterySample(
          ts: 1617714000,
          batteryPct: 80,
          source: 'authored-retained',
        );
        final before = await db.query('band_battery', orderBy: 'ts');
        final oldSink = NotificationCenter.instance.presentSink;
        NotificationCenter.instance.presentSink =
            (e, {bool allowPermissionPrompt = true}) async => false;
        addTearDown(() => NotificationCenter.instance.presentSink = oldSink);
        var app = AppState.forTesting();
        addTearDown(() => app.dispose());
        await db.execute(
          "CREATE TRIGGER authored_live_battery_refusal BEFORE INSERT ON band_battery BEGIN SELECT RAISE(ABORT,'authored live battery refusal'); END",
        );
        try {
          app.device
            ..batteryPct = 73
            ..charging = false
            ..wristOn = true;
          app.engine.onState(app.device);
          await until(
            () => app.logLines.any((s) => s.contains('sample could not save:')),
          );
          expect(
            app.logLines.join('\n'),
            contains('authored live battery refusal'),
          );
          expect(app.batteryRevision.value, 0);
          expect(await db.query('band_battery', orderBy: 'ts'), before);
        } finally {
          await db.execute('DROP TRIGGER authored_live_battery_refusal');
        }
        if (newOwner) {
          app.dispose();
          app = AppState.forTesting();
        }
        app.device
          ..batteryPct = newOwner ? 73 : 72
          ..charging = false
          ..wristOn = true;
        app.engine.onState(app.device);
        await until(() => app.batteryRevision.value == 1);
        final rows = await db.query('band_battery', orderBy: 'ts');
        expect(rows.first, before.single);
        expect(rows, hasLength(2));
        expect(rows.last['battery_pct'], newOwner ? 73.0 : 72.0);
        expect(rows.last['source'], 'device_state');
        app.engine.onState(app.device);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(app.batteryRevision.value, 1);
        expect(await db.query('band_battery', orderBy: 'ts'), rows);
      },
    );
  }
}
