// Authored 100 Hz waves and real SQLite refusals; no radio or calibration claims.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'coverage_data_export_handoff_test.dart' show Keychain;
import 'support/coverage_store.dart';

const key = 'live_session_checkpoint';

class CheckpointStore extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  String? refuseWrite, refuseRemove;
  Completer<void>? held, reached;
  String? attempted;
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Future<bool> remove(String name) async {
    if (name == 'flutter.$key') {
      if (refuseRemove == 'throws') {
        throw StateError('synthetic checkpoint remove refusal');
      }
      if (refuseRemove == 'false') return false;
    }
    values.remove(name);
    return true;
  }

  @override
  Future<bool> setValue(String type, String name, Object value) async {
    if (name == 'flutter.$key') {
      attempted = value as String;
      final gate = held;
      if (gate != null) {
        held = null;
        reached!.complete();
        await gate.future;
      }
      if (refuseWrite == 'throws') {
        throw StateError('synthetic checkpoint write refusal');
      }
      if (refuseWrite == 'false') return false;
    }
    values[name] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late CheckpointStore store;
  late SharedPreferencesStorePlatform original;
  setUpAll(() => coverageStore('step-tail-recovery'));
  setUp(() async {
    await resetCoverageStore();
    original = SharedPreferencesStorePlatform.instance;
    store = CheckpointStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    app = AppState.forTesting();
  });
  tearDown(() async {
    store.refuseWrite = store.refuseRemove = null;
    if (store.held != null && !store.held!.isCompleted) store.held!.complete();
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS synthetic_tail_refusal',
    );
    await app.debugFinalizeLivePedometer();
    app.dispose();
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
  });
  tearDownAll(LocalDb.close);
  void feed(DateTime start, {int frames = 16}) {
    final epoch = start.millisecondsSinceEpoch ~/ 1000;
    for (var f = 0; f < frames; f++) {
      app.debugFeedLiveAccel(
        [
          for (var i = 0; i < 200; i++)
            1 + .45 * math.sin(2 * math.pi * 2 * (f * 200 + i) / 100),
        ],
        recTs: epoch + f * 2,
        atMs: (epoch + f * 2) * 1000,
      );
    }
  }

  Future<List<Map<String, Object?>>> rows() async => [
    for (final row in await (await LocalDb.instance).query(
      'live_coverage',
      orderBy: 'start_ts',
    ))
      Map<String, Object?>.of(row)..remove('id'),
  ];
  int sum(Iterable<Map<String, Object?>> rows) =>
      rows.fold(0, (n, r) => n + (r['steps'] as num).toInt());
  List<dynamic> runs(String raw) => (jsonDecode(raw) as Map)['runs'] as List;
  int checkpointTotal(String raw) =>
      runs(raw).fold(0, (n, r) => n + (r[2] as num).toInt());
  Future<void> refuse({String? day}) async => (await LocalDb.instance).execute(
    "CREATE TRIGGER synthetic_tail_refusal BEFORE INSERT ON live_coverage ${day == null ? '' : "WHEN NEW.day='$day'"} BEGIN SELECT RAISE(ABORT,'synthetic tail refusal'); END",
  );
  Future<void> allow() async =>
      (await LocalDb.instance).execute('DROP TRIGGER synthetic_tail_refusal');
  Future<void> restart() async {
    app.dispose();
    app = AppState.forTesting();
  }

  for (final day in ['2021-04-06', '2021-04-07']) {
    test(
      'COV-46 final tail refused on $day remains durable across restart',
      () async {
        feed(DateTime(2021, 4, 6, 23, 59, 45));
        await refuse(day: day);
        await expectLater(app.debugFinalizeLivePedometer(), completes);
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(key)!;
        expect(runs(raw), hasLength(2));
        expect(checkpointTotal(raw), greaterThan(0));
        expect(store.values['flutter.$key'], raw);
        await allow();
        await restart();
        await app.debugFinalizeLivePedometer();
        final saved = await rows();
        expect(saved.map((r) => r['day']), ['2021-04-06', '2021-04-07']);
        expect(sum(saved), checkpointTotal(raw));
        expect(prefs.containsKey(key), false);
        await app.debugFinalizeLivePedometer();
        expect(await rows(), saved);
      },
    );
  }
  for (final failure in ['false', 'throws']) {
    test(
      'COV-46 checkpoint $failure falls back to a successful final database save',
      () async {
        feed(DateTime(2021, 4, 6, 12));
        store.refuseWrite = failure;
        await expectLater(app.debugFinalizeLivePedometer(), completes);
        expect(sum(await rows()), greaterThan(0));
        expect(store.values.containsKey('flutter.$key'), false);
        final saved = await rows();
        store.refuseWrite = null;
        await app.debugFinalizeLivePedometer();
        expect(await rows(), saved);
      },
    );
    test(
      'COV-46 both writers $failure retain the final snapshot for an empty-stream retry',
      () async {
        feed(DateTime(2021, 4, 6, 12));
        store.refuseWrite = failure;
        await refuse();
        await expectLater(app.debugFinalizeLivePedometer(), completes);
        expect(await rows(), isEmpty);
        expect(store.values.containsKey('flutter.$key'), false);
        expect(app.logLines.any((s) => s.contains('retained in memory')), true);
        store.refuseWrite = null;
        await allow();
        await app.debugFinalizeLivePedometer();
        final saved = await rows();
        expect(sum(saved), greaterThan(0));
        await app.debugFinalizeLivePedometer();
        expect(await rows(), saved);
      },
    );
    test(
      'COV-46 refused checkpoint clearing $failure keeps an idempotent recovery copy',
      () async {
        feed(DateTime(2021, 4, 6, 12));
        store.refuseRemove = failure;
        await app.debugFinalizeLivePedometer();
        final raw = store.values['flutter.$key'] as String;
        final saved = await rows();
        expect(sum(saved), checkpointTotal(raw));
        store.refuseRemove = null;
        await restart();
        await app.debugFinalizeLivePedometer();
        expect(await rows(), saved);
        expect(store.values.containsKey('flutter.$key'), false);
      },
    );
  }
  for (final legacy in [false, true]) {
    test(
      'COV-46 a refused ${legacy ? 'legacy' : 'current'} orphan and new final tail both survive',
      () async {
        final start = DateTime(2021, 4, 5, 12).millisecondsSinceEpoch ~/ 1000;
        final old = jsonEncode(
          legacy
              ? {
                  'steps': 100,
                  'samples': 6000,
                  'cover_start_ts': start,
                  'cover_end_ts': start + 60,
                  'first_ingest_ms': start * 1000,
                  'last_ingest_ms': (start + 60) * 1000,
                }
              : {
                  'runs': [
                    [start, start + 60, 100],
                  ],
                },
        );
        await (await SharedPreferences.getInstance()).setString(key, old);
        feed(DateTime(2021, 4, 6, 12));
        await refuse();
        await expectLater(app.debugFinalizeLivePedometer(), completes);
        final raw = store.values['flutter.$key'] as String;
        expect(runs(raw).first, [start, start + 60, 100]);
        expect(runs(raw), hasLength(2));
        await allow();
        await restart();
        await app.debugFinalizeLivePedometer();
        final saved = await rows();
        expect(saved.first['steps'], 100);
        expect(sum(saved), checkpointTotal(raw));
      },
    );
  }
  test(
    'COV-46 held final snapshot cannot clear or overwrite a new counting connection',
    () async {
      feed(DateTime(2021, 4, 6, 12));
      final reached = Completer<void>(), release = Completer<void>();
      store.reached = reached;
      store.held = release;
      final oldFinal = app.debugFinalizeLivePedometer();
      await reached.future.timeout(const Duration(seconds: 3));
      final oldTotal = checkpointTotal(store.attempted!);
      feed(DateTime(2021, 4, 7, 12), frames: 32);
      final newFinal = app.debugFinalizeLivePedometer();
      release.complete();
      await Future.wait([oldFinal, newFinal]);
      await app.debugFinalizeLivePedometer();
      final saved = await rows();
      expect(sum(saved.where((r) => r['day'] == '2021-04-06')), oldTotal);
      expect(
        sum(saved.where((r) => r['day'] == '2021-04-07')),
        greaterThan(oldTotal),
      );
      expect(store.values.containsKey('flutter.$key'), false);
    },
  );
  test(
    'COV-46 a held minute prefix cannot replace its completed final tail',
    () async {
      final reached = Completer<void>(), release = Completer<void>();
      store.reached = reached;
      store.held = release;
      feed(DateTime(2021, 4, 6, 12), frames: 31);
      await reached.future.timeout(const Duration(seconds: 3));
      final prefixTotal = checkpointTotal(store.attempted!);
      // Later frames continue the same connection while its minute snapshot waits.
      final epoch = DateTime(2021, 4, 6, 12).millisecondsSinceEpoch ~/ 1000;
      for (var f = 31; f < 45; f++) {
        app.debugFeedLiveAccel(
          [
            for (var i = 0; i < 200; i++)
              1 + .45 * math.sin(2 * math.pi * 2 * (f * 200 + i) / 100),
          ],
          recTs: epoch + f * 2,
          atMs: (epoch + f * 2) * 1000,
        );
      }
      final finalSave = app.debugFinalizeLivePedometer();
      release.complete();
      await finalSave;
      final saved = await rows();
      expect(sum(saved), greaterThan(prefixTotal));
      // GaitRuns deliberately keeps differing count densities as separate spans.
      // The held minute remains once, alongside the later measured tail.
      expect(saved, hasLength(2));
      expect(saved.first['steps'], prefixTotal);
      expect(saved.last['end_ts'], greaterThan(saved.first['end_ts'] as int));
      await app.debugFinalizeLivePedometer();
      expect(await rows(), saved);
      expect(store.values.containsKey('flutter.$key'), false);
    },
  );
  test(
    'COV-46 full reset waits for a held final writer and cannot resurrect it',
    () async {
      final oldKeys = FlutterSecureStoragePlatform.instance;
      FlutterSecureStoragePlatform.instance = Keychain();
      NotificationService.instance.debugCancel = (_) async {};
      const channel = MethodChannel('whoop/home_region');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() {
        FlutterSecureStoragePlatform.instance = oldKeys;
        NotificationService.instance.debugCancel = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      feed(DateTime(2021, 4, 6, 12));
      final reached = Completer<void>(), release = Completer<void>();
      store.reached = reached;
      store.held = release;
      final finalSave = app.debugFinalizeLivePedometer();
      await reached.future.timeout(const Duration(seconds: 3));
      var resetDone = false;
      final reset = app.resetAllData().then((_) => resetDone = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resetDone, false);
      release.complete();
      await Future.wait([finalSave, reset]);
      expect(await rows(), isEmpty);
      expect(store.values.containsKey('flutter.$key'), false);
      await app.debugFinalizeLivePedometer();
      expect(await rows(), isEmpty);
      expect(store.values.containsKey('flutter.$key'), false);
    },
  );
  for (final invalid in ['not JSON', '{"runs":[[1,"bad",2]]}']) {
    test(
      'COV-46 malformed orphan $invalid keeps original bytes and final tail for retry',
      () async {
        await (await SharedPreferences.getInstance()).setString(key, invalid);
        feed(DateTime(2021, 4, 6, 12));
        await app.debugFinalizeLivePedometer();
        expect(store.values['flutter.$key'], invalid);
        expect(await rows(), isEmpty);
        expect(
          app.logLines.any((s) => s.contains('recovery copy unchanged')),
          true,
        );
        // Simulate a separately completed recovery of the invalid original.
        await Prefs.saveValues({key: null});
        await app.debugFinalizeLivePedometer();
        expect(sum(await rows()), greaterThan(0));
      },
    );
  }
  for (final shape in ['longer-fewer', 'shorter-more', 'superset']) {
    test(
      'COV-48 ambiguous final-step recovery $shape preserves the original copy',
      () async {
        feed(DateTime(2021, 4, 6, 12));
        await refuse();
        await app.debugFinalizeLivePedometer();
        final prefs = await SharedPreferences.getInstance();
        final original = prefs.getString(key)!;
        final originalRuns = runs(original);
        expect(originalRuns, hasLength(1));
        final changed = List<int>.from(originalRuns.single as List);
        if (shape == 'shorter-more') {
          changed[1] -= 1;
          changed[2] += 1;
        } else {
          changed[1] += 60;
          changed[2] += shape == 'superset' ? 5 : -1;
        }
        final recovery = jsonEncode({
          'runs': [changed],
        });
        await prefs.setString(key, recovery);
        await app.debugFinalizeLivePedometer();
        expect(prefs.getString(key), recovery);
        expect(store.values['flutter.$key'], recovery);
        expect(await rows(), isEmpty);
        if (shape != 'superset') {
          expect(
            app.logLines.any(
              (s) => s.contains('Conflicting live-step windows'),
            ),
            true,
          );
          // Resolve with the separately retained authored original; never guess
          // which of two conflicting copies is authoritative in production.
          await prefs.setString(key, original);
        }
        await allow();
        await app.debugFinalizeLivePedometer();
        final saved = await rows();
        expect(
          sum(saved),
          shape == 'superset' ? changed[2] : checkpointTotal(original),
        );
        expect(prefs.containsKey(key), false);
        await app.debugFinalizeLivePedometer();
        expect(await rows(), saved);
      },
    );
  }
}
