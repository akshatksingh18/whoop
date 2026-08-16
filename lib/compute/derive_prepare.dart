import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;

import 'substrate.dart';

class PreparedDerivationDay {
  final String date;
  final int endSec;
  final double confidence;
  final List<String> flags;
  final Map<String, dynamic> sleepJson;
  final List<String> hypnoStages;
  final int sleepOnsetSec;
  final int sleepOffsetSec;
  final String sleepSource;
  final Substrate daySub;
  final Substrate sleepSub;

  /// Same as [daySub] but extended [napBoundaryBufferSec] past the calendar
  /// end — a nap/secondary-sleep block that starts before midnight and runs
  /// past it was being silently bisected at the exact day boundary (each half
  /// falling under the 20-min floor and vanishing from BOTH days). Only nap
  /// detection reads this wider slice; every other day-scoped calc keeps using
  /// the strict [daySub] so steps/wear/activity are never double-counted.
  final Substrate napSub;

  const PreparedDerivationDay({
    required this.date,
    required this.endSec,
    required this.confidence,
    required this.flags,
    required this.sleepJson,
    required this.hypnoStages,
    required this.sleepOnsetSec,
    required this.sleepOffsetSec,
    required this.daySub,
    required this.sleepSub,
    Substrate? napSub,
    this.sleepSource = 'auto',
  }) : napSub = napSub ?? daySub;

  Map<String, dynamic> toJson() => {
    'date': date,
    'end_sec': endSec,
    'confidence': confidence,
    'flags': flags,
    'sleep_json': sleepJson,
    'hypno_stages': hypnoStages,
    'sleep_onset_sec': sleepOnsetSec,
    'sleep_offset_sec': sleepOffsetSec,
    'sleep_source': sleepSource,
    'day_sub': daySub.toJson(),
    'sleep_sub': sleepSub.toJson(),
    'nap_sub': napSub.toJson(),
  };

  static PreparedDerivationDay fromJson(Map<String, dynamic> m) {
    List<String> strs(String k) =>
        ((m[k] as List?) ?? const []).map((e) => e.toString()).toList();
    final daySub = Substrate.fromJson(
      ((m['day_sub'] as Map?) ?? const {}).cast<String, dynamic>(),
    );
    return PreparedDerivationDay(
      date: m['date'] as String? ?? '',
      endSec: (m['end_sec'] as num?)?.toInt() ?? 0,
      confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
      flags: strs('flags'),
      sleepJson: ((m['sleep_json'] as Map?) ?? const {})
          .cast<String, dynamic>(),
      hypnoStages: strs('hypno_stages'),
      sleepOnsetSec: (m['sleep_onset_sec'] as num?)?.toInt() ?? 0,
      sleepOffsetSec: (m['sleep_offset_sec'] as num?)?.toInt() ?? 0,
      sleepSource: m['sleep_source'] as String? ?? 'auto',
      daySub: daySub,
      sleepSub: Substrate.fromJson(
        ((m['sleep_sub'] as Map?) ?? const {}).cast<String, dynamic>(),
      ),
      napSub: m['nap_sub'] is Map
          ? Substrate.fromJson((m['nap_sub'] as Map).cast<String, dynamic>())
          : daySub,
    );
  }
}

/// How far past a day's calendar end nap detection is allowed to look, so a
/// nap/secondary-sleep block spanning midnight is seen whole by the day it
/// started on. Naps starting inside this buffer belong to tomorrow, which
/// sees them anyway in its own regular (unbuffered) window.
///
/// That buffer stops the day that OWNS the nap from bisecting it, but it does
/// NOT by itself stop the double-count: tomorrow re-detects the post-midnight
/// remainder as a fresh bout starting at index 0 of its own window. See
/// [napLeadingEdgeContiguitySec] for the guard that drops it.
const int napBoundaryBufferSec = 3 * 3600;

