// Authored scanner callbacks and HTTP responses only. Default sockets are
// refused, so a lost mock scope cannot contact a barcode service.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/off_lookup.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart'
    show WhoopTextField;
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class _NoSockets extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('This authored test permits mocked HTTP only.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('barcode-label-fallback');
  });
  setUp(() async {
    await resetCoverageStore();
    await setOffLookupAllowed(true);
  });
  tearDownAll(LocalDb.close);

  for (final outcome in [
    'missing',
    'flagged',
    'unreachable',
    'revoked',
    'partial',
  ]) {
    testWidgets(
      'a $outcome library lookup preserves review and manual-entry boundaries',
      (t) async {
        final previous = HttpOverrides.current;
        HttpOverrides.global = _NoSockets();
        addTearDown(() => HttpOverrides.global = previous);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        for (final suffix in ['method', 'event', 'deviceOrientation']) {
          final channel = MethodChannel(
            'dev.steenbakker.mobile_scanner/scanner/$suffix',
          );
          messenger.setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'start') {
              throw PlatformException(code: 'PERMISSION_ERROR');
            }
            return null;
          });
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        }
        var calls = 0, finished = false;
        Map<String, Object?>? saved;
        await localizedPage(
          t,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await http.runWithClient(
                    () => FoodEditor.scanAndSave(context),
                    () => MockClient((request) async {
                      calls++;
                      expectSync(request.method, 'GET');
                      expectSync(request.url.path, endsWith('/0000000000000'));
                      if (outcome == 'missing') {
                        return http.Response('{}', 404);
                      }
                      if (outcome == 'unreachable') {
                        return http.Response('{}', 503);
                      }
                      return http.Response(
                        jsonEncode({
                          'product': {
                            'product_name': 'Authored partial food',
                            'serving_quantity': 50,
                            if (outcome == 'flagged')
                              'data_quality_errors_tags': [
                                'authored-invalid-panel',
                              ],
                            'nutriments': {'energy-kcal_100g': 200},
                          },
                        }),
                        200,
                      );
                    }),
                  );
                  finished = true;
                },
                child: const Text('Start authored scan'),
              ),
            ),
          ),
        );
        await t.tap(find.text('Start authored scan'));
        await flush(t);
        expect(find.byType(MobileScanner), findsOneWidget);
        if (outcome == 'revoked') {
          await t.runAsync(() => setOffLookupAllowed(false));
        }
        t.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
          BarcodeCapture(barcodes: [Barcode(rawValue: '0000000000000')]),
        );
        await flush(t);
        expect(calls, outcome == 'revoked' ? 0 : 1);
        final db = await LocalDb.instance;
        expect(await t.runAsync(() => db.query('food_def')), isEmpty);
        expect(await t.runAsync(() => db.query('food_entry')), isEmpty);
        if (outcome == 'partial') {
          final editor = t.widget<FoodEditor>(find.byType(FoodEditor));
          expect(editor.reviewBarcode, true);
          expect(editor.existing!['label'], 'Authored partial food');
          expect(editor.existing!['kcal_100'], 200);
          expect(editor.existing!['carbs_g_100'], isNull);
        } else {
          final reason = switch (outcome) {
            'missing' => 'This barcode is not in Open Food Facts yet.',
            'flagged' =>
              'This product is flagged as incorrect; its numbers were not used.',
            'unreachable' =>
              'The lookup could not connect. Saved barcode foods still work offline.',
            _ => 'Barcode lookup is off.',
          };
          expect(find.text('Add from the label'), findsOneWidget);
          expect(find.text(reason), findsOneWidget);
          if (outcome == 'missing' || outcome == 'revoked') {
            Navigator.of(t.element(find.text(reason))).pop();
            await flush(t);
            expect(finished, true);
            expect(saved, isNull);
            return;
          }
          await t.ensureVisible(find.text('Create a food'));
          await t.tap(find.text('Create a food'));
          await flush(t);
          final editor = t.widget<FoodEditor>(find.byType(FoodEditor));
          expect(editor.reviewBarcode, false);
          expect(editor.existing, isNull);
          final calories = find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is WhoopTextField && w.label == 'Calories (kcal)',
            ),
            matching: find.byType(TextField),
          );
          expect(t.widget<TextField>(calories).controller!.text, isEmpty);
        }
        Navigator.of(t.element(find.byType(FoodEditor))).pop();
        await flush(t);
        expect(finished, true);
        expect(saved, isNull);
        expect(await t.runAsync(() => db.query('food_def')), isEmpty);
        expect(await t.runAsync(() => db.query('food_entry')), isEmpty);
      },
    );
  }
}
