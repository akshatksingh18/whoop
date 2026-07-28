// proximity_policy.dart — pure smoothing/labelling for the "find my band"
// hunt. No BLE types, no timers: samples in, a stable label out.
//
// WHY A POLICY AND NOT AN INLINE READING
// Raw BLE RSSI is brutally noisy. Consecutive reads of a stationary device
// routinely swing 10 dB from multipath alone, and a hand or a duvet between the
// phone and the band costs another 10–20 dB. Painting that straight onto a
// screen gives a number that jitters wildly while you stand still and barely
// moves when you actually walk toward it — the exact opposite of what a hunt
// needs. Two things fix it and both belong in one testable place:
//
//   1. EWMA smoothing, so a single bad read cannot move the label.
//   2. HYSTERESIS on the zone boundaries, so hovering at a threshold does not
//      flicker between "Nearby" and "Close" several times a second.
//
// WHAT RSSI IS NOT
// It is not distance, and this file will not pretend otherwise. There is no
// path-loss-to-metres conversion here on purpose: that conversion needs a
// calibrated TX power and a free-space assumption, and a band down the side of
// a mattress violates the assumption completely. Showing "1.4 m" would be a
// fabricated number in a codebase whose whole contract is not fabricating them.
// Coarse zones plus an honest warmer/colder trend is what the signal can
// actually support, so that is what it reports.

/// How close the band looks, coarsely. Ordered strongest → weakest.
enum ProximityZone {
  /// Within arm's reach — under a pillow, in the bedding, on the desk.
  immediate,

  /// Same room, a few paces away.
  near,

  /// Reachable but attenuated — another room, or buried in something.
  far,

  /// Connected, but the signal is too weak to guide a hunt.
  veryFar,

  /// Not enough samples yet.
  unknown,
}

/// Which way the signal is moving as you walk.
enum ProximityTrend { warmer, colder, steady, unknown }

/// One evaluated reading.
class ProximityReading {
  const ProximityReading({
    required this.zone,
    required this.trend,
    required this.samples,
    this.smoothedRssi,
    this.rawRssi,
  });

  final ProximityZone zone;
  final ProximityTrend trend;

  /// How many samples have been folded in since the last reset.
  final int samples;

  /// EWMA of the raw values, in dBm. Null until the first sample.
  final double? smoothedRssi;

  /// The most recent raw value, in dBm. Shown only as a diagnostic.
  final int? rawRssi;

  /// 0..1 for a signal-strength bar. Maps the useful RSSI band (-95..-45 dBm)
  /// onto the unit interval; deliberately NOT presented as distance.
  double? get strength {
    final s = smoothedRssi;
    if (s == null) return null;
    const worst = -95.0;
    const best = -45.0;
    final t = (s - worst) / (best - worst);
    return t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  }
}

/// Stateful across samples, but pure: no clock, no I/O, no BLE dependency.
class ProximityTracker {
  ProximityTracker({
    this.alpha = 0.35,
    this.hysteresisDb = 3.0,
    this.trendDeadbandDb = 2.0,
    this.trendLookback = 4,
  });

  /// EWMA weight for each new sample. 0.35 settles in roughly five reads —
  /// responsive enough to feel live at ~1.5 Hz polling, damped enough that one
  /// multipath dropout does not jump the label.
  final double alpha;

  /// A zone boundary must be crossed by this much before the label changes.
  /// Without it, a signal sitting exactly on a threshold flickers continuously.
  final double hysteresisDb;

  /// Movement smaller than this is called steady rather than warmer/colder.
  final double trendDeadbandDb;

  /// How many samples back the trend compares against. Too short and the trend
  /// is noise; too long and it lags behind you as you walk.
  final int trendLookback;

  double? _ewma;
  int? _lastRaw;
  int _samples = 0;
  ProximityZone _zone = ProximityZone.unknown;
  final List<double> _history = [];

  /// Last three RAW samples, for the median prefilter below.
  final List<int> _rawWindow = [];

  /// Zone lower bounds in dBm, strongest first. Values are the conventional
  /// BLE proximity bands; they are coarse by design.
  static const _bounds = <(ProximityZone, double)>[
    (ProximityZone.immediate, -60.0),
    (ProximityZone.near, -75.0),
    (ProximityZone.far, -88.0),
  ];

