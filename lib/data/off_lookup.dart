// A barcode, looked up against Open Food Facts.
//
// THIS IS AN OUTBOUND NETWORK CALL, and this app's whole position is that it
// makes none it did not ask you about. So it is shaped like the only other one
// that touches your data (ui2/activity/tiles.dart, the map basemap):
//   · [offLookupAllowed] gates every entry point here, so turning it off in
//     Settings stops the lookup dead — there is no code path that fetches
//     around it;
//   · it is user-initiated, one product per scan, never a batch and never a
//     background job;
//   · what leaves is the barcode. Not the meal, not the day, not who you are;
//   · a hit is cached in `food_def`, so scanning the same packet twice asks
//     openfoodfacts.org once;
//   · a real User-Agent, which their terms require;
//   · [kOffAttribution], which the caller MUST render wherever the numbers
//     land. ODbL data without the credit is a licence breach, not a design
//     choice.
//
// THE DATA IS OFTEN WRONG. Measured live, roughly 6% of products carrying
// nutrition data hold a physically impossible value, rising to about 20% among
// the most-scanned ones — Maggi Noodles filed with 2500 g of salt per 100 g,
// Balaji Wheels with 355,942, Parle-G with 3.4 kcal. The dominant failure is
// sodium in milligrams typed into the salt-in-grams box. It is a data-entry
// failure mode, not an Indian one, and OFF's own validators miss the quiet
// half: Tata Salt returns 0 g of salt per 100 g with no error tag at all.
//
// So nothing here is trusted on arrival. [gateNutrients] is the whole point of
// this file: a value that fails a physical check arrives ABSENT, and an absent
// value leaves its box EMPTY. Never a zero, never a guess — the same rule the
// rest of the app runs on, applied to somebody else's typing.
//
// And a scanned number is INPUT, not a measurement. OFF's own terms say the
// data must not be used for medical purposes; [FoodSource.barcode] exists so
// it can never be ranked as a panel the user read off a pack.

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../state/prefs.dart';

// ══════════════════ LICENCE ══════════════════

/// Required on any surface that shows numbers this file produced. ODbL asks
/// for attribution "reasonably calculated" to make a viewer aware; one line
/// where the values appear is that.
const kOffAttribution =
    'Contains information from Open Food Facts, available under the Open '
    'Database License.';

const kOffSite = 'https://openfoodfacts.org';
const kOffLicence = 'https://opendatacommons.org/licenses/odbl/1-0/';

/// Their terms' first requirement. A generic Dart user-agent is the one thing
/// guaranteed to get an app blocked.
const _userAgent =
    'OpenStrap/1.0 (+https://github.com/OpenStrap/edge; local-first health '
    'app; one product lookup per barcode the user scans)';

// ══════════════════ CONSENT ══════════════════

/// Whether openfoodfacts.org may be asked about a barcode.
///
/// Default ON — with the update check, and unlike every path that would send
/// something ABOUT YOU (crash reports, health contribution), which stay off
/// until asked. The line between them is what leaves: this sends a number
/// printed on a packet by its manufacturer, and a scanner that refuses to scan
/// until you have found a settings toggle is a scanner nobody uses.
///
/// Still persisted and still revocable from Settings › Privacy, and the food
/// log is entirely usable with it off: typing the numbers off the pack was
/// always the fallback and still is.
///
/// Default-on and fail-closed are not in tension, because they answer two
/// different questions. `Prefs.getBool`'s fallback covers BOTH "loaded, no key
/// yet" (a fresh install — default on, deliberately) and "prefs never loaded"
/// (we cannot see the answer). Reading the second as the first sends the
/// barcode of someone who explicitly opted out, which is the one thing a
/// revocable consent must never do. So storage has to be there before the
/// default counts.
const kOffConsentKey = 'nutrition.barcode_lookup';

bool get offLookupAllowed =>
    Prefs.loaded && Prefs.getBool(kOffConsentKey, true);

/// Record the choice, and say whether it was actually RECORDED.
///
/// The one write in this app that is not fire-and-forget. SharedPreferences
/// updates its cache optimistically and never rolls it back, so a revocation
/// whose disk write fails reads as off for the rest of the session and is
/// silently back ON at the next launch — the app sending a barcode for
/// somebody who turned it off, which is the single thing a revocable consent
/// must never do. In-session it is already fail-closed (the cache is off, so
/// nothing goes out); what the caller has to do with a `false` here is TELL
/// the person, because it will not survive a restart.
Future<bool> setOffLookupAllowed(bool on) async {
  try {
    return await Prefs.setBoolAcked(kOffConsentKey, on);
  } catch (_) {
    return false;
  }
}

