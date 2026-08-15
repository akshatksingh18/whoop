// Data models shared across the app.

/// One decoded 1 Hz record (type-24 / R10): timestamp + counter + HR, plus the
/// sensor fields (RR beats, accel, SpO₂ raw, skin-temp raw) decoded ON-DEVICE
/// via proto.parseR24 — the app is local-first and owns the full sensor decode
/// (see LocalDb._queueDecodedOneHz); raw hex is kept as the replay ledger.
class Sample {
  final int tsEpoch;
  final int counter;
  final int hr; // 0 = off-wrist (never display as a heart rate)
  final List<int> rrIntervalsMs;
  final double? ax;
  final double? ay;
  final double? az;
  final int? spo2RedRaw;
  final int? spo2IrRaw;
  final int? skinTempRaw;

  // ── Fields only a gen5 band sends (all null on gen4) ───────────────────────
  // NULL means "this band never reported it", and that is NOT the same as zero:
  // a fabricated 0-step day or a 0 °C skin temperature reads as real data
  // downstream. Every one of these stays nullable end to end, into the DB.

  /// Cumulative step count from the band's own pedometer, which runs whether or
  /// not the app is connected. Monotonic — it does NOT reset at midnight, so a
  /// day's steps are a difference between two records, never the value itself.
  final int? stepCount;

  /// The band's own cadence for this second (steps/min).
  final int? stepCadence;

  /// The band's own activity class: 0 = not committed to a class yet (NOT
  /// "still" — do not count it as sedentary), 1 = walk, 2 = run. Null when the
  /// band reported no valid class at all; a class is never invented from an
  /// out-of-range code.
  final int? activityClass;

  /// Calibrated skin temperature in °C, as computed by the band. Unlike
  /// [skinTempRaw] (an uncalibrated ADC count that needs days of personal
  /// baseline before it means anything) this is usable on its first second.
  final double? skinTempC;

  /// The band's own on-wrist determination for this second (2-bit code).
  final int? onWrist;

  /// The band's own "HR and RR are valid this second" flag.
  final bool? hrValid;

  /// A second heart-rate byte the band reports alongside [hr]. It CORROBORATES
  /// [hr] (agreement runs ~58-75%, best when [hrValid]); it is not a substitute
  /// heart rate and must never be displayed as one.
  final int? hrAlt;

  Sample({
    required this.tsEpoch,
    required this.counter,
    required this.hr,
    this.rrIntervalsMs = const [],
    this.ax,
    this.ay,
    this.az,
    this.spo2RedRaw,
    this.spo2IrRaw,
    this.skinTempRaw,
    this.stepCount,
    this.stepCadence,
    this.activityClass,
    this.skinTempC,
    this.onWrist,
    this.hrValid,
    this.hrAlt,
  });

  /// Copy with an overridden [tsEpoch] — used by the clock-offset salvage path
  /// (a wandering/unset strap RTC offsets every record by the same amount, so a
  /// corrected+grid-snapped time is stamped back onto the decoded sample). All
  /// other decoded fields are preserved.
  Sample copyWith({int? tsEpoch}) => Sample(
    tsEpoch: tsEpoch ?? this.tsEpoch,
    counter: counter,
    hr: hr,
    rrIntervalsMs: rrIntervalsMs,
    ax: ax,
    ay: ay,
    az: az,
    spo2RedRaw: spo2RedRaw,
    spo2IrRaw: spo2IrRaw,
    skinTempRaw: skinTempRaw,
    stepCount: stepCount,
    stepCadence: stepCadence,
    activityClass: activityClass,
    skinTempC: skinTempC,
    onWrist: onWrist,
    hrValid: hrValid,
    hrAlt: hrAlt,
  );

  bool get wristOn => hr > 0;
  bool get hasDecodedOneHz =>
      ax != null &&
      ay != null &&
      az != null &&
      spo2RedRaw != null &&
      spo2IrRaw != null &&
      skinTempRaw != null;

  Map<String, dynamic> toDbMap() => {
    'ts': tsEpoch,
    'counter': counter,
    'hr': hr,
  };

  factory Sample.fromDbMap(Map<String, dynamic> m) => Sample(
    tsEpoch: m['ts'] as int,
    counter: m['counter'] as int,
    hr: m['hr'] as int,
  );

  /// One `decoded_onehz` row → [Sample]. Missing/NULL columns stay null (a gen4
  /// row carries none of the band-computed fields), never 0.
  factory Sample.fromDecodedRow(Map<String, Object?> m) {
    final valid = (m['hr_valid'] as num?)?.toInt();
    return Sample(
      tsEpoch: (m['rec_ts'] as num).toInt(),
      counter: (m['counter'] as num?)?.toInt() ?? 0,
      hr: (m['hr'] as num?)?.toInt() ?? 0,
      stepCount: (m['step_count'] as num?)?.toInt(),
      stepCadence: (m['step_cadence'] as num?)?.toInt(),
      activityClass: (m['activity_class'] as num?)?.toInt(),
      skinTempC: (m['skin_temp_c'] as num?)?.toDouble(),
      onWrist: (m['on_wrist'] as num?)?.toInt(),
      hrValid: valid == null ? null : valid != 0,
      hrAlt: (m['hr_alt'] as num?)?.toInt(),
    );
  }
}

