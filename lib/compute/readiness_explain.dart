// Recovery, explained (Build 90, Akshat's option A).
//
// Pure helpers the Recovery page and the HRV page share, so both describe a
// night against the SAME comparison the score used: the trailing 28 measured
// nights within the 60 calendar days before it (`_BaselineHistoryCache.
// valuesBefore` in derivation_engine.dart), at least 14 of them, from the same
// nightly series (`ln_rmssd_v2`, `rhr`, `resp_rate`, `tst_min`).
//
// Nothing here changes the score. The points are a decomposition of the stored
// composite (`clinical.readiness_composite.drivers`, whose contributions sum
// to the composite z), walked from a typical night (z = 0, score 50) in order
// of size, so they add up to the shown score exactly.

import 'dart:math' as math;

/// The score's comparison window (keep equal to derivation_engine.dart's
/// `_baselineWindowDays`, `_baselineMaxAgeDays` and analytics'
/// `readinessCompositeMinBaseline`; pinned by readiness_explain_test.dart).
const int kRecoveryBaselineNights = 28;
const int kRecoveryBaselineMaxAgeDays = 60;
const int kRecoveryBaselineMinNights = 14;

typedef DatedValue = ({String date, double value});

String _label(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The baseline [day] was judged against: the newest 28 values strictly before
/// [day] and no older than 60 calendar days. [series] is oldest → newest.
List<double> recoveryBaseline(List<DatedValue> series, String day) {
  final d = DateTime.parse(day);
  final from = _label(
    DateTime(d.year, d.month, d.day - kRecoveryBaselineMaxAgeDays),
  );
  final eligible = [
    for (final s in series)
      if (s.date.compareTo(day) < 0 && s.date.compareTo(from) >= 0) s.value,
  ];
  final start = math.max(0, eligible.length - kRecoveryBaselineNights);
  return eligible.sublist(start);
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// A baseline's centre and spread, the way the composite scales it: median and
/// MAD × 1.4826, or mean and SD when the MAD is 0 (a quantized baseline).
/// Null below 14 values or with no spread at all.
({double centre, double spread})? recoveryScale(List<double> base) {
  if (base.length < kRecoveryBaselineMinNights) return null;
  final m = _median(base);
  final mad = _median([for (final x in base) (x - m).abs()]) * 1.4826;
  if (mad > 0) return (centre: m, spread: mad);
  final mean = base.reduce((a, b) => a + b) / base.length;
  final sd = math.sqrt(
    base.fold<double>(0, (a, x) => a + (x - mean) * (x - mean)) /
        (base.length - 1),
  );
  return sd > 0 ? (centre: mean, spread: sd) : null;
}

/// "Usual" = within one spread of the centre, the band where the input barely
/// moves the score.
({double lo, double hi}) usualRange(({double centre, double spread}) s) =>
    (lo: s.centre - s.spread, hi: s.centre + s.spread);

/// Plain words for where [z] (value minus centre, in spreads) sits.
String usualWord(double z) {
  if (z <= -2) return 'Well below usual';
  if (z <= -1) return 'Below usual';
  if (z < 1) return 'About usual';
  if (z < 2) return 'Above usual';
  return 'Well above usual';
}

/// Points each input moved the score from a typical night (50), in input
/// order. Contributions are walked largest-first through the score's logistic
/// and rounded so they sum exactly to `round(score) − 50`.
List<int> recoveryPoints(List<double> contributions) {
  if (contributions.isEmpty) return const [];
  double score(double z) => 100 / (1 + math.exp(-z));
  final order = [for (var i = 0; i < contributions.length; i++) i]
    ..sort((a, b) => contributions[b].abs().compareTo(contributions[a].abs()));
  final raw = List<double>.filled(contributions.length, 0);
  var z = 0.0;
  for (final i in order) {
    final before = score(z);
    z += contributions[i];
    raw[i] = score(z) - before;
  }
  final target = score(z).round() - 50;
  final out = [for (final r in raw) r.truncate()];
  var rest = target - out.fold<int>(0, (a, b) => a + b);
  // Largest remainder in the direction still owed.
  final byRemainder = [for (var i = 0; i < raw.length; i++) i]
    ..sort(
      (a, b) => ((raw[b] - out[b]) * rest.sign).compareTo(
        (raw[a] - out[a]) * rest.sign,
      ),
    );
  for (final i in byRemainder) {
    if (rest == 0) break;
    out[i] += rest.sign;
    rest -= rest.sign;
  }
  return out;
}

/// What the recent-HRV card draws (see [recentHrv]).
typedef RecentHrvView = ({
  /// The day the view is for (the morning after the night it ends on).
  String day,
  List<({String date, double ms})> nights,
  ({double lo, double hi})? usual,
  double? avg7,
  double? last,
  String? lastDate,
});

/// The recent-HRV card: the last [nights] measured nights up to [day], each in
/// ms, the usual band (ms) from the baseline before [day], and the 7-night
/// average (ms, mean of the nights' ln values exponentiated). [lnSeries] is
/// `ln_rmssd_v2`, oldest → newest.
RecentHrvView recentHrv(
  List<DatedValue> lnSeries,
  String day, {
  int nights = 14,
}) {
  final upTo = [
    for (final s in lnSeries)
      if (s.date.compareTo(day) <= 0) s,
  ];
  final shown = upTo.sublist(math.max(0, upTo.length - nights));
  final lastIsDay = upTo.isNotEmpty && upTo.last.date == day;
  final scale = recoveryScale(recoveryBaseline(lnSeries, day));
  final band = scale == null ? null : usualRange(scale);
  final week = upTo.sublist(math.max(0, upTo.length - 7));
  return (
    day: day,
    nights: [for (final s in shown) (date: s.date, ms: math.exp(s.value))],
    usual: band == null ? null : (lo: math.exp(band.lo), hi: math.exp(band.hi)),
    avg7: week.length < 3
        ? null
        : math.exp(
            week.map((s) => s.value).reduce((a, b) => a + b) / week.length,
          ),
    last: lastIsDay ? math.exp(upTo.last.value) : null,
    lastDate: lastIsDay ? day : null,
  );
}
