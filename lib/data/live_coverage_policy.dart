// live_coverage_policy.dart — pure, I/O-free step-coverage policy. Nothing
// here touches BLE, the DB, Flutter or the clock.
//
// A `live_coverage` row says "over THIS period this source counted N steps".
// Phone rows come from the iPhone pedometer; band rows come only from an
// imported NOOP backup. [resolveDaySteps] turns a day's rows into one total
// without counting a minute twice, and [sanitizeCoverageWindow] guards what
// reaches the table.

import 'dart:math' as math;

/// Cadence ceiling used to derive a LOWER BOUND on elapsed time from a step
/// count. Elite sprint cadence tops out near 220 spm; 240 leaves headroom so
/// the bound is never tighter than physiology allows. This is a bound, never an
/// estimate: N steps cannot have happened in less than N / (240/60) seconds.
const double kMaxPlausibleCadenceSpm = 240.0;

/// A stored coverage window, in the same epoch-second base as
/// `decoded_onehz.rec_ts`.
class LiveCoverageWindow {
  const LiveCoverageWindow(this.startTs, this.endTs);
  final int startTs;
  final int endTs;
  int get seconds => endTs - startTs;

  @override
  String toString() => 'LiveCoverageWindow($startTs..$endTs, ${seconds}s)';
}

/// The shortest elapsed time [steps] could physically span, in whole seconds.
/// 0 for a non-positive count. See [kMaxPlausibleCadenceSpm].
int minCoverageSecondsForSteps(int steps) =>
    steps <= 0 ? 0 : (steps * 60 / kMaxPlausibleCadenceSpm).ceil();

// ── THE SOURCE LADDER ───────────────────────────────────────────────────────
//
// A day is not owned by one source. Each SPAN of it goes to the best source
// that actually covered that span, and the spans sum. Whole-day precedence
// ("the band reported something, so the band takes the day") reported 622 steps
// against the phone's 18,856 on a real export, because the strap only covered
// the hours it was syncing.
//
// TWO FAILURES, NOT ONE. Per-span precedence alone is not enough either.
// `live_coverage` spans say "a live link existed", not "the pedometer was
// counting", and older live rows were deliberately biased WIDE.
// On the same export the band claimed 9.35 h of coverage for 216 steps
// (0.4 spm) while the phone had 11 h for 7,775 (11.8 spm): handing the band
// that span because it is nominally the better sensor loses ~7,000 steps. So a
// band span only outranks the phone where it actually looks like gait — see
// [kBandSpanMinSpm].
//
// HOW OVERLAPS ARE SETTLED. Spans are resolved highest rank first; a lower-
// ranked span is credited its own count MINUS what the higher-ranked spans
// already counted over the time they share (pro-rated by overlap). So a strap
// session inside a phone-covered hour contributes its own minutes and the phone
// contributes the rest, and neither the walk nor the hour is counted twice. The
// subtraction is bounded at zero, so a source can lose its claim but can never
// go negative — nothing is ever fabricated and nothing is double-counted.

/// Minimum step density (steps per minute, over the span's own extent) a BAND
/// span must show before it outranks the phone over time they both cover.
///
/// This is a WEAR-vs-GAIT discriminator, not a cadence gate — a real bout
/// includes pauses, so it sits far below the 60–200 spm walking band. Measured
/// band spans from a real export: 0.4, 3.0 (link idle, phone was right) and
/// 101.6 spm (an 11-minute walk, band was right). It only ever changes the
/// ORDER between band and phone: on a day with no phone data the band keeps
/// every step it counted regardless of this number.
///
/// Left as a knob on purpose — a different strap, worn differently, will sit
/// somewhere else on this axis.
const double kBandSpanMinSpm = 10.0;

/// A band span below this density is treated as wrist noise when it overlaps
/// an hour the phone explicitly confirmed at zero steps. The floor is above
/// the documented 22-27 false steps/min seen during chores/driving and below
/// ordinary walking cadence, so a real walk with the phone left behind stays.
const double kConfirmedStillMinSpm = 40.0;