/// How close a day's first sample must be to local midnight for the record to
/// count as CONTIGUOUS into the day boundary.
///
/// Within this tolerance, a nap bout beginning at the very first sample is the
/// tail of one yesterday already saw (through [napBoundaryBufferSec]) and
/// emitted whole, so today must not count it again. Beyond it there is a real
/// recording gap at the boundary — yesterday's detector broke on that same
/// discontinuity and dropped the bout too, so today is its only chance to be
/// counted at all.
const int napLeadingEdgeContiguitySec = 60;

class PreparedDerivationPayload {
  final int dataNowSec;
  final List<PreparedDerivationDay> days;

  const PreparedDerivationPayload({
    required this.dataNowSec,
    required this.days,
  });

  Map<String, dynamic> toJson() => {
    'data_now_sec': dataNowSec,
    'days': [for (final day in days) day.toJson()],
  };

  static PreparedDerivationPayload fromJson(Map<String, dynamic> m) {
    final rows = ((m['days'] as List?) ?? const []);
    return PreparedDerivationPayload(
      dataNowSec: (m['data_now_sec'] as num?)?.toInt() ?? 0,
      days: [
        for (final row in rows)
          PreparedDerivationDay.fromJson(
            ((row as Map?) ?? const {}).cast<String, dynamic>(),
          ),
      ],
    );
  }
}

class SleepSessionCandidate {
  final String dayId;
  final double confidence;
  final List<String> flags;
  final Map<String, dynamic> sleepJson;
  final List<String> hypnoStages;
  final int sleepOnsetSec;
  final int sleepOffsetSec;
  final String sleepSource;

  const SleepSessionCandidate({
    required this.dayId,
    required this.confidence,
    required this.flags,
    required this.sleepJson,
    required this.hypnoStages,
    required this.sleepOnsetSec,
    required this.sleepOffsetSec,
    this.sleepSource = 'auto',
  });

  bool get present => sleepJson['tst_sec'] != null;

  Map<String, dynamic> toJson() => {
    'day_id': dayId,
    'confidence': confidence,
    'flags': flags,
    'sleep_json': sleepJson,
    'hypno_stages': hypnoStages,
    'sleep_onset_sec': sleepOnsetSec,
    'sleep_offset_sec': sleepOffsetSec,
    'sleep_source': sleepSource,
  };

  static SleepSessionCandidate fromJson(Map<String, dynamic> m) {
    List<String> strs(String k) =>
        ((m[k] as List?) ?? const []).map((e) => e.toString()).toList();
    return SleepSessionCandidate(
      dayId: m['day_id']?.toString() ?? '',
      confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
      flags: strs('flags'),
      sleepJson: ((m['sleep_json'] as Map?) ?? const {}).cast<String, dynamic>(),
      hypnoStages: strs('hypno_stages'),
      sleepOnsetSec: (m['sleep_onset_sec'] as num?)?.toInt() ?? 0,
      sleepOffsetSec: (m['sleep_offset_sec'] as num?)?.toInt() ?? 0,
      sleepSource: m['sleep_source'] as String? ?? 'auto',
    );
  }

  static SleepSessionCandidate absent(String dayId) => SleepSessionCandidate(
    dayId: dayId,
    confidence: 0,
    flags: const ['NO_SLEEP_DETECTED'],
    sleepJson: const {},
    hypnoStages: const [],
    sleepOnsetSec: 0,
    sleepOffsetSec: 0,
    sleepSource: 'none',
  );

  PreparedDerivationDay toPreparedDay({
    required Substrate daySub,
    required Substrate sleepSub,
    Substrate? napSub,
  }) => PreparedDerivationDay(
    date: dayId,
    // `endSec` is what the engine anchors FINALIZATION on
    // (`endSec + 48 h < dataNowSec` ⇒ lock). An empty substrate used to yield
    // endSec = 0, which makes that comparison unconditionally true — so a day
    // whose raw has been pruned (retention is 3 days) derived an all-absent
    // bundle and wrote it FINALIZED over the good historical row, permanently.
    // With no data, fall back to the day's real calendar end so an empty
    // result is aged exactly like a real one.
    endSec: daySub.lastTs != null
        ? daySub.lastTs! + 1
        : localNextMidnightSecForDayLabel(dayId),
    confidence: confidence,
    flags: flags,
    sleepJson: sleepJson,
    hypnoStages: hypnoStages,
    sleepOnsetSec: sleepOnsetSec,
    sleepOffsetSec: sleepOffsetSec,
    sleepSource: sleepSource,
    daySub: daySub,
    napSub: napSub,
    sleepSub: sleepSub,
  );
}

