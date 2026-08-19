// The gates on Open Food Facts data.
//
// This is the load-bearing test for the barcode scan. About 6% of OFF products
// carrying nutrition data hold a physically impossible value, rising to ~20%
// among the most-scanned ones, and the app's founding rule is that an absent
// number stays absent rather than becoming a zero or a guess. So every case
// here asks the same two questions: did the impossible value get dropped, and
// did the possible ones survive next to it.
//
// The clean fixtures are REAL bodies from world.openfoodfacts.org/api/v2 —
// Parle-G 8901719101090 and Nutella 3017624010701, fetched with the key set
// this app requests. The broken ones carry the values measured live on the
// named products (Maggi salt 2500, Sunfeast Yippee 2955, Balaji Wheels
// 355,942, Parle-G energy 3.4 kcal) inside the same envelope. Nothing here
// touches the network: a test that needs openfoodfacts.org to be up is a test
// that goes red for somebody else's outage.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/off_lookup.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An api/v2 body, in the shape the endpoint actually returns.
Map<String, Object?> body({
  String name = 'Test product',
  String brands = '',
  Object? servingQuantity,
  String servingSize = '',
  List<String> errors = const [],
  Map<String, Object?> nutriments = const {},
}) => {
      'code': '0000000000000',
      'status': 1,
      'product': {
        'product_name': name,
        'brands': brands,
        'serving_quantity': ?servingQuantity,
        if (servingSize.isNotEmpty) 'serving_size': servingSize,
        'data_quality_errors_tags': errors,
        'nutriments': nutriments,
      },
    };

/// The real Parle-G record, trimmed to the fields this app asks for.
Map<String, Object?> parleG({double? salt, double? kcal}) => body(
      name: 'Parle-g Glucose Biscuits',
      brands: 'Parle',
      nutriments: {
        'energy-kcal_100g': kcal ?? 454,
        'proteins_100g': 6.8,
        'carbohydrates_100g': 77.3,
        'fat_100g': 13,
        'sugars_100g': 25,
        'saturated-fat_100g': 6,
        'salt_100g': salt ?? 0.7,
        // OFF derives one from the other; salt = sodium x 2.5.
        'sodium_100g': (salt ?? 0.7) / 2.5,
      },
    );

