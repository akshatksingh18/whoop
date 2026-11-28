// Bound an actual SQLite restore at the preference mirror before zone install.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/compute/streak.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/day_zone_rules.dart';
import 'package:whoop_companion/data/day_zone_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/prefs.dart';

import '../support/coverage_store.dart';

class HeldMirror extends SharedPreferencesStorePlatform {
  static const key = 'flutter.steps.goal_history';
  final values = <String, Object>{'flutter.authored-unrelated': 'keep'};
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == HeldMirror.key && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    values[key] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('restore-wipe-mirror-owner', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final reset in [false, true]) {
    test(
      'restore at the calculation mirror with a concurrent wipe: $reset',
      () async {
        const day = '2021-04-06';
        const history =
            '{"from":"2021-04-06","targets":{"2021-04-06":6000},"earned":{}}';
        final instant =
            DateTime.utc(2021, 4, 6, 12).millisecondsSinceEpoch ~/ 1000;
        await DayZoneStore.observe([
          ZoneChange(instant, 'Europe/Berlin'),
        ], throughSec: instant);
        final zones = DayClock.snapshot();
        expect(DayClock.days, isNotEmpty);
        await CalculationStore.write(StepGoals.key, history);
        await JournalStore.put(day, '["rest"]', 'Authored restore row');
        final source = File(await LocalDb.exportCopy());
        final bytes = await source.readAsBytes();
        await LocalDb.wipeAll();

        final oldStore = SharedPreferencesStorePlatform.instance;
        final store = HeldMirror();
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();
        await Prefs.ensureLoaded();
        Future<int>? wipe;
        final restore = BackupImportStore.importFromFile(source.path);
        final outcome = reset
            ? expectLater(
                restore,
                throwsA(
                  isA<DbImportException>()
                      .having(
                        (e) => e.cause.toString(),
                        'reason',
                        contains('Restore stopped because your data was reset'),
                      )
                      .having(
                        (e) => e.records,
                        'committed before wipe',
                        greaterThan(0),
                      ),
                ),
              )
            : expectLater(restore, completion(isNotEmpty));
        try {
          await store.entered.future.timeout(const Duration(seconds: 3));
          expect(await JournalStore.entries(date: day), hasLength(1));
          expect(DayClock.days, isEmpty);
          if (reset) wipe = LocalDb.wipeAll();
          store.release.complete();
          await outcome;
          await wipe;
          if (reset) {
            expect(await JournalStore.entries(date: day), isEmpty);
            expect(
              await MetricSeriesStore.baseline('calculation:${StepGoals.key}'),
              isNull,
            );
            expect(store.values[HeldMirror.key], isNull);
            expect(DayClock.days, isEmpty);
            await BackupImportStore.importFromFile(source.path);
          }
          expect(
            (await JournalStore.entries(date: day)).single['note'],
            'Authored restore row',
          );
          expect(await CalculationStore.read(StepGoals.key), history);
          expect(store.values[HeldMirror.key], history);
          expect(store.values['flutter.authored-unrelated'], 'keep');
          expect(DayClock.snapshot(), zones);
          expect(await source.readAsBytes(), bytes);
        } finally {
          if (!store.release.isCompleted) store.release.complete();
          try {
            await outcome;
            await wipe;
          } finally {
            SharedPreferencesStorePlatform.instance = oldStore;
            SharedPreferences.resetStatic();
            await Prefs.ensureLoaded();
          }
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
