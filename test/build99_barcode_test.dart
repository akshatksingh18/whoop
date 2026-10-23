// Synthetic identifiers and mocked HTTP only; never contacts a service.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openstrap_edge/data/off_lookup.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/barcode_food.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAuditFonts);
  test('invalid barcode text never becomes a path or query', () async {
    SharedPreferences.setMockInitialValues({kOffConsentKey: true});
    await Prefs.ensureLoaded();
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      return http.Response('{}', 404);
    });
    addTearDown(client.close);
    for (final code in [
      '../other',
      '123?private=1',
      '123#fragment',
      '12/34',
      'ABC',
      '１２３',
    ]) {
      expect(
        (await fetchOffProduct(code, client: client)).outcome,
        OffOutcome.notFound,
      );
    }
    expect(calls, 0);
    await fetchOffProduct('0000000000000', client: client);
    expect(calls, 1);
  });
  test('a fresh installation waits for barcode consent', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    expect(offLookupAllowed, isFalse);
  });
  for (final scale in [1.0, 3.1]) {
    testWidgets('barcode disclosure can be read and cancelled at ${scale}x', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({kOffConsentKey: false});
      await Prefs.ensureLoaded();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var finished = false;
      await t.pumpWidget(
        RepaintBoundary(
          key: auditCaptureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () async {
                    expect(await scanFoodProduct(c), isNull);
                    finished = true;
                  },
                  child: const Text('Scan'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Scan'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await captureAuditScroll(t, 'barcode_${scale}x');
      await t.ensureVisible(find.text('Not now'));
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(finished, isTrue);
      expect(offLookupAllowed, isFalse);
      await t.pumpWidget(const SizedBox());
    });
  }
}