void main() {
  group('a clean record comes through intact', () {
    test('Parle-G, as the API actually serves it', () {
      final r = parseOffProduct('8901719101090', parleG());
      expect(r.outcome, OffOutcome.ok);
      final p = r.product!;
      expect(p.label, 'Parle-g Glucose Biscuits');
      expect(p.brand, 'Parle');
      expect(p.kcal, 454);
      expect(p.proteinG, 6.8);
      expect(p.carbsG, 77.3);
      expect(p.fatG, 13);
      // Fibre is the field that fails first, and this record has none. It is
      // absent, not zero.
      expect(p.fibreG, isNull);
      expect(p.isBare, isFalse);
    });

    test('sodium arrives in milligrams, because OFF files it in grams', () {
      final p = parseOffProduct('8901719101090', parleG()).product!;
      expect(p.sodiumMg, closeTo(280, 0.001));
    });

    test('Nutella: 539 kcal against 6.3P/57.5C/30.9F clears Atwater', () {
      final r = parseOffProduct(
        '3017624010701',
        body(
          name: 'Nutella',
          brands: 'Ferrero',
          nutriments: const {
            'energy-kcal_100g': 539,
            'proteins_100g': 6.3,
            'carbohydrates_100g': 57.5,
            'fat_100g': 30.9,
            'sugars_100g': 56.3,
            'saturated-fat_100g': 10.6,
            'sodium_100g': 0.043,
          },
        ),
      );
      expect(r.product!.kcal, 539);
    });
  });

  group('the values that were actually served, and are impossible', () {
    test('Maggi Noodles: salt 2500 g per 100 g is dropped, not scaled', () {
      // 2500 g of salt is 1000 g of sodium in 100 g of noodles. The rest of
      // the record is fine and must survive.
      final p = parseOffProduct('x', parleG(salt: 2500)).product!;
      expect(p.sodiumMg, isNull);
      expect(p.carbsG, 77.3, reason: 'one bad field is not a bad product');
      expect(p.kcal, 454);
    });

    test('Sunfeast Yippee: salt 2955', () {
      expect(parseOffProduct('x', parleG(salt: 2955)).product!.sodiumMg,
          isNull);
    });

    test('Balaji Wheels: salt 355,942', () {
      expect(parseOffProduct('x', parleG(salt: 355942)).product!.sodiumMg,
          isNull);
    });

    test('Parle-G energy 3.4 kcal against its own macros', () {
      // Atwater on 6.8P/77.3C/13F is ~454 kcal. 3.4 is not a rounding.
      final p = parseOffProduct('x', parleG(kcal: 3.4)).product!;
      expect(p.kcal, isNull);
      expect(p.proteinG, 6.8,
          reason: 'the macros passed a physical check; energy is the odd one');
      expect(p.carbsG, 77.3);
      expect(p.fatG, 13);
    });

    test('a field arrives ABSENT, never zeroed', () {
      final p = parseOffProduct('x', parleG(kcal: 3.4)).product!;
      expect(p.kcal, isNot(0));
      expect(p.kcal, isNull);
    });
  });

  group('the mandated gates', () {
    test('macros summing past 105 g per 100 g take each other down', () {
      final g = gateNutrients(const {
        'protein': 30.0,
        'carbs': 60.0,
        'fat': 30.0, // 120 g of solids in 100 g
        'fibre': 2.0,
        'sugar': 10.0,
        'satFat': 5.0,
      });
      expect(g['protein'], isNull);
      expect(g['carbs'], isNull);
      expect(g['fat'], isNull);
      expect(g['sugar'], isNull, reason: 'a subset of carbs that cannot stand');
      expect(g['satFat'], isNull, reason: 'a subset of fat that cannot stand');
      // Fibre is not in the sum and is independently plausible.
      expect(g['fibre'], 2.0);
    });

    test('105 exactly is inside the gate, 105.1 is outside', () {
      expect(
        gateNutrients(const {'protein': 5.0, 'carbs': 60.0, 'fat': 40.0})[
            'carbs'],
        60.0,
      );
      expect(
        gateNutrients(const {'protein': 5.1, 'carbs': 60.0, 'fat': 40.0})[
            'carbs'],
        isNull,
      );
    });

    test('salt: a value beyond pure sodium chloride cannot be real', () {
      expect(gateNutrients(const {'sodiumMg': 39000.0})['sodiumMg'], 39000.0);
      expect(gateNutrients(const {'sodiumMg': 41000.0})['sodiumMg'], isNull);
    });

    test('energy inside 25% of Atwater survives, outside it does not', () {
      // Atwater = 4*10 + 4*50 + 9*10 = 330. Tolerance 82.5.
      Map<String, double?> at(double kcal) => gateNutrients({
            'kcal': kcal,
            'protein': 10.0,
            'carbs': 50.0,
            'fat': 10.0,
          });
      expect(at(330)['kcal'], 330);
      expect(at(400)['kcal'], 400, reason: 'labels round and fibre carries');
      expect(at(500)['kcal'], isNull);
      expect(at(120)['kcal'], isNull);
    });

    test('a zero-energy drink is not rejected for being 100% off zero', () {
      // Atwater 0, labelled 3 kcal. Without the floor on the denominator this
      // is an infinite relative error and every diet drink loses its energy.
      final g = gateNutrients(const {
        'kcal': 3.0,
        'protein': 0.0,
        'carbs': 0.0,
        'fat': 0.0,
      });
      expect(g['kcal'], 3.0);
    });

    test('energy beyond a pure fat is impossible on its own', () {
      expect(gateNutrients(const {'kcal': 899.0})['kcal'], 899.0);
      expect(gateNutrients(const {'kcal': 901.0})['kcal'], isNull);
    });

    test('negative and non-finite values are absences', () {
      final g = gateNutrients({
        'kcal': -10.0,
        'protein': double.nan,
        'carbs': double.infinity,
      });
      expect(g['kcal'], isNull);
      expect(g['protein'], isNull);
      expect(g['carbs'], isNull);
    });

    test('a single macro past 100 g takes the macro block with it', () {
      // Balaji Wheels' 355,942 in a macro field rather than salt.
      final g = gateNutrients(const {'protein': 355942.0, 'carbs': 50.0});
      expect(g['protein'], isNull);
      expect(g['carbs'], isNull, reason: 'which field was mistyped is a guess');
    });
  });

  group('a flagged record offers nothing', () {
    test('data_quality_errors_tags rejects the whole product', () {
      final r = parseOffProduct(
        'x',
        body(
          name: 'Something wrong',
          errors: const ['en:nutrition-value-total-over-105'],
          nutriments: const {
            'energy-kcal_100g': 200,
            'proteins_100g': 5,
          },
        ),
      );
      expect(r.outcome, OffOutcome.flagged);
      expect(r.product, isNull);
    });

    test('an empty tag list is not a flag', () {
      expect(parseOffProduct('x', parleG()).outcome, OffOutcome.ok);
    });
  });

  group('a part-filled scan is the normal case', () {
    test('a product with a name and nothing else is still a product', () {
      final r = parseOffProduct('x', body(name: 'Mystery snack'));
      expect(r.outcome, OffOutcome.ok);
      expect(r.product!.label, 'Mystery snack');
      expect(r.product!.isBare, isTrue,
          reason: 'it logs as a bare eating occasion, which is a valid entry');
    });

    test('no product at all is notFound, not an empty product', () {
      expect(parseOffProduct('x', const {'status': 0}).outcome,
          OffOutcome.notFound);
    });

    test('a product with no name is not a usable answer', () {
      expect(parseOffProduct('x', body(name: '')).outcome,
          OffOutcome.notFound);
    });
  });

  group('portion maths', () {
    test('per 100 g scales, and absent stays absent', () {
      final p = parseOffProduct('x', parleG()).product!;
      final v = p.forPortion(50);
      expect(v.kcal, closeTo(227, 0.001));
      expect(v.carbsG, closeTo(38.65, 0.001));
      expect(v.fibreG, isNull, reason: 'scaling nothing is not zero');
    });

    test('the form opens at the pack serving when there is a plausible one',
        () {
      final withServing = parseOffProduct(
        'x',
        body(
          name: 'Biscuits',
          servingQuantity: '33',
          servingSize: '33 g',
          nutriments: const {'energy-kcal_100g': 400},
        ),
      ).product!;
      expect(withServing.servingG, 33);
      expect(withServing.defaultPortionG, 33);
      expect(withServing.forPortion(withServing.defaultPortionG).kcal,
          closeTo(132, 0.001));
    });

    test('an implausible serving mass is ignored and 100 g is the basis', () {
      final p = parseOffProduct(
        'x',
        body(
          name: 'Jar',
          servingQuantity: 40000,
          nutriments: const {'energy-kcal_100g': 400},
        ),
      ).product!;
      expect(p.servingG, isNull);
      expect(p.defaultPortionG, 100);
    });

    test('a per-SERVING-only record is rebased, not read as per 100 g', () {
      // 110 kcal in a 28 g serving is 392.9 kcal per 100 g. Reading the
      // serving figure as a per-100 g one would understate it 3.6x.
      //
      // The macros have to be a real 28 g serving, not a plausible-looking
      // one: 3P/28C/2F is 33 g of solids inside 28 g, and rebasing it puts the
      // sum past the 105 g gate, which drops all three. The gate caught the
      // fixture before it caught a product, which is the gate working.
      final p = parseOffProduct(
        'x',
        body(
          name: 'Cereal',
          servingQuantity: 28,
          nutriments: const {
            'energy-kcal_serving': 110,
            'proteins_serving': 2,
            'carbohydrates_serving': 22,
            'fat_serving': 1,
          },
        ),
      ).product!;
      expect(p.kcal, closeTo(392.86, 0.01));
      expect(p.carbsG, closeTo(78.57, 0.01));
      // And one serving gets its label back.
      expect(p.forPortion(28).kcal, closeTo(110, 0.01));
    });

    test('a stray sodium_100g does not hijack a per-serving panel', () {
      // OFF derives sodium from salt and can file it per 100 g while the panel
      // is per serving. If that decided the basis, every macro would be read
      // at `_100g`, find nothing, and the product would come back carrying
      // salt and nothing else.
      final p = parseOffProduct(
        'x',
        body(
          name: 'Soup',
          servingQuantity: 250,
          nutriments: const {
            'sodium_100g': 0.3,
            'energy-kcal_serving': 120,
            'proteins_serving': 4,
            'carbohydrates_serving': 15,
            'fat_serving': 5,
          },
        ),
      ).product!;
      expect(p.kcal, closeTo(48, 0.01));
      expect(p.proteinG, closeTo(1.6, 0.01));
      expect(p.isBare, isFalse);
    });

    test('per-serving with no serving mass states nothing at all', () {
      // The basis cannot be named, so treating it as per-100 g would be a
      // fabrication. The label survives; the numbers do not.
      final p = parseOffProduct(
        'x',
        body(
          name: 'Sachet',
          nutriments: const {'energy-kcal_serving': 150},
        ),
      ).product!;
      expect(p.kcal, isNull);
      expect(p.isBare, isTrue);
    });
  });

  group('the cache round-trips through food_def', () {
    test('every field survives the dictionary row', () {
      final p = parseOffProduct('8901719101090', parleG()).product!;
      final back = OffProduct.fromDefRow(p.toDefRow());
      expect(back.barcode, p.barcode);
      expect(back.label, p.label);
      expect(back.brand, p.brand);
      expect(back.kcal, p.kcal);
      expect(back.proteinG, p.proteinG);
      expect(back.carbsG, p.carbsG);
      expect(back.fatG, p.fatG);
      expect(back.fibreG, p.fibreG);
      expect(back.sodiumMg, p.sodiumMg);
    });

    test('it caches as barcode, never as verified', () {
      final row = parseOffProduct('x', parleG()).product!.toDefRow();
      expect(row['source'], 'barcode');
    });
  });

  group('the consent gate', () {
    // Order matters: Prefs caches its SharedPreferences instance on first load
    // and never reloads, so the unloaded case has to be read before anything
    // mocks a store in.
    test('storage we cannot read is a refusal, not the default', () async {
      // Nothing has loaded Prefs. The default is ON, but an unreadable store
      // is not evidence of a fresh install — it is equally the phone of
      // somebody who turned this OFF, and their barcode must not go out on a
      // guess.
      expect(Prefs.loaded, isFalse);
      expect(offLookupAllowed, isFalse);
      final r = await fetchOffProduct('8901719101090');
      expect(r.outcome, OffOutcome.refused);
    });

    test('a fresh install may look up', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(const {});
      await Prefs.ensureLoaded();
      // Loaded, and the key has never been written: THIS is the fresh install,
      // and it is on. What leaves is the barcode, never anything about the
      // person holding it.
      expect(Prefs.loaded, isTrue);
      expect(offLookupAllowed, isTrue);
    });

    test('a lookup refuses before any request once it is turned off', () async {
      // Written through the instance the test above loaded — Prefs caches it
      // for the process, so a second `setMockInitialValues` would not be seen.
      setOffLookupAllowed(false);
      expect(offLookupAllowed, isFalse);
      final r = await fetchOffProduct('8901719101090');
      expect(r.outcome, OffOutcome.refused);
    });
  });
}
