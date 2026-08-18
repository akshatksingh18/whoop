// FINDINGS — what the app noticed, in one place, said the same way twice.
//
// Four independent detectors fire on the cross-day rollup: the illness CUSUM,
// the multivariate overnight anomaly, the skin-temperature flag and a
// change-point search on resting heart rate. A fifth, the irregular-rhythm
// screen, comes off `metric_series`, and a sixth is simply a low readiness.
//
// Exactly one of them — illness — ever reached a screen. The rest existed only
// as a push notification: one buzz, and if you dismissed it, gone. The
// `notifications` table with its kind/title/body/date has been in the schema
// the whole time with nothing writing to it.
//
// THE LOG IS RECOMPUTED, NOT RECORDED. Nothing here is written to disk and no
// table was added, because a finding is DERIVED and not authored — the rollup
// already carries the per-day inputs (`recent[]` holds `illness`, `anomaly`,
// `temp` and `rhr` for every day in the 90-day window), so the whole history
// is available from the first run instead of a log that starts empty today and
// fills up over three months. It also cannot drift from what the detectors
// currently say: re-derive a day, and its entry changes with it.
//
// What that costs, stated plainly: a finding whose data was later re-derived
// away DISAPPEARS from the log rather than standing as a record of what buzzed
// that morning. That is the right trade for a health app — the log answers
// "what does my data say happened", not "what did this phone display" — and it
// is the reason `notif_fired` is left alone as the fire-once ledger it is.
//
// The wording lives HERE and nowhere else. It used to be inline in the
// notification builder, which is why a log built anywhere else would have
// quietly become a second, differently-worded copy of the same six sentences.

import 'package:flutter/foundation.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;

/// Below this, readiness is a finding. Shared so the notification and the log
/// cannot disagree about which mornings were low.
const double kLowReadiness = 34;

enum FindingKind {
  illness,
  anomaly,
  tempElevated,
  irregularRhythm,
  lowReadiness,
  rhrShift,
}

@immutable
class Finding {
  const Finding(this.kind, this.date, {this.risen});

  final FindingKind kind;

  /// The day the finding is ABOUT (`YYYY-MM-DD`), which is not the day it was
  /// computed on — a back-catalogue import produces findings about last
  /// November.
  final String date;

  /// Direction, for [FindingKind.rhrShift] only.
  final bool? risen;

  /// DETECTION-class, the ones the design sanctions interrupting for. It picks
  /// the notification's dedupe key and marks the entry in the log; it never
  /// changes the wording, and it is never a diagnosis.
  bool get medical => switch (kind) {
        FindingKind.illness ||
        FindingKind.anomaly ||
        FindingKind.tempElevated ||
        FindingKind.irregularRhythm =>
          true,
        _ => false,
      };

  String get title => switch (kind) {
        FindingKind.illness => 'Possible illness onset',
        FindingKind.anomaly => 'Unusual overnight physiology',
        FindingKind.tempElevated => 'Skin temperature elevated',
        FindingKind.irregularRhythm => 'Irregular heart rhythm — screen',
        FindingKind.lowReadiness => 'Low readiness today',
        FindingKind.rhrShift => 'Your resting heart-rate trend shifted',
      };

  String get detail => switch (kind) {
        FindingKind.illness =>
          'Elevated resting HR + suppressed HRV over recent nights.',
        FindingKind.anomaly =>
          'Your nightly signals deviate from your personal baseline.',
        FindingKind.tempElevated =>
          'Sustained rise vs your baseline — a possible illness signal.',
        FindingKind.irregularRhythm =>
          'Your beat-to-beat pattern looked irregular today. This is a '
              'screen, not a diagnosis — see a clinician if you have symptoms.',
        FindingKind.lowReadiness =>
          'Your recovery markers are below your usual range — ease off.',
        FindingKind.rhrShift =>
          'Your resting HR has ${risen == false ? 'fallen' : 'risen'} '
              'noticeably versus your recent baseline.',
      };

  @override
  bool operator ==(Object other) =>
      other is Finding &&
      other.kind == kind &&
      other.date == date &&
      other.risen == risen;

  @override
  int get hashCode => Object.hash(kind, date, risen);
}

/// Every finding the rollup holds, newest day first, and within a day in the
/// order the detectors are listed above.
///
/// [cd] is the stored cross-day bundle (`getInsights()`). Only `recent[]` is
/// read: it carries one row per day with the three overnight detector verdicts
/// already computed, so nothing is re-detected here except the resting-HR
/// change points, which need the whole series at once.
///
/// [readiness] and [irregularDays] come from `metric_series` — the one store
/// that keeps a value per day for as long as the day exists — because neither
/// is in `recent[]`. Absent, those two kinds simply do not appear; they are
/// never inferred from a neighbouring day.
///
/// UNSETTLED DAYS ARE SKIPPED, for the same reason the notification stands down
/// on them: a night that is only half drained reads several bpm high, and a
/// log that shows a finding in the morning and drops it by lunchtime is worse
/// than one that waits for the day to settle.
List<Finding> findingsHistory(
  Map<String, dynamic> cd, {
  Map<String, double> readiness = const {},
  Set<String> irregularDays = const {},
}) {
  final recent = cd['recent'];
  if (recent is! List) return const [];

  final rows = <Map>[
    for (final r in recent)
      if (r is Map && r['date'] is String && r['unsettled'] != true) r,
  ];

  // The change-point search wants the RHR series in order, and the dates have
  // to travel with the values: the series is compacted (a day with no
  // nocturnal RHR is skipped, which is most days for some people), so the
  // detection's index is an index into the COMPACTED list, not into the days.
  final rhr = <double>[];
  final rhrDates = <String>[];
  for (final r in rows) {
    if (r['rhr'] is num) {
      rhr.add((r['rhr'] as num).toDouble());
      rhrDates.add(r['date'] as String);
    }
  }
  // ponytail: called exactly as the notification path calls it — no `dates`,
  // so a calendar gap does not break the regime. Passing them is the honest
  // reading by the detector's own documentation, but it would make this log
  // report a different set of shifts than the buzz the user actually got.
  // Change both together or neither.
  final shifts = <String, bool>{};
  if (rhr.length >= 10) {
    for (final d in ana.cusumChangePoints(rhr, h: 5.0)) {
      if (d.index >= 0 && d.index < rhrDates.length) {
        shifts[rhrDates[d.index]] = d.direction > 0;
      }
    }
  }

  final out = <Finding>[];
  for (final r in rows.reversed) {
    final date = r['date'] as String;
    if (r['illness'] == true) out.add(Finding(FindingKind.illness, date));
    if (r['anomaly'] == true) out.add(Finding(FindingKind.anomaly, date));
    if (r['temp'] == true) out.add(Finding(FindingKind.tempElevated, date));
    if (irregularDays.contains(date)) {
      out.add(Finding(FindingKind.irregularRhythm, date));
    }
    final ready = readiness[date];
    if (ready != null && ready < kLowReadiness) {
      out.add(Finding(FindingKind.lowReadiness, date));
    }
    if (shifts.containsKey(date)) {
      out.add(Finding(FindingKind.rhrShift, date, risen: shifts[date]));
    }
  }
  return out;
}
