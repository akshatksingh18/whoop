// nightly_sweep.dart — what, if anything, is worth saying about today.
//
// PURE. Takes each metric's own trailing history plus today's value and returns
// zero or more findings. Zero is the normal answer and a complete one: on most
// days nothing about a person is unusual, and a note that restates numbers the
// user looked at three hours ago has negative value.
//
// The bar a finding has to clear — all three are relative to THIS user, never
// to a population:
//   • it is outside the range this person's own history calls ordinary, or
//   • it is a value they have not reached before in the window, or
//   • two of the above landed on the same day.
// Nothing here scores, bands, diagnoses or ranks a day. It reports distance
// from the user's own middle, in the user's own units, with the window it was
// measured over attached — so the reader can disbelieve it.
//
// Robust statistics, for the reason the readiness composite learned the hard
// way: a median/MAD z is unmoved by the one 4am artefact in the window, and MAD
// legitimately collapses to zero on a quantized series (integer efficiency,
// step counts), so it falls back to mean/SD and abstains only when BOTH are
// flat. A flat series has no unusual day in it, which is a correct silence.

import 'dart:math' as math;

import '../data/day_label.dart';
import '../data/local_repository.dart';

/// One metric as the sweep sees it: today, and the days before it.
class SweepSeries {
  /// Series key (`rhr`, `readiness`, …) — only for identity/dedupe.
  final String key;

  /// How the finding names it, in the second person's own words.
  final String label;

  /// `bpm`, `ms`, `%`, `min` (rendered as h/m), or empty for a bare number.
  final String unit;

  /// Decimal places when the value is rendered.
  final int decimals;

  final double today;

  /// Values STRICTLY BEFORE today, oldest→newest, already truncated at any
  /// algo-version break (values across one are not comparable — see
  /// `getChart`'s `algo_breaks`).
  final List<double> history;

  const SweepSeries({
    required this.key,
    required this.label,
    required this.today,
    required this.history,
    this.unit = '',
    this.decimals = 0,
  });
}

class SweepFinding {
  final String key;

  /// The whole line, already human and already carrying its own evidence.
  final String text;

  /// Robust distance from this user's own middle. Ranking only.
  final double z;

  /// True when today is above the middle, false below.
  final bool high;

  const SweepFinding({
    required this.key,
    required this.text,
    required this.z,
    required this.high,
  });
}

/// Days of history before a metric may be judged at all. Below this there is no
/// "usual" to be unusual against, and saying so is the honest output.
const int kSweepMinHistory = 14;

/// Days before "you have not been here before" is worth saying — a new maximum
/// over eleven days is arithmetic, not news.
const int kSweepMinExtremeHistory = 21;

/// How far outside the user's own middle counts. The looser bar applies only
/// when today is also a new high or low for the window: two weak signals
/// agreeing is what makes it worth an interruption.
const double kSweepZ = 2.5;
const double kSweepExtremeZ = 2.0;

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Percentile by nearest rank — the "usually X–Y" band a finding is read
/// against. Not a confidence interval and never presented as one.
double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return double.nan;
  final i = ((sorted.length - 1) * p).round();
  return sorted[i];
}

/// Robust z with a mean/SD fallback for a legitimately quantized series, and
/// null when the history is flat (no unusual day exists in it).
double? _robustZ(double v, List<double> h) {
  final m = _median(h);
  final mad = _median([for (final x in h) (x - m).abs()]);
  if (mad > 0) return 0.6745 * (v - m) / mad;
  final mean = h.reduce((a, b) => a + b) / h.length;
  final sd = math.sqrt(
      h.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / h.length);
  if (sd <= 0) return null;
  return (v - mean) / sd;
}

String _fmt(double v, SweepSeries s) {
  if (s.unit == 'min') {
    final t = v.round();
    final h = t ~/ 60;
    final m = t % 60;
    return h == 0 ? '${m}m' : '${h}h ${m}m';
  }
  final n = v.toStringAsFixed(s.decimals);
  return s.unit.isEmpty ? n : (s.unit == '%' ? '$n%' : '$n ${s.unit}');
}

/// The findings, strongest first. Empty means nothing stood out — which is a
/// complete answer, not a failure to find one.
List<SweepFinding> sweepFindings(List<SweepSeries> series) {
  final out = <SweepFinding>[];
  for (final s in series) {
    final h = [for (final v in s.history) if (v.isFinite) v];
    if (!s.today.isFinite || h.length < kSweepMinHistory) continue;
    final z = _robustZ(s.today, h);
    if (z == null) continue;
    final sorted = [...h]..sort();
    final extreme = h.length >= kSweepMinExtremeHistory &&
        (s.today > sorted.last || s.today < sorted.first);
    if (z.abs() < (extreme ? kSweepExtremeZ : kSweepZ)) continue;

    final high = z > 0;
    final usual = 'usually ${_fmt(_percentile(sorted, .1), s)}'
        '–${_fmt(_percentile(sorted, .9), s)}';
    final where = extreme
        ? '${high ? 'the highest' : 'the lowest'} in ${h.length} days'
        : '${high ? 'above' : 'below'} your usual range';
    out.add(SweepFinding(
      key: s.key,
      text: '${s.label} ${_fmt(s.today, s)} — $where ($usual)',
      z: z,
      high: high,
    ));
  }
  out.sort((a, b) => b.z.abs().compareTo(a.z.abs()));
  return out;
}