/// A raw historical record exactly as it came off the band — the source of truth.
/// We keep this even when decode succeeds so the cloud can re-decode opaque bytes.
class RawRecord {
  final int
  counter; // u32 @[3:7] for header records; 0 for counter-less live packets
  final int packetType; // inner[0]: 0x2F historical, 0x2B/0x28/0x33 live
  final String hex; // full inner bytes, hex — the idempotency key
  final int
  capturedAt; // epoch ms we received it (STORAGE age — used for pruning)
  final bool uploaded;
  // The record's REAL device timestamp, epoch SECONDS. This — not capturedAt —
  // is what the DerivationEngine buckets/windows days by, so a multi-day flash
  // backfill (all received in one sync, one capturedAt≈now) still splits into the
  // correct per-real-day buckets. Null here means "decode at insert / fall back to
  // capturedAt/1000"; the DB column is always non-null.
  final int? recTs;

  RawRecord({
    required this.counter,
    this.packetType = 0,
    required this.hex,
    required this.capturedAt,
    this.uploaded = false,
    this.recTs,
  });
}

/// A historical record we RECEIVED off the band but could NOT decode (an
/// unknown/unsupported record version that also failed the physiological
/// fallback). Rather than silently dropping it — which would lose a future
/// firmware's records forever while the UI still showed a clean sync — we
/// archive the raw bytes durably (never pruned) so they can be re-decoded once
/// the format is understood. Archived as part of the SAME durable commit that
/// runs BEFORE the HISTORY_END ACK, so the safe-trim invariant holds.
/// [ArchiveRecord.reason] for a record the plausibility gate refused.
///
/// Load-bearing, not a label: three separate decisions branch on it — whether
/// the burst counts as offload progress, whether the band may be told to trim,
/// and whether a derive pass is scheduled. A typo in any one of them either
/// wedges the offload or lets the band erase data we distrusted, so the string
/// exists once.
const String kGateDroppedReason = 'gate_dropped';

class ArchiveRecord {
  final int counter;
  final String hex; // full inner bytes, hex
  final int packetType; // inner[0]: 0x2F historical (the only archived kind)
  final int? recTs; // decoded record time if any survived; usually null
  final int capturedAt; // epoch ms we received it
  final String reason; // e.g. 'undecodable_v<version>'

  ArchiveRecord({
    required this.counter,
    required this.hex,
    required this.packetType,
    required this.capturedAt,
    required this.reason,
    this.recTs,
  });
}

/// Live, in-memory device state (not persisted; rebuilt each connection).
class DeviceState {
  String? address;
  String? serial;
  double? batteryPct;
  bool? charging;

  /// Strap timestamp (unix sec) of the chargingOn/chargingOff EVENT that last
  /// set [charging] — null when unknown.
  ///
  /// [charging] alone cannot distinguish "the puck just went on" from "the strap
  /// replayed a chargingOn out of its flash backlog hours later" (see
  /// charge_alert_policy.dart). It is deliberately kept beside the flag rather
  /// than folded into it: the flag is still the LATEST KNOWN charging state and
  /// the UI should show it, while anything that treats the transition as a live
  /// event (notifications) has to check the age first.
  int? chargingTs;

  bool? wristOn;
  int? liveHr; // latest live HR from the foreground stream
  int? liveHrAt; // epoch ms
  int?
  alarmEpoch; // current strap alarm (unix sec) from GET_ALARM_TIME, if read
  String?
  strapName; // strap advertising name (editable via SET_ADVERTISING_NAME)
  String connection; // 'disconnected' | 'scanning' | 'connecting' | 'connected'

  // ── resumable-sync / reconnect-health flags ──────────────────────────────────
  /// MarginalRadioDetector tripped: the BT radio can't sustain the R10/R11 raw
  /// stream — next connect should stick to standard HR only.
  bool standardHrFallback = false;
  /// PostBondTimeoutLoopDetector tripped (#617): bond-then-instant-timeout loop —
  /// surface the re-pair guide to the user.
  bool needsRepairGuide = false;
  /// Monotonic count of bond REFUSALS this process (the createBond call the band
  /// rejects — link reachable but encryption denied). AppState feeds the delta
  /// into a BondRefusalGiveUp policy so a band that keeps refusing pauses the
  /// auto-reconnect loop instead of hammering the radio + draining battery.
  int bondRefusals = 0;
  /// BondRefusalGiveUp tripped: too many consecutive bond refusals in a row — the
  /// auto-reconnect loop is PAUSED (it would just pin the radio + drain the
  /// battery on a band that will never accept the bond). A manual user connect /
  /// re-pair still runs createBond and clears this on a successful bond.
  bool autoReconnectPaused = false;
  /// EmptySyncTracker tripped: ≥3 consecutive console-only offloads — the strap's
  /// RTC has likely lost sync.
  bool syncClockLost = false;
  /// StuckStrapDetector tripped: frontier frozen while the strap is ahead — a
  /// defensive reboot/clock-reset was attempted.
  bool strapNeedsReboot = false;
  /// Strap's own banked-data window from GET_DATA_RANGE (unix sec), for the
  /// session-relative plausibility gate + the UI's "history available" readout.
  int? dataRangeOldest;
  int? dataRangeNewest;
  /// Which WHOOP generation this connection is speaking — `'gen4'` or
  /// `'gen5'`, set once at service discovery (see `BleEngine._doConnect`'s
  /// `session.applyBand`). Null until a link has been established at least
  /// once this process. Lets the UI show "WHOOP 5 connected" and gate any
  /// gen5-only controls (e.g. a deep-buffer opt-in toggle) without reaching
  /// into the transport layer.
  String? generation;

  DeviceState({this.connection = 'disconnected'});
}