/// Remove only the portion of a low-density band span that overlaps a
/// confirmed-zero phone window. Phone rows are never modified.
List<CoverageSpan> _vetoAgainstConfirmedStill(List<CoverageSpan> rows) {
  final stillWindows = [
    for (final r in rows)
      if (!r.fromBand && r.steps == 0 && r.endTs > r.startTs) r,
  ];
  if (stillWindows.isEmpty) return rows;

  // ponytail: phone coverage is written as non-overlapping hourly windows, so
  // a direct overlap sum is simpler than a merge pass. Merge first if that
  // storage contract ever changes.
  final out = <CoverageSpan>[];
  for (final r in rows) {
    if (!r.fromBand || r.steps <= 0 || r.endTs <= r.startTs) {
      out.add(r);
      continue;
    }
    final dur = r.endTs - r.startTs;
    final spm = r.steps * 60 / dur;
    if (spm >= kConfirmedStillMinSpm) {
      out.add(r);
      continue;
    }
    var voidedSec = 0;
    for (final z in stillWindows) {
      final lo = math.max(r.startTs, z.startTs);
      final hi = math.min(r.endTs, z.endTs);
      if (hi > lo) voidedSec += hi - lo;
    }
    if (voidedSec <= 0) {
      out.add(r);
      continue;
    }
    final keptSec = math.max(0, dur - voidedSec);
    if (keptSec <= 0) continue;
    final keptSteps = (r.steps * keptSec / dur).round();
    if (keptSteps <= 0) continue;
    out.add(
      CoverageSpan(
        startTs: r.startTs,
        endTs: r.endTs,
        steps: keptSteps,
        fromBand: true,
        deviceId: r.deviceId,
      ),
    );
  }
  return out;
}

/// PHONE FIRST (the personal build, Akshat's decision). He carries the phone
/// on every walk and run, and held in the hand it still counts every stride,
/// while the wrist reads a real walk low: on 3 October the band counted 4,835
/// steps for a 35-minute run the phone counted at 5,200 (cadence × time puts
/// it near 5,250).
///
/// So any phone window that counted steps belongs to the phone outright: the
/// band's steps over that window are removed BEFORE ranking, never prorated
/// against it. (Ranking the phone above the band would not do this — overlap
/// is shared out by time, and a phone hour's steps are not spread evenly over
/// it, so a run inside a busy hour would be counted twice.) The band keeps:
///
/// * time no phone window covers (the phone was not counting);
/// * phone windows that confirmed zero steps, subject to the still-veto above;
/// A positive phone measurement always wins; a larger wrist count cannot override it.
///
/// Band spans are split into the pieces that survive, each keeping its share
/// of the span's steps by time. Phone rows are never modified.
List<CoverageSpan> _phoneFirst(List<CoverageSpan> rows) {
  final counted = [
    for (final r in rows)
      if (!r.fromBand && r.steps > 0 && r.endTs > r.startTs) r,
  ]..sort((a, b) => a.startTs.compareTo(b.startTs));
  if (counted.isEmpty) return rows;
  final out = <CoverageSpan>[];
  for (final r in rows) {
    if (!r.fromBand || r.steps <= 0 || r.endTs <= r.startTs) {
      out.add(r);
      continue;
    }
    final dur = r.endTs - r.startTs;
    final clips = <(int, int)>[];
    for (final ph in counted) {
      final lo = math.max(r.startTs, ph.startTs);
      final hi = math.min(r.endTs, ph.endTs);
      if (hi <= lo) continue;
      // Positive phone movement always wins this exact interval.
      clips.add((lo, hi));
    }
    if (clips.isEmpty) {
      out.add(r);
      continue;
    }
    var cursor = r.startTs;
    void piece(int a, int b) {
      if (b <= a) return;
      final n =
          (r.steps * (b - r.startTs) / dur).round() -
          (r.steps * (a - r.startTs) / dur).round();
      if (n <= 0) return;
      out.add(
        CoverageSpan(
          startTs: a,
          endTs: b,
          steps: n,
          fromBand: true,
          deviceId: r.deviceId,
        ),
      );
    }

    for (final (lo, hi) in clips) {
      piece(cursor, lo);
      if (hi > cursor) cursor = hi;
    }
    piece(cursor, r.endTs);
  }
  return out;
}

/// One `live_coverage` row, as the resolver sees it.
class CoverageSpan {
  const CoverageSpan({
    required this.startTs,
    required this.endTs,
    required this.steps,
    required this.fromBand,
    this.deviceId = '',
  });

  final int startTs;
  final int endTs;
  final int steps;

