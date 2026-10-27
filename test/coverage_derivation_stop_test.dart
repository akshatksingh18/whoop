// Cancellation through each real calculation entry point, without a sensor.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/state/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DerivationEngine engine;
  const day = '2026-01-02';
  late int ts;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = (await Directory(
      'build/coverage-remainder/derive-stop',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    ts = localDayStartSec(day)! + 12 * 3600;
    engine = DerivationEngine(background: true);
    await LocalDb.insertRecord(
      RawRecord(
        counter: 1,
        packetType: 47,
        hex: 'synthetic',
        capturedAt: ts * 1000,
        recTs: ts,
      ),
      Sample(
        tsEpoch: ts,
        counter: 1,
        hr: 60,
        rrIntervalsMs: const [1000],
        ax: 0,
        ay: 0,
        az: 1,
      ),
    );
  });
  tearDownAll(LocalDb.close);
  Substrate imported() => Substrate(
    tsSec: [ts],
    hr: [60],
    rrTsMs: [],
    rrMs: [],
    ax: [0],
    ay: [0],
    az: [1],
    spo2Red: [0],
    spo2Ir: [0],
    skinTemp: [0],
    skinContact: [0],
  );

  for (final entry in ['ordinary', 'selected', 'imported', 'rescan']) {
    test(
      '$entry resumes under a new generation, persists only measured inputs and releases the process lock',
      () async {
        DeriveStop.request('an earlier pass stopped');
        final job = switch (entry) {
          'selected' => engine.runDays(const Profile(), {day}),
          'imported' => engine.deriveImportedDays(imported(), const Profile(), {
            day,
          }),
          'rescan' => engine.rescanRecent(const Profile()),
          _ => engine.run(const Profile(), force: true),
        };
        expect(
          await DerivationEngine().runDays(const Profile(), {day}),
          0,
          reason: 'another engine cannot race the same store',
        );
        expect(await job, 1);
        final row = (await LocalDb.dayResult(day))!;
        expect(row['skipped'], 0);
        expect(row['rmssd'], isNull);
        expect(row['readiness'], isNull);
        expect(engine.running, isFalse);
        if (entry != 'imported')
          expect(engine.snapshot()['active_days'], isEmpty);
      },
    );
    test(
      '$entry work stops before writing when its generation is cancelled during the first read',
      () async {
        final job = switch (entry) {
          'selected' => engine.runDays(const Profile(), {day}),
          'imported' => engine.deriveImportedDays(imported(), const Profile(), {
            day,
          }),
          'rescan' => engine.rescanRecent(const Profile()),
          _ => engine.run(const Profile(), force: true),
        };
        DeriveStop.request('synthetic background expiry');
        if (entry == 'rescan') {
          expect(await job, 0);
        } else {
          await expectLater(job, throwsA(isA<DeriveCancelled>()));
        }
        expect(await LocalDb.dayResult(day), isNull);
        expect(await LocalDb.getCursor('baseline_sig'), isNull);
        expect(engine.running, isFalse);
        expect(
          await LocalDb.lastDecodedRecTs(),
          ts,
          reason: 'cancelled work must not prune its retry input',
        );
      },
    );
    test(
      '$entry work cannot revive a cancelled pass between its two compute stages',
      () async {
        var stopped = false;
        engine = DerivationEngine(
          background: true,
          log: (line) {
            if (!stopped && line.startsWith('[derive] day-bundle ')) {
              stopped = true;
              DeriveStop.request('synthetic stop after headline computation');
            }
          },
        );
        final job = switch (entry) {
          'selected' => engine.runDays(const Profile(), {day}),
          'imported' => engine.deriveImportedDays(imported(), const Profile(), {
            day,
          }),
          'rescan' => engine.rescanRecent(const Profile()),
          _ => engine.run(const Profile(), force: true),
        };
        if (entry == 'rescan') {
          expect(await job, 0);
        } else {
          await expectLater(job, throwsA(isA<DeriveCancelled>()));
        }
        expect(
          stopped,
          isTrue,
          reason: 'the test must reach the real first compute stage',
        );
        expect(await LocalDb.dayResult(day), isNull);
        expect(await LocalDb.wakeDayFeatures(day), isNull);
        expect(engine.running, isFalse);
        expect(await LocalDb.lastDecodedRecTs(), ts);
      },
    );
  }
  for (final boundary in ['initial read', 'history decision']) {
    test(
      'rollup cancellation at $boundary preserves its previous status instead of stamping success/failure',
      () async {
        const previous = '{"kind":"ready","synthetic":true}';
        await LocalDb.putBaseline('crossday_status', previous);
        var stopped = false;
        engine = DerivationEngine(
          log: (line) {
            if (boundary == 'history decision' &&
                line.contains('usable day(s) — skip')) {
              stopped = true;
              DeriveStop.request('synthetic rollup stop');
            }
          },
        );
        final job = engine.rebuildCrossDay(const Profile());
        if (boundary == 'initial read') {
          stopped = true;
          DeriveStop.request('synthetic rollup stop');
        }
        await expectLater(job, throwsA(isA<DeriveCancelled>()));
        expect(stopped, isTrue);
        expect(
          (await LocalDb.baseline('crossday_status'))?['payload_json'],
          previous,
        );
        expect(engine.running, isFalse);
      },
    );
  }
}
