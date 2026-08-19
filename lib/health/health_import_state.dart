// When each health-store read last brought something back — and the name of
// the store to say it about.
//
// WHY THIS EXISTS AT ALL. The button on Workout and on Edit profile says
// "Import from Apple Health" the first time and "Refresh" after that, and the
// only honest way to know which is our own record of a read that worked.
// Asking the store is not an option: on iOS HealthKit deliberately never
// reveals whether READ was granted, so `hasPermissions` comes back null or
// false either way and `requestAuthorization` returns true even on a denial
// (the same trap phone_pedometer.dart documents). A label driven off either
// would say "Import" forever on the platform this feature is mostly for.
//
// So the flag means what the word means: something was actually read and
// stored. A grant with an empty store leaves it unset, and the button keeps
// saying "Import" — which is true, because nothing has been imported.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whichever store this platform has. Named, because "your phone" is not a
/// thing a user can go and check a permission on.
String get storeName => Platform.isIOS ? 'Apple Health' : 'Health Connect';

/// Which store this is, for the two places the platforms genuinely differ.
///
/// Health Connect has NO date-of-birth and NO sex record — not a permission
/// this app skipped, the record types do not exist — and it keeps workout
/// ROUTES behind a restricted permission this app has not applied for. Both
/// sentences have to change together, and both split on the same test
/// [storeName] uses, so the copy and the store name can never disagree.
bool get isAppleHealth => Platform.isIOS;

/// The two things a user can bring in, each with its own consent and its own
/// button. Values are the preference keys and are not renamed lightly — a new
/// key reads as "never imported" and puts the first-run word back on the
/// button for someone who has been refreshing for months.
enum HealthImport {
  profile('health_import_profile_at'),
  workouts('health_import_workouts_at');

  const HealthImport(this.key);
  final String key;
}

/// When [what] last brought something back, or null for never.
///
/// Never throws. Preferences are unavailable in a widget test and on a device
/// whose storage is locked, and both of those are "we do not know", which
/// renders as the first-run label rather than as an error nobody can act on.
Future<DateTime?> lastImportAt(HealthImport what) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final sec = p.getInt(what.key);
    return sec == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sec * 1000);
  } catch (e) {
    debugPrint('[health_import] read ${what.key}: $e');
    return null;
  }
}

/// Record that [what] just brought something back.
///
/// Call it ONLY when rows actually arrived. A denied read on iOS comes back as
/// an empty list rather than as an error, so marking a zero-row read as done
/// would flip the button to "Refresh" for someone who said no.
Future<void> markImported(HealthImport what, {DateTime? now}) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setInt(
      what.key,
      (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
    );
  } catch (e) {
    debugPrint('[health_import] write ${what.key}: $e');
  }
}

/// The verb for a button that does the same read twice. "Import from Apple
/// Health" before anything has arrived, "Refresh from Apple Health" after —
/// same control, and the second word is a promise that it re-reads rather than
/// stacking a second copy.
String importLabel(DateTime? last) =>
    '${last == null ? 'Import' : 'Refresh'} from $storeName';