// ══════════════════ RESULT ══════════════════

enum OffOutcome {
  /// A product came back. Its numbers may still be mostly absent — only about
  /// 12% of random products carry all seven core fields (34% among popular
  /// ones), and fibre fails first. A PART-FILLED form is the normal case.
  ok,

  /// That barcode is not in the database. Common, and not an error.
  notFound,

  /// The record carries `data_quality_errors_tags`. OFF itself says these
  /// numbers are wrong, so none of them are offered.
  flagged,

  /// No network, a timeout, or one of their 503s — which they serve
  /// independently of your request rate.
  unreachable,

  /// [offLookupAllowed] is off. Nothing was sent.
  refused,
}

/// One product, already gated. Every nutrient is PER 100 g — see
/// [parseOffProduct] for why there is only one basis.
class OffProduct {
  const OffProduct({
    required this.barcode,
    required this.label,
    this.brand = '',
    this.servingG,
    this.servingLabel = '',
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fibreG,
    this.sugarG,
    this.satFatG,
    this.sodiumMg,
  });

  final String barcode;
  final String label;
  final String brand;

  /// One serving in grams, when the record states one plausibly. This is the
  /// portion the form is pre-filled at; 100 g when it is unknown.
  final double? servingG;

  /// What the pack calls that serving ('30 g', '2 biscuits'). Shown, never
  /// parsed.
  final String servingLabel;

  final double? kcal, proteinG, carbsG, fatG, fibreG, sugarG, satFatG, sodiumMg;

  /// Nothing survived the gates. The label is still worth having — it logs as
  /// a bare eating occasion, which is a complete entry.
  bool get isBare =>
      kcal == null &&
      proteinG == null &&
      carbsG == null &&
      fatG == null &&
      fibreG == null;

  /// The grams this form opens at.
  double get defaultPortionG => servingG ?? 100;

  /// The five numbers the log form has boxes for, scaled to [grams].
  ///
  /// Absent stays absent — scaling null is null, not zero.
  ({
    double? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fibreG,
  }) forPortion(double grams) {
    final f = grams / 100;
    double? s(double? v) => v == null ? null : v * f;
    return (
      kcal: s(kcal),
      proteinG: s(proteinG),
      carbsG: s(carbsG),
      fatG: s(fatG),
      fibreG: s(fibreG),
    );
  }

  /// The `food_def` row this caches as. The dictionary table already has a
  /// column for every field OFF returns, so the cache is that table and not a
  /// second one.
  Map<String, Object?> toDefRow() => {
        'key': barcode,
        'label': label,
        'brand': brand,
        'serving_g': servingG,
        'serving_label': servingLabel,
        'kcal_100': kcal,
        'protein_g_100': proteinG,
        'carbs_g_100': carbsG,
        'fat_g_100': fatG,
        'fibre_g_100': fibreG,
        'sugar_g_100': sugarG,
        'sat_fat_g_100': satFatG,
        'sodium_mg_100': sodiumMg,
        'source': 'barcode',
      };

  static OffProduct fromDefRow(Map<String, Object?> r) {
    double? d(String k) => (r[k] as num?)?.toDouble();
    return OffProduct(
      barcode: r['key'] as String,
      label: r['label'] as String,
      brand: (r['brand'] as String?) ?? '',
      servingG: d('serving_g'),
      servingLabel: (r['serving_label'] as String?) ?? '',
      kcal: d('kcal_100'),
      proteinG: d('protein_g_100'),
      carbsG: d('carbs_g_100'),
      fatG: d('fat_g_100'),
      fibreG: d('fibre_g_100'),
      sugarG: d('sugar_g_100'),
      satFatG: d('sat_fat_g_100'),
      sodiumMg: d('sodium_mg_100'),
    );
  }
}

class OffResult {
  const OffResult(this.outcome, [this.product]);
  final OffOutcome outcome;
  final OffProduct? product;
}

// ══════════════════ THE GATES ══════════════════

/// Energy from a pure fat, per 100 g. Nothing edible exceeds it.
const _maxKcal100 = 900.0;

/// Sum of protein + carbohydrate + fat, per 100 g. 100 with 5 g of slack for
/// rounding and for the water/ash a label rounds away.
const _maxMacroSum = 105.0;

/// Pure sodium chloride is 39.3 g of sodium per 100 g. A gram over that is
/// arithmetic nobody can defend.
///
/// This IS the mandated salt gate, in its tighter form. OFF derives each of
/// salt and sodium from the other (salt = sodium × 2.5), so reading sodium and
/// capping it here rejects everything a `salt ≤ 100 g/100 g` rule would and a
/// band of physically impossible records besides.
const _maxSodiumG100 = 40.0;