/// Local midnight at the START OF THE NEXT day for a `YYYY-MM-DD` day label.
///
/// `DateTime(y, m, d + 1)` normalizes the overflow itself and
/// `millisecondsSinceEpoch` respects local DST rules, so this is correct on the
/// two 23 h/25 h days a year — unlike `startOfDay + 86400`.
int localNextMidnightSecForDayLabel(String dayId) {
  final d = DateTime.tryParse(dayId);
  if (d == null) return 0;
  return DateTime(d.year, d.month, d.day + 1).millisecondsSinceEpoch ~/ 1000;
}

void derivationPrepareWorker(SendPort mainSendPort) {
  final port = ReceivePort();
  final state = _PrepareAccumulator();
  String? targetDay;
  var mode = 'prepared_day';
  mainSendPort.send(port.sendPort);

  void handle(Object? message) {
    if (message is! Map) return;
    final type = message['type'];
    if (type == 'page') {
      final frames = ((message['frames'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      if (frames.isNotEmpty) {
        final rr = ((message['rr'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        state.addDecodedPage(frames, rr);
        return;
      }
      final hexes = ((message['hexes'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      state.addRawPage(hexes);
      return;
    }
    if (type == 'config') {
      targetDay = message['target_day']?.toString();
      final cfgMode = message['mode']?.toString();
      if (cfgMode != null && cfgMode.isNotEmpty) mode = cfgMode;
      return;
    }
    if (type == 'finish') {
      try {
        final substrate = state.buildSubstrate();
        if (mode == 'substrate') {
          mainSendPort.send({
            'type': 'result',
            'kind': 'substrate',
            'payload': substrate.toJson(),
          });
        } else {
          final payload = prepareDerivationPayload(
            substrate,
            targetDay: targetDay,
          );
          mainSendPort.send({
            'type': 'result',
            'kind': 'prepared_day',
            'payload': payload.toJson(),
          });
        }
      } finally {
        port.close();
      }
    }
  }

  // EVERY branch is guarded, not just 'finish'. A throw inside the 'page'
  // handler (a malformed SQLite row reaching one of the numeric reads) used to
  // kill this worker silently: the only error report lived in the 'finish'
  // branch, so the main side awaited a Completer that could never complete —
  // `_running` stayed true and DerivationEngine's scheduler never drained
  // again, i.e. ALL derivation was dead until app restart. Now any failure is
  // reported back and the port is closed so the isolate exits.
  port.listen((message) {
    try {
      handle(message);
    } catch (e, st) {
      mainSendPort.send({'type': 'error', 'error': '$e\n$st'});
      port.close();
    }
  });
}

@visibleForTesting
PreparedDerivationPayload prepareDerivationPayload(
  Substrate sub, {
  String? targetDay,
  SleepWindowOverride? override,
  List<({int startSec, int endSec, String dayKey})> priorSleep = const [],
}) {
  if (sub.isEmpty || sub.lastTs == null) {
    return const PreparedDerivationPayload(dataNowSec: 0, days: []);
  }
  final days = <PreparedDerivationDay>[];
  for (final day in calendarDays(
    sub,
    override: override,
    priorSleep: priorSleep,
  )) {
    if (targetDay != null && day.date != targetDay) continue;
    final daySub = sub.slice(day.startSec, day.endSec);
    final napSub = sub.slice(day.startSec, day.endSec + napBoundaryBufferSec);
    final sleepSub = day.hasSleep
        ? sub.sliceIdx(day.sleepLoIdx, day.sleepHiIdx)
        : Substrate.empty;
    final hypno = day.sleep.stages4.isNotEmpty
        ? List<String>.from(day.sleep.stages4)
        : <String>[
            for (final s in day.sleep.stages)
              s == ana.SleepStage.wake
                  ? 'wake'
                  : (s == ana.SleepStage.rem ? 'rem' : 'light'),
          ];
    final win = day.sleep.window;
    final onsetSec = win == null
        ? 0
        : (win.onsetMs != null
              ? (win.onsetMs! / 1000).round()
              : (sleepSub.firstTs ?? 0));
    final offsetSec = win == null
        ? 0
        : (win.offsetMs != null
              ? (win.offsetMs! / 1000).round() + 1
              : ((sleepSub.lastTs ?? -1) + 1));
    days.add(
      PreparedDerivationDay(
        date: day.date,
        endSec: day.endSec,
        confidence: day.confidence,
        flags: List<String>.from(day.flags),
        sleepJson: day.sleep.toJson(),
        hypnoStages: hypno,
        sleepOnsetSec: onsetSec,
        sleepOffsetSec: offsetSec,
        sleepSource: day.sleepSource,
        daySub: daySub,
        sleepSub: sleepSub,
        napSub: napSub,
      ),
    );
  }
  return PreparedDerivationPayload(dataNowSec: sub.lastTs!, days: days);
}

SleepSessionCandidate prepareSleepSessionCandidate(
  Substrate sub, {
  required String targetDay,
  SleepWindowOverride? override,
  List<({int startSec, int endSec, String dayKey})> priorSleep = const [],
}) {
  final payload = prepareDerivationPayload(sub,
      targetDay: targetDay, override: override, priorSleep: priorSleep);
  if (payload.days.isEmpty) return SleepSessionCandidate.absent(targetDay);
  final day = payload.days.first;
  return SleepSessionCandidate(
    dayId: day.date,
    confidence: day.confidence,
    flags: day.flags,
    sleepJson: day.sleepJson,
    hypnoStages: day.hypnoStages,
    sleepOnsetSec: day.sleepOnsetSec,
    sleepOffsetSec: day.sleepOffsetSec,
    sleepSource: day.sleepSource,
  );
}

class _PrepareAccumulator {
  final List<int> tsSec = [];
  final List<int> hr = [];
  final List<double> rrTsMs = [];
  final List<double> rrMs = [];
  final List<double> ax = [];
  final List<double> ay = [];
  final List<double> az = [];
  final List<int> spo2Red = [];
  final List<int> spo2Ir = [];
  final List<int> skinTemp = [];
  final List<int> skinContact = [];

  /// Gen5 on-chip cumulative step counter, `-1` = the record carried none.
  /// See [Substrate.stepCount] for why the sentinel is not 0.
  final List<int> stepCount = [];

  /// Defensive numeric read. The decoded-page rows come straight out of SQLite,
  /// where a column's storage class is per-VALUE, not per-column — a row written
  /// by an older/importing path can hand back a String or null where an INTEGER
  /// is declared. A bare `row['hr'] as num?` throws on that, and a throw in this
  /// worker used to hang the whole engine (see [derivationPrepareWorker]).
  static num? _num(Object? v) => v is num ? v : null;

  void addRawPage(List<String> hexes) {
    if (hexes.isEmpty) return;
    final sub = decodeSubstrate(hexes);
    if (sub.isEmpty) return;
    tsSec.addAll(sub.tsSec);
    hr.addAll(sub.hr);
    rrTsMs.addAll(sub.rrTsMs);
    rrMs.addAll(sub.rrMs);
    ax.addAll(sub.ax);
    ay.addAll(sub.ay);
    az.addAll(sub.az);
    spo2Red.addAll(sub.spo2Red);
    spo2Ir.addAll(sub.spo2Ir);
    skinTemp.addAll(sub.skinTemp);
    skinContact.addAll(sub.skinContact);
    // decodeSubstrate fills -1 for the whole page (gen4 R24 has no counter),
    // but read it rather than assuming, so the arrays stay 1:1 with tsSec.
    stepCount.addAll(sub.stepCount.length == sub.length
        ? sub.stepCount
        : List<int>.filled(sub.length, -1));
  }

  void addDecodedPage(
    List<Map<String, dynamic>> frames,
    List<Map<String, dynamic>> rrRows,
  ) {
    if (frames.isEmpty) return;
    // Associate beats to frames by rec_ts (their shared key). The strap's counter
    // resets on reboot, so grouping by counter mis-joined two seconds that reused
    // one counter within a page.
    final rrByRecTs = <int, List<Map<String, dynamic>>>{};
    for (final row in rrRows) {
      final recTs = _num(row['rec_ts'])?.toInt();
      if (recTs == null) continue;
      rrByRecTs.putIfAbsent(recTs, () => <Map<String, dynamic>>[]).add(row);
    }
    for (final row in frames) {
      final recTs = _num(row['rec_ts'])?.toInt();
      if (recTs == null || recTs <= 0) continue;
      tsSec.add(recTs);
      hr.add(plausibleHrOrZero(_num(row['hr'])?.toInt() ?? 0));
      // The 1 Hz arrays are POSITIONAL — one entry per second, 1:1 with tsSec —
      // so a NULL sensor column (schema v39: absent, never coerced to a real
      // reading) must still occupy its slot. It lands as the array's ABSENT
      // SENTINEL, which is what every reader tests, not as a measurement:
      //   accel  → exact (0, 0, 0), read back through `Substrate.accelPresentAt`
      //            (no real sensor reads 0 g on all three axes — see that doc)
      //   ADC    → 0, read back through the `v > 0` gate every ADC consumer uses
      // Same discipline as `stepCount`'s -1 below.
      ax.add(_num(row['ax'])?.toDouble() ?? 0);
      ay.add(_num(row['ay'])?.toDouble() ?? 0);
      az.add(_num(row['az'])?.toDouble() ?? 0);
      spo2Red.add(_num(row['spo2_red_raw'])?.toInt() ?? 0);
      spo2Ir.add(_num(row['spo2_ir_raw'])?.toInt() ?? 0);
      // gen4 stores skin temp as a raw ADC count (`skin_temp_raw`); gen5 v18
      // decodes it to °C and stores THAT (`skin_temp_c`), leaving skin_temp_raw
      // NULL on every row. Reading only the gen4 column meant a WHOLE gen5
      // install never produced a skin-temp reading and readiness ran on three
      // drivers forever, with the band delivering the measurement all along.
      // Both are only ever used RELATIVE to the user's own baseline (a z), so
      // carry whichever the row has, in centi-°C to stay integral and positive
      // through the `v > 0` gate every ADC consumer uses. A user who swaps
      // gen4 → gen5 mid-history steps the baseline once; the z re-settles.
      final tempRaw = _num(row['skin_temp_raw'])?.toInt();
      final tempC = _num(row['skin_temp_c'])?.toDouble();
      skinTemp.add(tempRaw ?? (tempC == null ? 0 : (tempC * 100).round()));
      // NO skin contact on the decoded path, and no column to read: the byte the
      // name refers to is the sign+exponent half of a float32, never a contact
      // measurement. The array stays 1:1 with tsSec, all-zero ⇒ absent.
      skinContact.add(0);
      // `decoded_onehz.step_count` is NULL on every gen4 row and on any gen5
      // row decoded before schema v34. NULL is ABSENT (-1), not 0: 0 is a real
      // reading from a band that has not moved since its counter last wrapped.
      stepCount.add(_num(row['step_count'])?.toInt() ?? -1);
      final beats = rrByRecTs[recTs];
      if (beats == null) continue;
      for (final beat in beats) {
        final rr = _num(beat['rr_ms'])?.toDouble();
        if (rr == null || rr <= 0) continue;
        rrTsMs.add(_num(beat['rr_ts_ms'])?.toDouble() ?? recTs * 1000.0);
        rrMs.add(rr);
      }
    }
  }

  Substrate buildSubstrate() => Substrate(
    tsSec: tsSec,
    hr: hr,
    rrTsMs: rrTsMs,
    rrMs: rrMs,
    ax: ax,
    ay: ay,
    az: az,
    spo2Red: spo2Red,
    spo2Ir: spo2Ir,
    skinTemp: skinTemp,
    skinContact: skinContact,
    stepCount: stepCount,
  );
}
