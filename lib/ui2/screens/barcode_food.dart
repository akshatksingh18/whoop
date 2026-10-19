// Barcode lookups for the Food screens: the consent asked once, the scan, the
// Open Food Facts lookup with its local cache, and the licence credit shown
// wherever those numbers appear.
//
// A SCAN PART-FILLS. That is the normal case, not a failure: only about 12% of
// products carry all seven core fields, and everything Open Food Facts hands
// over goes through `gateNutrients` first, which drops a physically impossible
// value rather than round it into range. Every box the lookup could not stand
// behind is left EMPTY for the user to type. None of it is a measurement —
// see `FoodSource.barcode`.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../data/db.dart';
import '../../data/nutrition_store.dart';
import '../../data/off_lookup.dart';
import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'scan_barcode.dart';

/// The shared camera/consent/cache path, independent of the old occasion UI.
Future<OffResult?> scanFoodProduct(
  BuildContext c, {
  VoidCallback? onManual,
  bool cacheProduct = true,
}) async {
  if (!offLookupAllowed) {
    final agreed = await _askLookupConsent(c);
    if (agreed != true || !c.mounted) return null;
    await setOffLookupAllowed(true);
    if (!c.mounted) return null;
  }
  final code = await scanBarcode(c, onManual: onManual);
  if (code == null || !c.mounted) return null;
  return lookupBarcodeFood(code, cacheProduct: cacheProduct);
}

Future<OffResult> lookupBarcodeFood(
  String code, {
  bool cacheProduct = true,
  http.Client? client,
}) async {
  final db = await LocalDb.instance;
  final cached = await NutritionDb.foodDef(db, code);
  if (cached != null && cached['source'] == 'barcode') {
    return OffResult(OffOutcome.ok, OffProduct.fromDefRow(cached));
  }
  final res = await fetchOffProduct(code, client: client);
  if (cacheProduct && res.product != null) {
    final product = res.product!;
    await NutritionDb.putFoodDef(db, product.toDefRow());
  }
  return res;
}

/// The disclosure, before the first lookup ever happens.
///
/// Asked once, then remembered; revocable from Settings › Privacy. It states
/// what leaves the phone — the barcode, and nothing else — because this app's
/// whole claim is that nothing does unless you said so.
Future<bool?> _askLookupConsent(BuildContext c) => showModalBottomSheet<bool>(
  context: c,
  sheetAnimationStyle: sheetMotion(c),
  backgroundColor: P.of(c).card,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
  ),
  builder: (s) {
    final p = P.of(s);
    final l = AppLocalizations.of(s);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l?.logFoodConsentTitle ?? 'Look barcodes up online?',
              style: F.t2.copyWith(color: p.ink),
            ),
            const SizedBox(height: S.x4),
            Text(
              l?.logFoodConsentBody1 ??
                  'A scan sends the barcode to openfoodfacts.org, a free, '
                      'open food database. They see the barcode and your IP '
                      'address. Nothing about you, your meals or your health '
                      'leaves this phone, and a barcode you have scanned before '
                      'is answered from your own copy without asking them again.',
              style: F.body.copyWith(color: p.ink2, height: 1.5),
            ),
            const SizedBox(height: S.x3),
            Text(
              l?.logFoodConsentBody2 ??
                  'Their numbers are typed in by the public and a fair few of '
                      'them are wrong, so anything that fails a sanity check is '
                      'left blank rather than filled in. Everything it does fill '
                      'in is yours to edit before you save.',
              style: F.body.copyWith(color: p.ink2, height: 1.5),
            ),
            const SizedBox(height: S.x3),
            Text(
              l?.logFoodConsentBody3 ??
                  'You can turn this back off in Settings › Privacy. Typing '
                      'the numbers off the pack works either way.',
              style: F.cap.copyWith(color: p.ink3, height: 1.45),
            ),
            const SizedBox(height: S.x5),
            BigButton(
              l?.logFoodAllowLookups ?? 'Allow lookups',
              color: C.domFood,
              onTap: () => Navigator.of(s).pop(true),
            ),
            const SizedBox(height: S.x3),
            BigButton(
              l?.logFoodNotNow ?? 'Not now',
              color: C.domFood,
              soft: true,
              onTap: () => Navigator.of(s).pop(false),
            ),
          ],
        ),
      ),
    );
  },
);

/// The ODbL credit, wherever Open Food Facts numbers are shown. Both links
/// are the licence's, not decoration — the notice names the source and the
/// terms, and a user has to be able to reach both.
Widget offCredit() => const _OffCredit();

class _OffCredit extends StatelessWidget {
  const _OffCredit();

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kOffAttribution,
          style: F.cap.copyWith(color: p.ink3, height: 1.45),
        ),
        const SizedBox(height: S.x1),
        // Wrap, not Row: "Open Database License" beside a URL runs off the
        // right of the sheet at accessibility text sizes, and a link that has
        // overflowed is a link nobody can follow.
        const Wrap(
          spacing: S.x3,
          runSpacing: S.x1,
          children: [
            _Link('openfoodfacts.org', kOffSite),
            _Link('Open Database License', kOffLicence),
          ],
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.url);
  final String label, url;

  @override
  Widget build(BuildContext c) => Pressable(
    semanticLabel:
        AppLocalizations.of(c)?.logFoodOpensInBrowser(label) ??
        '$label, opens in your browser',
    onTap: () =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    child: Text(
      label,
      style: F.cap.copyWith(
        color: P.of(c).on(C.domFood),
        decoration: TextDecoration.underline,
      ),
    ),
  );
}
