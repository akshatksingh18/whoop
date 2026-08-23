// PairedDevice — the LOCAL record of the band the user paired.
//
// LOCAL ONLY — there is no server. This survived the cloud excision (it used to
// live alongside BackendConfig/Session in sync/config.dart, both deleted).
//
// IT IS A TABLE NOW, not two SharedPreferences scalars. Prefs could hold
// exactly one band, carried no state beside the id, and could not be joined to
// anything — while `decoded_onehz` / `decoded_rr` / `samples` have been keyed
// by `device_id` since schema 47 with nothing on the other end of that key.
// The `device` table (schema 49) is that other end, and it can hold N rows.
//
// THE PREFS PAIR IS KEPT AS A MIRROR OF THE PRIMARY BAND, deliberately:
//  * The table lives in a database that can be quarantined and rebuilt
//    (`_openOrRebuild`) and that "Delete everything" empties. Losing a band's
//    identity to either of those means the user has to re-pair for no reason
//    they can see.
//  * `load()` is the FIRST line of app start-up, so the fallback is also the
//    thing that heals it: a table with no primary row and a mirror that has one
//    puts the row back.
// The table WINS whenever it has the row, so there is no ambiguity about which
// is authoritative — the mirror only ever answers when the table is silent.
//
// ponytail: the mirror carries the PRIMARY only. A second device lives in the
// table alone and does not survive a rebuild; give it its own mirror the day
// one can actually be paired, or stop rebuilding databases.

import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';

/// The `SourceTier` a wrist band sits on (the enum name in
/// `ui2/profile/devices.dart` — measurement quality, which is the only thing
/// that decides precedence between two sources).
const String kBandSourceTier = 'wristOptical';

/// The band the user paired. Persisted so we auto-reconnect on every launch.
class PairedDevice {
  static const String _kRemoteId = 'paired_remote_id';
  static const String _kSerial = 'paired_serial';

  final String remoteId; // BLE remote id (iOS: per-install UUID; Android: MAC)
  final String? serial;
  PairedDevice(this.remoteId, this.serial);

  static Future<PairedDevice?> load() async {
    final row = await LocalDb.deviceRow();
    final id = row?['remote_id'] as String?;
    if (id != null && id.isNotEmpty) {
      // Sanitize on read: drop any garbled value (e.g. "?*" junk persisted by
      // an older build's HELLO content-scan) so it can never reach the UI.
      return PairedDevice(id, cleanDeviceLabel(row?['label'] as String?));
    }
    // No row: either this install predates the table, or the database was
    // rebuilt/wiped under a band that is still paired. Same repair either way —
    // the prefs mirror is the only other copy, and putting it back IS the
    // migration. A user mid-upgrade never re-pairs.
    final prefs = await SharedPreferences.getInstance();
    final mirrored = prefs.getString(_kRemoteId);
    if (mirrored == null || mirrored.isEmpty) return null;
    final serial = cleanDeviceLabel(prefs.getString(_kSerial));
    await LocalDb.upsertDevice(
      remoteId: mirrored,
      label: serial,
      tier: kBandSourceTier,
    );
    return PairedDevice(mirrored, serial);
  }

  /// Persist the primary band. [adapterId] is the registry's `BandEntry.id`
  /// (`gen4` / `gen5`) when the link has said which band this is — omitted, it
  /// leaves whatever the row already knows rather than blanking it, and a row
  /// that has never been told keeps NULL, which every per-family metric reads
  /// as a refusal instead of assuming gen4.
  static Future<void> save(
    String remoteId,
    String? serial, {
    String? adapterId,
  }) async {
    final clean = cleanDeviceLabel(serial);
    await LocalDb.upsertDevice(
      adapterId: adapterId,
      remoteId: remoteId,
      label: clean,
      tier: kBandSourceTier,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRemoteId, remoteId);
    if (clean != null) {
      await prefs.setString(_kSerial, clean);
    } else {
      await prefs.remove(_kSerial); // never persist junk
    }
  }

  /// Forget the primary band. BOTH copies, or the mirror puts it straight back
  /// on the next launch — and the measurements it wrote are untouched, which is
  /// what the forget dialog promises.
  static Future<void> clear() async {
    await LocalDb.deleteDevice();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRemoteId);
    await prefs.remove(_kSerial);
  }
}

// Compiled once — cleanDeviceLabel is called from the ~1 Hz engine-state
// pipeline, and RegExp construction per call was pure per-tick waste.
final RegExp _labelSafeCharset = RegExp(r"^[A-Za-z0-9 '._-]+$");
final RegExp _labelHasAlnum = RegExp(r'[A-Za-z0-9]');

/// A WHOOP serial ("4C2248092") or a user-set strap name ("Abdul's WHOOP") is
/// made of letters, digits, spaces and a little ordinary punctuation. Anything
/// containing other characters (the "?*"-style junk a bad HELLO parse produced)
/// is rejected → null. Gates what we persist and display as the device label.
String? cleanDeviceLabel(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty) return null;
  if (!_labelSafeCharset.hasMatch(t)) return null; // safe charset
  if (!_labelHasAlnum.hasMatch(t)) return null; // needs ≥1 alnum
  return t;
}
