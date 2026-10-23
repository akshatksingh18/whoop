// Refused persistence must not advance the onboarding route in memory.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

class _Store extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  bool refuse = true;
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (refuse) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('setup button explains a refused save and stays available', (
    t,
  ) async {
    final original = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = _Store();
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting()..initialized = true;
    addTearDown(() async {
      app.dispose();
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.resetStatic();
      await Prefs.ensureLoaded();
    });
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const WelcomeScreen(),
        ),
      ),
    );
    await t.tap(find.text('Set up my band'));
    await t.pumpAndSettle();
    expect(
      find.text('Setup could not continue. Please try again.'),
      findsOneWidget,
    );
    expect(app.route, AppRoute.welcome);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  for (final imported in [false, true]) {
    test(
      '${imported ? 'Imported' : 'New'} onboarding refuses and retries durably',
      () async {
        final original = SharedPreferencesStorePlatform.instance;
        final store = _Store();
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();
        await Prefs.ensureLoaded();
        final app = AppState.forTesting()..initialized = true;
        addTearDown(() async {
          app.dispose();
          SharedPreferencesStorePlatform.instance = original;
          SharedPreferences.resetStatic();
          await Prefs.ensureLoaded();
        });
        Future<void> choose() =>
            imported ? app.completeImportOnboard() : app.chooseNewUser();
        expect(app.route, AppRoute.welcome);
        await expectLater(choose(), throwsStateError);
        expect(app.route, AppRoute.welcome);
        expect(
          (await SharedPreferences.getInstance()).getString(
            'onboarding_choice',
          ),
          isNull,
        );
        store.refuse = false;
        await choose();
        expect(app.route, AppRoute.pairing);
        expect(
          store.values['flutter.onboarding_choice'],
          imported ? 'imported' : 'new',
        );
      },
    );
  }
}