/// How far energy may sit from what its own macros imply, as a fraction of the
/// Atwater estimate. A calibration knob, not a law: labels round, fibre and
/// polyols carry energy Atwater does not count, and 25% is wide enough to let
/// an honest label through while still catching a decimal point in the wrong
/// place.
const _atwaterTolerance = 0.25;

/// The floor on that comparison's denominator, so a diet drink (Atwater 0,
/// labelled 3 kcal) is not rejected for being 100% off zero.
const _atwaterFloorKcal = 50.0;

/// Every physical check, in one pure place.
///
/// Keys in and out: kcal, protein, carbs, fat, fibre, sugar, satFat, sodiumMg.
/// A key whose value fails its check comes back NULL. It never comes back
/// zeroed and it never comes back rounded into range — the form leaves that
/// box empty and the user types what the pack says.
///
/// Three of these are the mandated set: the macro sum, the salt ceiling, and
/// energy against Atwater. The rest are the same idea applied per field.
Map<String, double?> gateNutrients(Map<String, double?> raw) {
  double? v(String k) {
    final x = raw[k];
    if (x == null || !x.isFinite || x < 0) return null;
    return x;
  }

  // Per-field ceilings first, because they are self-contained: a single macro
  // over 100 g per 100 g is impossible on its own evidence.
  var kcal = v('kcal');
  if (kcal != null && kcal > _maxKcal100) kcal = null;

  var protein = v('protein');
  var carbs = v('carbs');
  var fat = v('fat');
  var fibre = v('fibre');
  var sugar = v('sugar');
  var satFat = v('satFat');
  for (final f in [protein, carbs, fat, fibre, sugar, satFat]) {
    if (f != null && f > 100) {
      // One impossible macro means the macro block was mis-entered; which
      // field is anyone's guess, so none of them are offered.
      protein = carbs = fat = fibre = sugar = satFat = null;
      break;
    }
  }

  // The macro sum. Mutually inconsistent, and again unattributable — drop the
  // three, and with them the two that are subsets of carbs and fat.
  if (protein != null && carbs != null && fat != null) {
    if (protein + carbs + fat > _maxMacroSum) {
      protein = carbs = fat = sugar = satFat = null;
    }
  }

  // Salt. THE dominant error: sodium in milligrams typed into a field that is
  // grams. `sodiumMg` arrives here already converted from OFF's grams.
  var sodiumMg = v('sodiumMg');
  if (sodiumMg != null && sodiumMg > _maxSodiumG100 * 1000) sodiumMg = null;

  // Energy against its own macros. Only meaningful once the macros have
  // survived on their own, and when it fails ENERGY is the field dropped: the
  // macros already passed a physical check and are mutually consistent in
  // mass, so the odd figure out is the one derived from them.
  if (kcal != null && protein != null && carbs != null && fat != null) {
    final atwater = 4 * protein + 4 * carbs + 9 * fat;
    final tolerance =
        _atwaterTolerance * math.max(atwater, _atwaterFloorKcal);
    if ((kcal - atwater).abs() > tolerance) kcal = null;
  }

  return {
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fibre': fibre,
    'sugar': sugar,
    'satFat': satFat,
    'sodiumMg': sodiumMg,
  };
}

// ══════════════════ PARSE ══════════════════

