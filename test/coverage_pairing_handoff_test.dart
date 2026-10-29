// Real AppState pairing persistence, with only the picker and connection handoff
// scripted. These authored identities never connect to a radio or certify ASK.
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/paired_device.dart';

import 'support/coverage_store.dart';

class _PairApp extends AppState {
  _PairApp() : super.forTesting();
  var opened = 0;
  Map<String, Object?>? rowAtOpen;
  PairedDevice? pairedAtOpen;
  @override
  Future<void> openSession() async {
    opened++;
    pairedAtOpen = paired;
    rowAtOpen = await LocalDb.deviceRow();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('whoop/accessory_setup');
  const id = 'AA:BB:CC:DD:EE:02';
  final service = NotificationService.instance;
  final calls = <String>[];
  late _PairApp app;
  String? picked;
  var refusePicker = false;
  setUpAll(() => coverageStore('pairing-handoff'));
  setUp(() async {
    await resetCoverageStore();
    app = _PairApp();
    calls.clear();
    picked = id;
    refusePicker = false;
    service.invalidatePermissionCache();
    service.debugRequestPermission = () async {
      calls.add('permission');
      return false;
    };
    service.debugProbePermission = () async => false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (refusePicker) {
        throw PlatformException(code: 'synthetic_picker_refusal');
      }
      return picked;
    });
  });
  tearDown(() async {
    app.dispose();
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS synthetic_pairing_refusal',
    );
    service.debugRequestPermission = null;
    service.debugProbePermission = null;
    service.invalidatePermissionCache();
    messenger.setMockMethodCallHandler(channel, null);
  });
  tearDownAll(LocalDb.close);

  Future<void> pair(String entry, {String? serial}) => entry == 'picker'
      ? app.pairViaAccessorySetup(serial: serial)
      : app.pairWith(BluetoothDevice.fromId(id), serial: serial);

  for (final entry in ['picker', 'scan']) {
    for (final explicit in [false, true]) {
      test(
        '$entry pairing persists ${explicit ? 'explicit' : 'observed'} identity before connection, despite permission denial',
        () async {
          app.device.serial = 'SYNTHETIC 456';
          app.device.generation = explicit ? 'gen5' : null;
          await pair(entry, serial: explicit ? '  SYNTHETIC 123  ' : null);
          final label = explicit ? 'SYNTHETIC 123' : 'SYNTHETIC 456';
          final generation = explicit ? 'gen5' : null;
          final prefs = await SharedPreferences.getInstance();
          expect(app.opened, 1);
          expect(app.pairedAtOpen?.remoteId, id);
          expect(app.pairedAtOpen?.serial, label);
          expect(app.pairedAtOpen?.generation, generation);
          expect(app.rowAtOpen?['remote_id'], id);
          expect(app.rowAtOpen?['label'], label);
          expect(app.rowAtOpen?['adapter_id'], generation);
          expect(prefs.getString('paired_remote_id'), id);
          expect(prefs.getString('paired_serial'), label);
          expect(prefs.getString('paired_generation'), generation);
          expect(calls.where((c) => c == 'permission'), hasLength(1));
          expect(
            calls.where((c) => c == 'showPicker'),
            entry == 'picker' ? hasLength(1) : isEmpty,
          );
        },
      );
    }
  }

  for (final result in ['null', 'empty', 'refused']) {
    test('picker $result leaves all pairing copies untouched', () async {
      picked = result == 'null' ? null : '';
      refusePicker = result == 'refused';
      await expectLater(app.pairViaAccessorySetup(), throwsException);
      expect(await LocalDb.deviceRow(), isNull);
      expect(
        (await SharedPreferences.getInstance()).getKeys(),
        isNot(contains('paired_remote_id')),
      );
      expect(app.paired, isNull);
      expect(app.opened, 0);
      expect(calls, ['showPicker']);
    });
  }

  for (final entry in ['picker', 'scan']) {
    test(
      '$entry refused durable identity retains the old pair and retries',
      () async {
        await PairedDevice.save(
          'synthetic-old-band',
          'SYNTHETIC OLD',
          generation: 'gen4',
        );
        app.paired = await PairedDevice.load();
        final before = await LocalDb.deviceRow();
        final db = await LocalDb.instance;
        await db.execute(
          "CREATE TRIGGER synthetic_pairing_refusal BEFORE INSERT ON device "
          "BEGIN SELECT RAISE(ABORT,'synthetic pairing refusal'); END",
        );
        await expectLater(
          pair(entry, serial: 'SYNTHETIC NEW'),
          throwsA(anything),
        );
        expect(await LocalDb.deviceRow(), before);
        expect(app.paired?.remoteId, 'synthetic-old-band');
        expect(
          (await SharedPreferences.getInstance()).getString('paired_remote_id'),
          'synthetic-old-band',
        );
        expect(app.opened, 0);
        expect(calls, isNot(contains('permission')));
        await db.execute('DROP TRIGGER synthetic_pairing_refusal');
        await pair(entry, serial: 'SYNTHETIC NEW');
        expect(app.opened, 1);
        expect(app.pairedAtOpen?.remoteId, id);
        expect(app.pairedAtOpen?.serial, 'SYNTHETIC NEW');
        expect(
          app.pairedAtOpen?.generation,
          isNull,
          reason: 'the new band cannot inherit the earlier generation',
        );
        expect((await PairedDevice.load())?.remoteId, id);
      },
    );
  }

  test(
    'non-iOS pairing capability selects the existing scan fallback',
    () async {
      expect(await app.accessorySetupSupported(), false);
      expect(calls, isEmpty);
      expect(await LocalDb.deviceRow(), isNull);
    },
  );
}