  /// `source != 'phone'` — the band's own 100 Hz pedometer, live or imported.
  final bool fromBand;

  /// WHICH PHYSICAL SENSOR counted these steps. `''` is permanently reserved
  /// for the primary band (and for the phone, which is likewise one of it),
  /// so a single-device install is entirely `''` and behaves exactly as it did
  /// before this field existed.
  ///
  /// It exists because two sensors that are not the same sensor can produce
  /// two spans of the same rank over the same walk — see [resolveDaySteps].
  final String deviceId;
}

/// A day's steps after the ladder has run, split by the sensor that counted.
class ResolvedDaySteps {
  const ResolvedDaySteps({
    this.strap = 0,
    this.phone = 0,
    this.spans = const [],
    this.hasPhoneCoverage = false,
    this.coveredSeconds = 0,
  });

  /// Includes explicitly measured stillness; zero differs from no phone read.
  final bool hasPhoneCoverage;
  final int coveredSeconds;

  /// Steps credited to the band's 100 Hz pedometer.
  final int strap;

  /// Steps credited to the phone's pedometer.
  final int phone;

  /// The spans AS CREDITED, in time order — never the raw table rows.
  ///
  /// A screen that draws the day's spans has to draw these: a raw row still
  /// carries the steps the ladder took back off it, so a strap session inside a
  /// phone-covered hour would be drawn twice, showing the user a walk the total
  /// (correctly) only counts once. Spans credited nothing are dropped for the
  /// same reason.
  ///
  /// Each span is rounded on its own, so re-summing this list can differ from
  /// [total] by a step or two. [total] is the number to publish.
  final List<CoverageSpan> spans;

  int get total => strap + phone;

  /// The sensor that counted most of the day, or null when nothing counted.
  /// Ties go to the strap — it is the higher-ranked sensor.
  String? get dominant =>
      total <= 0 ? null : (strap >= phone ? 'strap' : 'phone');

  bool get mixed => strap > 0 && phone > 0;

  static const none = ResolvedDaySteps();
}

class _Ranked {
  _Ranked(
    this.startTs,
    this.endTs,
    this.steps,
    this.rank,
    this.fromBand,
    this.deviceId,
  );
  final int startTs, endTs, rank;
  final double steps;
  final bool fromBand;
  final String deviceId;
  double credited = 0;
}

