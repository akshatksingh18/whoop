// Real profile/history stores with authored refusals at preference and SQLite boundaries.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Script the installed preference boundary without adding a production dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/compute/streak.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/profile_history.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'support/coverage_store.dart';

class ProfileStore extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  String? refuse;
  Completer<void>? hold;
  Completer<void>? reached;
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
    if (key == 'flutter.local_profile_json') {
      final gate = hold;
      if (gate != null) {
        reached!.complete();
        hold = null;
        await gate.future;
      }
      final failure = refuse;
      refuse = null;
      if (failure == 'throws') throw StateError('synthetic preference refusal');
      if (failure == 'false') return false;
    }
    values[key] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform original;
  late ProfileStore store;
  setUpAll(() => coverageStore('state-storage-controls'));
  setUp(() async {
    await resetCoverageStore();
    original = SharedPreferencesStorePlatform.instance;
    store = ProfileStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  tearDown(() {
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
  });
  tearDownAll(LocalDb.close);
  const profile = {
    'age': 30,
    'height_cm': 170.0,
    'weight_kg': 70.0,
    'sex': 'f',
    'step_goal': 8000,
  };
  for (final hadHistory in [false, true]) {
    for (final failure in ['false', 'throws', 'history']) {
      test(
        'COV-45 profile $failure restores ${hadHistory ? 'existing' : 'absent'} anchors and retries',
        () async {
          final app = AppState.forTesting()..user = {...profile};
          addTearDown(app.dispose);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('local_profile_json', jsonEncode(profile));
          if (hadHistory) {
            await ProfileHistory.record(profile, profile);
            await StepGoals.read(initial: 8000);
          }
          final before = {
            ProfileHistory.key: await CalculationStore.read(ProfileHistory.key),
            StepGoals.key: await CalculationStore.read(StepGoals.key),
          };
          final db = await LocalDb.instance;
          if (failure == 'history') {
            await db.execute(
              '''CREATE TRIGGER synthetic_profile_refusal BEFORE INSERT ON baselines
            WHEN NEW.key = 'calculation:profile.calculation_history'
              AND instr(NEW.payload_json, '"weight_kg":71.25') > 0
            BEGIN SELECT RAISE(ABORT,'synthetic profile history refusal'); END''',
            );
          } else {
            store.refuse = failure;
          }
          try {
            await expectLater(
              app.updateProfile({'weight_kg': 71.25, 'step_goal': 9000}),
              throwsA(
                predicate(
                  (e) => '$e'.contains(switch (failure) {
                    'history' => 'synthetic profile history refusal',
                    'false' => 'Profile could not save',
                    _ => 'synthetic preference refusal',
                  }),
                ),
              ),
            );
            expect(app.user, profile);
            expect(app.insightsRevision.value, 0);
            await prefs.reload();
            expect(jsonDecode(prefs.getString('local_profile_json')!), profile);
            for (final e in before.entries) {
              expect(await CalculationStore.read(e.key), e.value);
            }
          } finally {
            await db.execute(
              'DROP TRIGGER IF EXISTS synthetic_profile_refusal',
            );
          }
          final saved = await app.updateProfile({
            'weight_kg': 71.25,
            'step_goal': 9000,
          });
          expect(saved['weight_kg'], 71.25);
          expect(saved['step_goal'], 9000);
          expect(app.insightsRevision.value, 1);
          expect(await CalculationStore.read(StepGoals.key), contains('9000'));
        },
      );
    }
  }
  test(
    'COV-45 queued profile updates retain each preceding successful field',
    () async {
      final app = AppState.forTesting()..user = {...profile};
      addTearDown(app.dispose);
      final reached = Completer<void>(), release = Completer<void>();
      store.reached = reached;
      store.hold = release;
      final first = app.updateProfile({'weight_kg': 71.25});
      await reached.future;
      final second = app.updateProfile({'step_goal': 9000});
      release.complete();
      final results = await Future.wait([first, second]);
      expect(results.first['step_goal'], 8000);
      expect(results.last['weight_kg'], 71.25);
      expect(results.last['step_goal'], 9000);
      expect(app.user, results.last);
      expect(app.insightsRevision.value, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('local_profile_json')!), results.last);
    },
  );
}
