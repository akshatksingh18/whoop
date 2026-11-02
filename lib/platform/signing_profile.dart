// The installed signing profile's expiry, read from inside the app.
//
// A free Apple Personal Team profile lasts seven days, and when it lapses the
// app stops launching — so on the sideloaded personal build the expiry is the
// one date that matters more than any metric. Sideloadly embeds the profile it
// signed with as `embedded.mobileprovision` in the app bundle, beside the
// executable. The file is a CMS envelope around a plain XML plist; the plist
// is readable as text without verifying the signature, which is all a display
// needs (iOS itself enforces the real expiry).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// `ExpirationDate` from a provisioning profile's bytes, or null when there is
/// none to find (not a profile, a truncated file, an unparseable date).
///
/// Latin-1, not UTF-8: the CMS wrapper around the plist is binary DER, and a
/// strict UTF-8 decode would throw on it before reaching the XML.
DateTime? parseProvisionExpiry(List<int> bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final m = RegExp(r'<key>ExpirationDate</key>\s*<date>([^<]+)</date>')
      .firstMatch(text);
  if (m == null) return null;
  return DateTime.tryParse(m.group(1)!.trim());
}

/// The installed profile's expiry, or null off iOS, on a build with no
/// embedded profile (simulator, App Store), or when it cannot be read.
Future<DateTime?> readSigningExpiry() async {
  if (!Platform.isIOS) return null;
  try {
    final f = File(p.join(
        p.dirname(Platform.resolvedExecutable), 'embedded.mobileprovision'));
    if (!await f.exists()) return null;
    return parseProvisionExpiry(await f.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// How long before expiry each alert fires. 48 h then 24 h: the Windows
/// health check owns the earlier warnings, and these two are the phone's own
/// last calls while a USB/Wi-Fi refresh is still easy.
const List<int> kSigningAlertHours = [48, 24];

/// Which expiry alerts to arm now: one per [kSigningAlertHours] entry whose
/// moment is still in the future. An alert whose moment has already passed is
/// dropped rather than fired late — the Status screen shows the live figure.
List<({int hoursBefore, DateTime at})> signingAlertPlan(
    DateTime? expiry, DateTime now) {
  if (expiry == null) return const [];
  return [
    for (final h in kSigningAlertHours)
      if (expiry.subtract(Duration(hours: h)).isAfter(now))
        (hoursBefore: h, at: expiry.subtract(Duration(hours: h))),
  ];
}
