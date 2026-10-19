// Units controller — LOCAL display preferences for weight, distance and
// height. Everything is stored in metric (kg, cm, m); this only changes how
// values are shown and how edit fields are parsed. Persisted on-device via
// SharedPreferences, mirroring ThemeController.
//
// Build 95 (Akshat, option A): three separate choices instead of one
// metric/imperial switch. Weight is the one Body, Today, Food, Progress and
// the profile all follow, so Body no longer keeps a switch of its own.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A whole system at once — for seeding a controller (tests, start-up
/// fallback). The preferences themselves are per measure.
enum UnitSystem { metric, imperial }

/// How a height is written: centimetres, or feet and inches.
enum HeightUnit { cm, ftIn }

class UnitsController extends ChangeNotifier {
  /// The weight choice keeps Body's existing key, so the unit someone already
  /// picked on Body carries over untouched.
  static const String kWeightPref = 'body.unit'; // 'kg' | 'lb'
  static const String kDistancePref = 'units.distance'; // 'km' | 'mi'
  static const String kHeightPref = 'units.height'; // 'cm' | 'ftIn'

  /// Before Build 95 one switch covered every measure. Read once, as the
  /// starting point for any choice that has not been made yet.
  static const String _kLegacySystem = 'units_system';

  static const double _kgPerLb = 0.45359237;
  static const double _cmPerIn = 2.54;
  static const double _metersPerKm = 1000.0;
  static const double _metersPerMile = 1609.344;

  bool _lb;
  bool _miles;
  HeightUnit _height;

  UnitsController._(this._lb, this._miles, this._height);

  /// Every measure in one system.
  factory UnitsController.seed(UnitSystem s) {
    final imperial = s == UnitSystem.imperial;
    return UnitsController._(
      imperial,
      imperial,
      imperial ? HeightUnit.ftIn : HeightUnit.cm,
    );
  }

  /// Each measure on its own.
  factory UnitsController.withUnits({
    String weight = 'kg',
    String distance = 'km',
    HeightUnit height = HeightUnit.cm,
  }) => UnitsController._(weight == 'lb', distance == 'mi', height);