/// One `api/v2/product` body → a gated product. PURE, so the gates are
/// testable against the records that actually broke them.
///
/// ONE BASIS. OFF states nutrition per 100 g, per serving, or both. A record
/// that only states per serving is converted to per 100 g when it also states
/// the serving's mass — and DISCARDED when it does not, because a number whose
/// basis we cannot name is a number we cannot scale, and quietly treating it
/// as per-100 g is exactly the silent fabrication this file exists to stop.
/// The label survives; it logs as a bare occasion.
OffResult parseOffProduct(String barcode, Map<String, Object?> body) {
  final p = body['product'];
  if (p is! Map) return const OffResult(OffOutcome.notFound);

  final errors = p['data_quality_errors_tags'];
  if (errors is List && errors.isNotEmpty) {
    return const OffResult(OffOutcome.flagged);
  }

  final label = _text(p['product_name']).isNotEmpty
      ? _text(p['product_name'])
      : _text(p['product_name_en']);
  if (label.isEmpty) return const OffResult(OffOutcome.notFound);

  final brand = _text(p['brands']).split(',').first.trim();
  final servingG = _plausibleServing(_number(p['serving_quantity']));
  final servingLabel = _text(p['serving_size']);

  final n = p['nutriments'];
  final nut = n is Map ? n : const {};

  // Per 100 g if it is there; otherwise per serving rebased, which needs the
  // serving's mass.
  double? at(String key, String suffix) => _number(nut['$key$suffix']);
  // Probed on energy and the macros only, never on sodium. OFF derives sodium
  // from salt and can file it per 100 g while the panel itself is per serving;
  // letting that decide the basis would read `_100g` for everything and come
  // back with a product that has salt and nothing else.
  var have100 = false;
  for (final k in const [
    'energy-kcal',
    'proteins',
    'carbohydrates',
    'fat',
  ]) {
    if (at(k, '_100g') != null) {
      have100 = true;
      break;
    }
  }
  final double? rebase = have100
      ? 1
      : (servingG != null && servingG > 0 ? 100 / servingG : null);
  final suffix = have100 ? '_100g' : '_serving';

  final raw = <String, double?>{};
  if (rebase != null) {
    for (final e in _keys.entries) {
      final v = at(e.value, suffix);
      raw[e.key] = v == null ? null : v * rebase;
    }
    // OFF files sodium in GRAMS. Everything downstream of here is milligrams.
    final sodium = raw['sodiumMg'];
    if (sodium != null) raw['sodiumMg'] = sodium * 1000;
  }

  final g = gateNutrients(raw);
  return OffResult(
    OffOutcome.ok,
    OffProduct(
      barcode: barcode,
      label: label,
      brand: brand,
      servingG: servingG,
      servingLabel: servingLabel,
      kcal: g['kcal'],
      proteinG: g['protein'],
      carbsG: g['carbs'],
      fatG: g['fat'],
      fibreG: g['fibre'],
      sugarG: g['sugar'],
      satFatG: g['satFat'],
      sodiumMg: g['sodiumMg'],
    ),
  );
}

/// Our field name → OFF's nutriment name.
const _keys = <String, String>{
  'kcal': 'energy-kcal',
  'protein': 'proteins',
  'carbs': 'carbohydrates',
  'fat': 'fat',
  'fibre': 'fiber',
  'sugar': 'sugars',
  'satFat': 'saturated-fat',
  'sodiumMg': 'sodium',
};

/// A serving is only usable as a portion if it is a mass a person could eat.
/// Anything else is left absent and the form opens at 100 g.
double? _plausibleServing(double? g) =>
    (g != null && g.isFinite && g >= 1 && g <= 2000) ? g : null;

String _text(Object? v) => v is String ? v.trim() : '';

/// OFF returns numbers as numbers, and sometimes as strings.
double? _number(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

// ══════════════════ FETCH ══════════════════

/// One GET, one barcode.
///
/// Deliberately not the `openfoodfacts` package: this is a single documented
/// endpoint with a `fields=` narrowing, and the package is a whole write/auth/
/// prices/folksonomy client with its own model layer we would immediately map
/// away from. The precedent in this repo is the same shape (tiles.dart).
///
/// SEARCH IS NOT USED, on purpose. `cgi/search.pl` is effectively deprecated
/// and 503s, and search.openfoodfacts.org serves an index last built in
/// October 2024. Barcode lookup only.
///
/// Their read limit is 15 requests a minute per user. A person scanning
/// packets cannot reach it, and a repeat scan is served from `food_def`
/// without a request at all, so there is no throttle here to go stale.
Future<OffResult> fetchOffProduct(String barcode,
    {http.Client? client}) async {
  if (!offLookupAllowed) return const OffResult(OffOutcome.refused);
  final code = barcode.trim();
  if (code.isEmpty || code.length > 20) {
    return const OffResult(OffOutcome.notFound);
  }
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final res = await c.get(
      Uri.parse('https://world.openfoodfacts.org/api/v2/product/$code'
          '?fields=product_name,product_name_en,brands,serving_quantity,'
          'serving_size,data_quality_errors_tags,nutriments'),
      headers: const {'User-Agent': _userAgent},
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode == 404) return const OffResult(OffOutcome.notFound);
    // 503 arrives independently of anything we did, so it reads as
    // unreachable rather than as a missing product.
    if (res.statusCode != 200) return const OffResult(OffOutcome.unreachable);
    final body = jsonDecode(res.body);
    if (body is! Map<String, Object?>) {
      return const OffResult(OffOutcome.unreachable);
    }
    return parseOffProduct(code, body);
  } catch (_) {
    return const OffResult(OffOutcome.unreachable);
  } finally {
    if (owned) c.close();
  }
}