  /// Fold in one RSSI reading (dBm, negative).
  ProximityReading add(int rssi) {
    _lastRaw = rssi;
    _samples++;

    // MEDIAN-OF-3 PREFILTER, ahead of the EWMA. An EWMA alone cannot survive
    // impulse noise: at alpha 0.35 a single -100 dBm dropout (a hand over the
    // band, a multipath null — both common while hunting) drags the average
    // 15 dB in one step, which is enough to repaint the zone and send the user
    // walking the wrong way. A median of the last three RAW samples removes a
    // lone outlier completely while letting any change that persists for two
    // samples through, which is exactly the distinction we want. Below three
    // samples it passes through, so the very first reads still respond
    // immediately instead of sitting inert.
    _rawWindow.add(rssi);
    if (_rawWindow.length > 3) _rawWindow.removeAt(0);
    final filtered = _rawWindow.length < 3
        ? rssi.toDouble()
        : (List<int>.from(_rawWindow)..sort())[1].toDouble();

    final prev = _ewma;
    _ewma = prev == null ? filtered : prev + alpha * (filtered - prev);

    _history.add(_ewma!);
    if (_history.length > trendLookback + 1) _history.removeAt(0);

    _zone = _zoneFor(_ewma!, _zone);
    return ProximityReading(
      zone: _samples >= _minSamplesForZone ? _zone : ProximityZone.unknown,
      trend: _trend(),
      samples: _samples,
      smoothedRssi: _ewma,
      rawRssi: _lastRaw,
    );
  }

  /// Current state without folding in a new sample.
  ProximityReading get current => ProximityReading(
        zone: _samples >= _minSamplesForZone ? _zone : ProximityZone.unknown,
        trend: _trend(),
        samples: _samples,
        smoothedRssi: _ewma,
        rawRssi: _lastRaw,
      );

  /// Forget everything — call when the hunt restarts or the link drops, so a
  /// stale EWMA from the last session cannot seed the new one.
  void reset() {
    _ewma = null;
    _lastRaw = null;
    _samples = 0;
    _zone = ProximityZone.unknown;
    _history.clear();
    _rawWindow.clear();
  }

  /// One sample is not a zone: the first read is as likely to be a multipath
  /// null as the truth.
  static const int _minSamplesForZone = 3;

  /// Hysteresis in both directions: to move to a STRONGER zone the value must
  /// clear that zone's floor by [hysteresisDb]; to fall to a weaker one it must
  /// drop below the current zone's floor by the same margin. Between those it
  /// holds whatever it already showed.
  ProximityZone _zoneFor(double v, ProximityZone currentZone) {
    final bare = _bareZone(v);
    if (currentZone == ProximityZone.unknown) return bare;
    final bareIdx = _index(bare);
    final curIdx = _index(currentZone);
    if (bareIdx == curIdx) return currentZone;

    if (bareIdx < curIdx) {
      // Candidate is a stronger zone — require clearing its floor by the margin.
      final floor = _floorOf(bare);
      return floor == null || v >= floor + hysteresisDb ? bare : currentZone;
    }
    // Candidate is weaker — require dropping below the CURRENT floor by margin.
    final curFloor = _floorOf(currentZone);
    return curFloor == null || v <= curFloor - hysteresisDb ? bare : currentZone;
  }

  static ProximityZone _bareZone(double v) {
    for (final (zone, floor) in _bounds) {
      if (v >= floor) return zone;
    }
    return ProximityZone.veryFar;
  }

  static double? _floorOf(ProximityZone z) {
    for (final (zone, floor) in _bounds) {
      if (zone == z) return floor;
    }
    return null; // veryFar / unknown have no floor
  }

  static int _index(ProximityZone z) => switch (z) {
        ProximityZone.immediate => 0,
        ProximityZone.near => 1,
        ProximityZone.far => 2,
        ProximityZone.veryFar => 3,
        ProximityZone.unknown => 4,
      };

  ProximityTrend _trend() {
    if (_history.length <= trendLookback) return ProximityTrend.unknown;
    final delta = _history.last - _history.first;
    if (delta.abs() < trendDeadbandDb) return ProximityTrend.steady;
    return delta > 0 ? ProximityTrend.warmer : ProximityTrend.colder;
  }
}

/// Display strings, kept beside the model so wording and thresholds stay in
/// step. Deliberately about signal, never about metres.
extension ProximityZoneLabel on ProximityZone {
  String get label => switch (this) {
        ProximityZone.immediate => 'Right here',
        ProximityZone.near => 'Close by',
        ProximityZone.far => 'Somewhere around',
        ProximityZone.veryFar => 'Faint signal',
        ProximityZone.unknown => 'Listening…',
      };

  String get hint => switch (this) {
        ProximityZone.immediate =>
          'Within arm\'s reach — check the bedding, pockets and under cushions.',
        ProximityZone.near => 'You\'re in the right area. Sweep slowly.',
        ProximityZone.far => 'Try another part of the room, or the next one.',
        ProximityZone.veryFar =>
          'Barely in range. Walk around and watch for the signal to climb.',
        ProximityZone.unknown => 'Getting a fix on the signal…',
      };
}

extension ProximityTrendLabel on ProximityTrend {
  String get label => switch (this) {
        ProximityTrend.warmer => 'Warmer',
        ProximityTrend.colder => 'Colder',
        ProximityTrend.steady => 'Steady',
        ProximityTrend.unknown => '',
      };
}