/// The two strongest findings stated as what they are: two things that are each
/// unusual for this user, on the same day. NOT a correlation, and never a
/// cause — nothing here has measured a relationship between them.
String? sweepPairing(List<SweepFinding> findings) {
  if (findings.length < 2) return null;
  String name(SweepFinding f) => f.text.split(' — ').first;
  return '${name(findings[0])} and ${name(findings[1])} — both outside your '
      'usual range on the same day, which is worth noticing but is not a '
      'measured relationship between them';
}

/// The exact payload the model is given, and therefore the exact payload the
/// "what was sent" screen shows. One entry per line in the prompt; a key that
/// is absent here was absent from the request.
///
/// Empty when there is nothing to say. The caller must not call a model with
/// an empty map — there is no question to ask.
Map<String, dynamic> sweepInputs(
  List<SweepFinding> findings, {
  String? recommendedBedtime,
}) {
  if (findings.isEmpty) return const {};
  final pair = sweepPairing(findings);
  return {
    'unusual_for_you': [for (final f in findings.take(4)) f.text],
    'unusual_together': ?pair,
    // Evidence for an action, and the only value here that is not a finding.
    // Already computed by the sleep coach and already shown on Home — the model
    // is given the time so it can name one rather than invent one.
    'recommended_bedtime': ?recommendedBedtime,
  };
}

/// The one line the OS notification carries. It is a finding, not a promise of
/// one: the notification is armed only when this is non-null, and its body is
/// this text, so tapping it can never lead to "nothing to report".
String? sweepHeadline(List<SweepFinding> findings) {
  if (findings.isEmpty) return null;
  final t = findings.first.text;
  return t.isEmpty ? null : '${t[0].toUpperCase()}${t.substring(1)}';
}

/// What the briefing says when the sweep found nothing. Complete as it stands —
/// it must never be padded out with the day's numbers to look like more.
const String kNothingStoodOut = 'Nothing stood out tonight.';

// ── reading the series ──────────────────────────────────────────────────────

num? _num(dynamic v) => v is num ? v : null;

/// The metrics the sweep looks at, keyed by the name [LocalRepository.getChart]
/// speaks (it maps those onto series keys itself). Deliberately short: every
/// one of these is a number the user already has a screen for, so a finding
/// about it can be checked.
const Map<String, ({String key, String label, String unit, int dp})>
    kSweepMetrics = {
  'recovery': (key: 'readiness', label: 'readiness', unit: '', dp: 0),
  'resting_hr': (key: 'rhr', label: 'resting heart rate', unit: 'bpm', dp: 0),
  'hrv': (key: 'rmssd', label: 'HRV', unit: 'ms', dp: 0),
  'strain': (key: 'strain', label: 'strain', unit: '', dp: 1),
  'steps': (key: 'steps', label: 'steps', unit: '', dp: 0),
  'sleep': (key: 'tst_min', label: 'time asleep', unit: 'min', dp: 0),
  'efficiency': (
    key: 'efficiency',
    label: 'sleep efficiency',
    unit: '%',
    dp: 0
  ),
};

/// Today's value plus its own trailing history, per metric, read from the same
/// derived store the trend screens draw. A metric with no value TODAY is left
/// out entirely — there is nothing to have a finding about.
///
/// The window stops at the most recent algo-version break on or before the
/// shown calendar day. A later break cannot erase an earlier day's history.
/// Values either side
/// of one are not comparable, and a version bump reported as "the lowest in 60
/// days" would be a finding about us, not about the user.
Future<List<SweepSeries>> collectSweepSeries(
  LocalRepository repo,
  DateTime now,
) async {
  final today = todayLabel(now);
  final out = <SweepSeries>[];
  for (final e in kSweepMetrics.entries) {
    try {
      final chart = await repo.getChart(e.key);
      final points = chart['points'];
      if (points is! List) continue;
      var cutoff = 0;
      final breaks = chart['algo_breaks'];
      if (breaks is List) {
        for (final b in breaks) {
          final t = b is Map ? _num(b['t'])?.toInt() : null;
          if (t != null &&
              t > cutoff &&
              todayLabel(
                    DateTime.fromMillisecondsSinceEpoch(t * 1000),
                  ).compareTo(today) <=
                  0) {
            cutoff = t;
          }
        }
      }
      double? todayValue;
      final history = <double>[];
      for (final p in points) {
        if (p is! Map) continue;
        final t = _num(p['t'])?.toInt();
        final v = _num(p['v'])?.toDouble();
        if (t == null || v == null || !v.isFinite) continue;
        final day = todayLabel(DateTime.fromMillisecondsSinceEpoch(t * 1000));
        if (day == today) {
          todayValue = v;
        } else if (day.compareTo(today) < 0 && t >= cutoff) {
          history.add(v);
        }
      }
      if (todayValue == null) continue;
      final m = e.value;
      out.add(SweepSeries(
        key: m.key,
        label: m.label,
        unit: m.unit,
        decimals: m.dp,
        today: todayValue,
        history: history,
      ));
    } catch (_) {/* a series we cannot read is a series with no finding */}
  }
  return out;
}