/// Resolve one day's coverage rows into a per-sensor step split.
///
/// Order of business, per the ladder note above: rank each span, then walk them
/// highest first, subtracting from each what the higher-ranked spans already
/// counted over shared time.
///
/// A single-source day is unchanged by all of this — every span keeps its full
/// count and the total is the plain sum, exactly as before.
// ponytail: O(n²) over one day's rows (tens, typically single digits). If a day
// ever carries thousands, sort by start and sweep instead.
ResolvedDaySteps resolveDaySteps(
  Iterable<CoverageSpan> rows, {
  bool phoneFirst = true,
  bool bandSteps = false,
}) {
  final spans = <_Ranked>[];
  // Phone only by default (Akshat, Build 89): band rows never enter the
  // resolution, so they can neither add steps nor fill time the phone did not
  // cover. [bandSteps] keeps the band ladder testable.
  final measured = [
    for (final r in rows)
      if (bandSteps || !r.fromBand) r,
  ];
  final hasPhoneCoverage = measured.any(
    (r) => !r.fromBand && r.steps >= 0 && r.endTs > r.startTs,
  );
  final vetted = _vetoAgainstConfirmedStill(measured);
  final coverage =
      vetted
          .where(
            (r) =>
                r.endTs > r.startTs &&
                (r.steps > 0 || (!r.fromBand && r.steps == 0)),
          )
          .toList()
        ..sort((a, b) => a.startTs.compareTo(b.startTs));
  var coveredSeconds = 0, coveredUntil = 0;
  for (final r in coverage) {
    final start = math.max(coveredUntil, r.startTs);
    if (r.endTs > start) coveredSeconds += r.endTs - start;
    coveredUntil = math.max(coveredUntil, r.endTs);
  }
  for (final r in phoneFirst ? _phoneFirst(vetted) : vetted) {
    // Legacy zero-width rows are real counts with a lost extent; repair them
    // the same way the writer does rather than dropping a measurement.
    final w = sanitizeCoverageWindow(r.startTs, r.endTs, r.steps);
    if (w == null) continue;
    final spm = r.steps * 60 / (w.endTs - w.startTs);
    // 2 = band that looks like gait, 1 = phone, 0 = band that does not.
    final rank = r.fromBand ? (spm >= kBandSpanMinSpm ? 2 : 0) : 1;
    spans.add(
      _Ranked(
        w.startTs,
        w.endTs,
        r.steps.toDouble(),
        rank,
        r.fromBand,
        r.deviceId,
      ),
    );
  }
  // Rank first, then start time — `List.sort` is NOT stable in Dart, and once
  // equal-ranked spans from different devices compete (below) the winner is
  // whichever is resolved first, so the tie needs a rule of its own or the
  // day's total depends on the order SQLite happened to return the rows in.
  // Earliest span wins; it is arbitrary but it is the same arbitrary answer
  // every run, which is what a re-derive needs — and that only holds if the
  // keys reach a TOTAL order. Two devices can share rank AND start, so end and
  // then `deviceId` finish it; without them the claim above was still an
  // unstable sort's answer. Same-device ties need no rule: equal rank within
  // one device is summed, not competed (see the loop below).
  spans.sort((a, b) {
    if (b.rank != a.rank) return b.rank.compareTo(a.rank);
    if (a.startTs != b.startTs) return a.startTs.compareTo(b.startTs);
    if (a.endTs != b.endTs) return a.endTs.compareTo(b.endTs);
    return a.deviceId.compareTo(b.deviceId);
  });

  var strap = 0.0;
  var phone = 0.0;
  for (var i = 0; i < spans.length; i++) {
    final s = spans[i];
    var alreadyCounted = 0.0;
    for (var j = 0; j < i; j++) {
      final h = spans[j];
      // EQUAL RANK IS NOT COMPETITION *WITHIN ONE DEVICE*. Two band rows, or
      // two phone rows, from the SAME `device_id` are the same sensor reporting
      // twice and are summed — which is what the table has always meant and
      // what re-import idempotency relies on.
      //
      // Two DIFFERENT devices are not that. Rank is a property of the SPAN
      // (band-that-looks-like-gait / phone / band-that-does-not), so two straps
      // on the same 3,000-step walk both rank 2, skipped each other here, and
      // the day published 6,000. Different id ⇒ they compete like any other
      // pair, and the tie is broken by start time (see the sort above).
      if (h.rank <= s.rank && h.deviceId == s.deviceId) continue;
      final ov = math.min(s.endTs, h.endTs) - math.max(s.startTs, h.startTs);
      if (ov <= 0) continue;
      alreadyCounted += h.credited * ov / (h.endTs - h.startTs);
    }
    s.credited = math.max(0.0, s.steps - alreadyCounted);
    if (s.fromBand) {
      strap += s.credited;
    } else {
      phone += s.credited;
    }
  }
  return ResolvedDaySteps(
    hasPhoneCoverage: hasPhoneCoverage,
    coveredSeconds: coveredSeconds,
    strap: strap.round(),
    phone: phone.round(),
    spans: [
      for (final s in spans)
        if (s.credited.round() > 0)
          CoverageSpan(
            startTs: s.startTs,
            endTs: s.endTs,
            steps: s.credited.round(),
            fromBand: s.fromBand,
            deviceId: s.deviceId,
          ),
    ]..sort((a, b) => a.startTs.compareTo(b.startTs)),
  );
}

/// Persistence-boundary guard: normalise a window before it reaches the
/// `live_coverage` table, or null when it must not be stored at all.
///
/// REPAIR, NOT REJECT. Dropping a zero-width row would throw away a real step
/// count. Widening the window to the physically implied minimum
/// ([minCoverageSecondsForSteps]) keeps the steps and claims only what a bound
/// supports.
/// The one case that IS rejected is an inverted window (`endTs < startTs`):
/// that is incoherent rather than merely imprecise, and there is no defensible
/// way to decide which end was meant.
LiveCoverageWindow? sanitizeCoverageWindow(int startTs, int endTs, int steps) {
  if (steps <= 0) return null;
  if (endTs < startTs) return null;
  final minS = math.max(1, minCoverageSecondsForSteps(steps));
  if (endTs - startTs < minS) {
    return LiveCoverageWindow(startTs, startTs + minS);
  }
  return LiveCoverageWindow(startTs, endTs);
}
