// Consent and product-cache boundaries use authored storage and mocked HTTP.
// No camera frame or network request leaves the test process.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/off_lookup.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/barcode_food.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_settings_controls_test.dart' show Store;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';

class ConsentStore extends Store {
  String mode = 'ready';
  Completer<void>? reached, release;
  final writes = <Object>[];
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.$kOffConsentKey') {
      writes.add(value);
      if (value == true) {
        reached?.complete();
        await release?.future;
        if (mode == 'throws') throw StateError('authored grant refusal');
        if (mode == 'false') return false;
      }
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late ConsentStore store;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('barcode-persistence-boundaries');
  });
  setUp(() async {
    await resetCoverageStore();
    previous = SharedPreferencesStorePlatform.instance;
    store = ConsentStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  tearDown(() async {
    SharedPreferencesStorePlatform.instance = previous;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  tearDownAll(LocalDb.close);

  Future<Completer<OffResult?>> openConsent(WidgetTester t) async {
    final result = Completer<OffResult?>();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async => result.complete(await scanFoodProduct(c)),
              child: const Text('Authored scan'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Authored scan'));
    await t.pumpAndSettle();
    expect(find.text('Look barcodes up online?'), findsOneWidget);
    return result;
  }

  for (final mode in ['false', 'throws']) {
    testWidgets(
      'a $mode consent write reports refusal and never opens the camera',
      (t) async {
        store.mode = mode;
        final result = await openConsent(t);
        await t.ensureVisible(find.text('Allow lookups'));
        await t.tap(find.text('Allow lookups'));
        await t.pumpAndSettle();
        expect(await result.future, isNull);
        expect(
          find.textContaining('Barcode permission could not be saved.'),
          findsOneWidget,
        );
        expect(find.text('Scan the barcode'), findsNothing);
        expect(offLookupAllowed, false);
        expect(store.writes, [true, false]);
        expect(store.values['flutter.$kOffConsentKey'], false);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('food_def'),
          ),
          isEmpty,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final dismiss in [false, true]) {
    testWidgets(
      'consent ${dismiss ? 'Back dismissal' : 'Not now'} does not persist a grant',
      (t) async {
        final result = await openConsent(t);
        if (dismiss) {
          Navigator.of(t.element(find.text('Look barcodes up online?'))).pop();
        } else {
          await t.ensureVisible(find.text('Not now'));
          await t.tap(find.text('Not now'));
        }
        await t.pumpAndSettle();
        expect(await result.future, isNull);
        expect(offLookupAllowed, false);
        expect(store.writes, isEmpty);
        expect(find.text('Scan the barcode'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'leaving the host during an acknowledged grant never opens a stale camera route',
    (t) async {
      store.reached = Completer<void>();
      store.release = Completer<void>();
      final result = await openConsent(t);
      await t.ensureVisible(find.text('Allow lookups'));
      await t.tap(find.text('Allow lookups'));
      await t.pumpAndSettle();
      expect(store.reached!.isCompleted, true);
      expect(result.isCompleted, false);
      await t.pumpWidget(const SizedBox());
      store.release!.complete();
      await t.pumpAndSettle();
      expect(await result.future, isNull);
      expect(offLookupAllowed, true);
      expect(store.writes, [true]);
      expect(t.takeException(), isNull);
    },
  );

  for (final cache in [false, true]) {
    test(
      'successful lookup ${cache ? 'caches only its definition' : 'leaves persistence to review'} with missing nutrients intact',
      () async {
        await setOffLookupAllowed(true);
        var requests = 0;
        final client = MockClient((request) async {
          requests++;
          expect(request.url.path, contains('0000000000000'));
          return http.Response(
            jsonEncode({
              'status': 1,
              'product': {
                'product_name': 'Authored beans',
                'nutriments': {'energy-kcal_100g': 120, 'proteins_100g': 8},
              },
            }),
            200,
          );
        });
        addTearDown(client.close);
        final result = await lookupBarcodeFood(
          '0000000000000',
          cacheProduct: cache,
          client: client,
        );
        expect(result.outcome, OffOutcome.ok);
        expect(result.product!.carbsG, isNull);
        expect(requests, 1);
        final db = await LocalDb.instance;
        final saved = await NutritionDb.foodDef(db, '0000000000000');
        expect(saved != null, cache);
        expect(await db.query('food_entry'), isEmpty);
        if (cache) {
          await setOffLookupAllowed(false);
          final offline = await lookupBarcodeFood(
            '0000000000000',
            client: client,
          );
          expect(offline.outcome, OffOutcome.ok);
          expect(offline.product!.carbsG, isNull);
          expect(
            requests,
            1,
            reason: 'A saved definition works without a new external lookup',
          );
        }
      },
    );
  }
}
