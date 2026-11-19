import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/off_lookup.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';

import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class RecordingBrowser extends UrlLauncherPlatform {
  bool accepted = true;
  final calls = <(String, LaunchOptions)>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url, options));
    return accepted;
  }
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('barcode-credit-links', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'saved barcode attribution opens both public links at ${scale}x',
      (tester) async {
        const key = 'authored-barcode';
        const day = '2021-04-06';
        final db = await LocalDb.instance;
        await NutritionDb.putFoodDef(db, {
          ...myFoodDef(
            key: key,
            label: 'Authored barcode meal',
            refGrams: 100,
            unit: 'g',
            kcal: 180,
          ),
          'source': 'barcode',
        });
        final definition = (await NutritionDb.foodDef(db, key))!;
        expect(definition['source'], 'barcode');
        final previous = UrlLauncherPlatform.instance;
        final browser = RecordingBrowser();
        UrlLauncherPlatform.instance = browser;
        addTearDown(() => UrlLauncherPlatform.instance = previous);
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        await localizedPage(
          tester,
          Scaffold(
            body: FoodDetailSheet(def: definition, date: day, meal: 'lunch'),
          ),
          app: app,
          scale: scale,
        );
        expect(find.text(kOffAttribution), findsOneWidget);
        for (final (label, accepted) in [
          ('openfoodfacts.org', false),
          ('Open Database License', true),
        ]) {
          browser.accepted = accepted;
          final link = find.text(label);
          await reveal(tester, link);
          await tester.tap(link);
          await tester.pumpAndSettle();
          expect(find.byType(FoodDetailSheet), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        expect(browser.calls.map((call) => call.$1), [
          'https://openfoodfacts.org',
          'https://opendatacommons.org/licenses/odbl/1-0/',
        ]);
        expect(
          browser.calls.map((call) => call.$2.mode),
          everyElement(PreferredLaunchMode.externalApplication),
        );
        expect(
          browser.calls.map((call) => call.$2.webViewConfiguration.headers),
          everyElement(isEmpty),
        );
        expect(await NutritionDb.foodDef(db, key), definition);
        expect(await NutritionDb.entriesForDay(db, day), isEmpty);
      },
    );
  }
}