  static Future<UnitsController> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final c = fromPrefs(
      weight: prefs.getString(kWeightPref),
      distance: prefs.getString(kDistancePref),
      height: prefs.getString(kHeightPref),
      legacySystem: prefs.getString(_kLegacySystem),
    );
    // Write every choice down once, so the legacy switch is never consulted
    // again and nothing moves if it is ever removed.
    await prefs.setString(kWeightPref, c.weightUnit);
    await prefs.setString(kDistancePref, c.distanceUnit);
    await prefs.setString(kHeightPref, c.heightUnit.name);
    return c;
  }

  /// The migration rule: a choice already made wins; otherwise the old
  /// metric/imperial switch decides; otherwise metric.
  @visibleForTesting
  static UnitsController fromPrefs({
    String? weight,
    String? distance,
    String? height,
    String? legacySystem,
  }) {
    final imperial = legacySystem == 'imperial';
    return UnitsController._(
      weight == null ? imperial : weight == 'lb',
      distance == null ? imperial : distance == 'mi',
      height == null
          ? (imperial ? HeightUnit.ftIn : HeightUnit.cm)
          : (height == HeightUnit.ftIn.name ? HeightUnit.ftIn : HeightUnit.cm),
    );
  }

  /// 'kg' / 'lb'.
  String get weightUnit => _lb ? 'lb' : 'kg';
  bool get isLb => _lb;
  bool get isMiles => _miles;
  HeightUnit get heightUnit => _height;

  Future<void> setWeightUnit(String unit) async {
    final lb = unit == 'lb';
    if (_lb == lb) return;
    _lb = lb;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kWeightPref, weightUnit);
  }

  Future<void> setDistanceUnit(String unit) async {
    final miles = unit == 'mi';
    if (_miles == miles) return;
    _miles = miles;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kDistancePref, distanceUnit);
  }

  Future<void> setHeightUnit(HeightUnit unit) async {
    if (_height == unit) return;
    _height = unit;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kHeightPref, unit.name);
  }

  // ── display (input is always metric, as stored) ────────────────────────────
  String _trim(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  /// "70 kg" / "154 lb".
  ///
  /// The odd one out: it still answers a bare dash for null, because its one
  /// caller (health_screen's weight row) only ever passes a measured weight, so
  /// the branch is unreachable today. It should become `String?` like the rest
  /// the next time that screen is open for edit.
  String weight(num? kg) {
    if (kg == null) return '—';
    return _lb ? '${(kg / _kgPerLb).round()} lb' : '${_trim(kg)} kg';
  }

  /// "180 cm" / "5′11″", or null when there is no height to show. NULL, not a
  /// dash: a formatter cannot know why the value is missing, and the caller
  /// that does must say so rather than print a placeholder.
  String? height(num? cm) {
    if (cm == null) return null;
    if (_height == HeightUnit.cm) return '${_trim(cm)} cm';
    final totalIn = (cm / _cmPerIn).round();
    return "${totalIn ~/ 12}′${totalIn % 12}″";
  }

  // ── distance + pace (GPS workout routes) ───────────────────────────────────
  /// Length of one distance unit in metres (km or mi).
  double get distanceUnitMeters => _miles ? _metersPerMile : _metersPerKm;

  /// "km" / "mi".
  String get distanceUnit => _miles ? 'mi' : 'km';

  /// Distance value in the user's unit (km or mi), unformatted.
  double distanceValue(double meters) => meters / distanceUnitMeters;

  /// "5.24 km" / "3.25 mi", or null when there is no distance. See [height]
  /// on why this is not a dash.
  String? distance(double? meters, {int decimals = 2}) {
    if (meters == null) return null;
    return '${distanceValue(meters).toStringAsFixed(decimals)} $distanceUnit';
  }

  /// "/km" / "/mi".
  String get paceUnit => '/$distanceUnit';

  /// Above this, a "pace" is meaningless noise, not a real number — e.g. a
  /// few metres of GPS jitter (stationary) divided into real elapsed time
  /// produces something like 1000 min/km. 60 min/km is already far slower
  /// than any real walk/run/ride; treat anything beyond it as "no
  /// meaningful pace yet" rather than showing the raw absurd number.
  static const double _kMaxSanePaceSecPerUnit = 60 * 60;

  /// Format a pace given as seconds-per-unit → "m:ss" (e.g. "5:30"). NULL for
  /// infinite / non-finite (a zero-distance split) or an absurdly slow value
  /// (see [_kMaxSanePaceSecPerUnit]) — there is no pace, and the caller drops
  /// the stat rather than printing a placeholder where a number belongs.
  static String? formatPace(double secPerUnit) {
    if (!secPerUnit.isFinite ||
        secPerUnit <= 0 ||
        secPerUnit > _kMaxSanePaceSecPerUnit) {
      return null;
    }
    final total = secPerUnit.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// "5:30 /km" from total metres + total seconds, or NULL whenever there is
  /// no meaningful pace — including the absurd-pace case (see
  /// [_kMaxSanePaceSecPerUnit]), not just meters<=0. Null rather than a dash
  /// so a caller cannot accidentally render "— /km".
  String? pace(double? meters, int? seconds) {
    if (meters == null || seconds == null || meters <= 0 || seconds <= 0) {
      return null;
    }
    final formatted = formatPace(seconds / (meters / distanceUnitMeters));
    return formatted == null ? null : '$formatted $paceUnit';
  }

  /// "km/h" / "mph" — the unit for INSTANTANEOUS speed (cycling reads more
  /// naturally as a speed than a pace; the live map shows both).
  String get speedUnit => _miles ? 'mph' : 'km/h';

  /// Instantaneous speed (m/s) → "18.4 km/h" / "11.4 mph". NULL for
  /// null/non-finite/negative (no fix yet, or GPS hasn't reported speed) —
  /// there is no speed to show, and the caller owns saying why.
  String? speed(double? metersPerSec, {int decimals = 1}) {
    if (metersPerSec == null || !metersPerSec.isFinite || metersPerSec < 0) {
      return null;
    }
    final perHour = metersPerSec * 3600 / distanceUnitMeters;
    return '${perHour.toStringAsFixed(decimals)} $speedUnit';
  }

  /// Instantaneous pace from a live speed (m/s) → "5:30 /km" — the LIVE
  /// counterpart to [pace] (which needs a whole distance+duration). Used for
  /// a live "current pace" readout that updates every fix instead of only
  /// reflecting the run's average so far.
  String? paceFromSpeed(double? metersPerSec) {
    if (metersPerSec == null || !metersPerSec.isFinite || metersPerSec <= 0) {
      return null;
    }
    final formatted = formatPace(distanceUnitMeters / metersPerSec);
    return formatted == null ? null : '$formatted $paceUnit';
  }

  // ── edit-field helpers (display ↔ metric for storage) ──────────────────────
  String get weightLabel => _lb ? 'Weight (lb)' : 'Weight (kg)';
  String get heightLabel =>
      _height == HeightUnit.ftIn ? 'Height (in)' : 'Height (cm)';

  /// The unit word under a height field: 'in' or 'cm'.
  String get heightFieldUnit => _height == HeightUnit.ftIn ? 'in' : 'cm';

  String _fieldNumber(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// Pre-fill value for the weight field in the user's units.
  String weightField(num? kg) =>
      kg == null ? '' : (_lb ? _trim(kg / _kgPerLb) : _fieldNumber(kg));

  /// Pre-fill value for the height field in the user's units (total inches).
  String heightField(num? cm) => cm == null
      ? ''
      : (_height == HeightUnit.ftIn ? _trim(cm / _cmPerIn) : _fieldNumber(cm));

  /// Parse a weight field (display units) → kg for storage.
  double? weightToKg(String text) {
    final v = double.tryParse(text.trim());
    if (v == null) return null;
    return _lb ? v * _kgPerLb : v;
  }

  /// Parse a height field (display units = total inches for feet) → cm.
  double? heightToCm(String text) {
    final v = double.tryParse(text.trim());
    if (v == null) return null;
    return _height == HeightUnit.ftIn ? v * _cmPerIn : v;
  }
}
