// charge_alert_policy.dart — decides whether a "charging started" band event is
// NEWS (worth buzzing the user) or NOISE (a backlog replay of something that
// already happened).
//
// WHY THIS EXISTS (issue #179 — "repeated 'band is on the charger' well after
// the charger was removed"):
//
// The strap buffers its event log in flash and dumps it on connect, and it
// re-sends events that were already delivered. Both are measurable in a real
// user export: 410 of 6,980 events arrived more than an hour after they
// occurred (worst case 8h26m, an 8-hour backlog dumped in ~90 s), and 140
// distinct (event_id, ts) pairs were delivered more than once — up to 4× —
// with a different frame `seq` each time, so nothing upstream de-dupes them.
// `db.dart`'s insertEvent already notes "the band re-sends events", and
// GestureDispatcher already carries a recency window for exactly this reason
// ("older than this = a drained/historical tap"). The charging alert never got
// the same treatment: it fired on any false→true edge, with the edge state held
// only in RAM — so every Android process restart (EdgeApplication pre-warm,
// KeepAliveWorker, FGS START_STICKY) re-armed it and the next replayed
// chargingOn buzzed again.
//
// Two independent guards, because neither is sufficient alone:
//   • RECENCY — an event describing a plug-in from hours ago is not news.
//     Handles first-time delivery of a stale backlogged event.
//   • IDENTITY — never announce a charge session at or before the last one
//     already announced, persisted across process restarts. Handles exact
//     re-sends and restart-driven re-arming, both of which are recent enough
//     to pass the recency check.
//
// Pure and synchronous: the caller owns the clock, the persisted values and the
// notification plugin. See device_alerts.dart for the wiring.

/// Why a charging event did (or did not) raise an alert. Returned instead of a
/// bare bool so the caller can log the reason — the failure this fixes was
/// invisible in logs precisely because nothing recorded WHY a notification
/// fired.
enum ChargeAlertVerdict {
  /// Genuine new charge session — show the notification.
  announce,

  /// We already believe we are charging (in-process edge state) — the strap
  /// re-sent chargingOn, or another field on the same DeviceState changed and
  /// re-delivered the unchanged charging flag.
  alreadyCharging,

  /// The event describes a plug-in that happened long enough ago that it is
  /// history, not news — a flash-backlog replay.
  stale,

  /// This exact charge session was already announced (same or older strap
  /// timestamp than the last announcement) — a re-send, or a fresh process
  /// re-processing an event the previous process already alerted on.
  alreadyAnnounced,

  /// The event carries no usable timestamp AND we announced recently enough
  /// that another alert would be a duplicate.
  cooldown,
}

class ChargeAlertPolicy {
  const ChargeAlertPolicy._();

  /// How recent a chargingOn event must be to count as news.
  ///
  /// Deliberately generous. The point is to reject the HOURS-stale backlog
  /// dump, not to demand instant delivery: in the same real export, genuine
  /// first-delivery charging events lagged 0 s, 105 s and 226 s behind the
  /// strap timestamp (the app reconnecting a few minutes after the puck went
  /// on). A tight window would silence those real alerts and fix nothing —
  /// exact replays are caught by the identity check below, not by this one.
  static const int liveWindowSec = 900; // 15 min

  /// Above this age a timestamp is not evidence of anything — the strap ships
  /// with its RTC unset and can wander before SET_CLOCK lands. We refuse to
  /// judge staleness from it (mirrors GestureDispatcher's `_plausibleAgeCapSec`)
  /// and fall back to the untimed path.
  static const int implausibleAgeSec = 86400;

  /// Below this a strap timestamp is clearly a wrong/unset RTC rather than a
  /// real unix time — the same plausible-unix floor the sync clock policies use.
  static const int plausibleUnixFloor = 1700000000;

  /// Tolerance for a strap clock that reads slightly AHEAD of the phone. Inside
  /// this the event is still "now"; beyond it the timestamp is not usable.
  static const int futureSlackSec = 300;

  /// Minimum gap between alerts when the event carries no usable timestamp, so
  /// an unset-RTC strap can't buzz on every reconnect.
  static const int untimedCooldownSec = 3600; // 1 h

  /// The identity check is not applied to an announcement older than this.
  ///
  /// Without an expiry, a strap clock that jumps BACKWARDS (into a still-
  /// plausible range, so the floor above doesn't catch it) would leave every
  /// future session comparing `<=` against a high-water timestamp that never
  /// gets beaten — charging alerts would go permanently silent, a worse and far
  /// less visible bug than the one being fixed. Expiring the comparison costs
  /// nothing: a replay old enough to reach this point is already rejected by
  /// the recency window.
  static const int identityExpirySec = 43200; // 12 h

  /// Whether [tsEpoch] can be trusted as a real strap wall-clock reading.
  static bool timestampUsable(int? tsEpoch, {required int wallNowSec}) {
    if (tsEpoch == null || tsEpoch < plausibleUnixFloor) return false;
    final age = wallNowSec - tsEpoch;
    if (age < -futureSlackSec) return false; // strap clock ahead of the phone
    return age < implausibleAgeSec;
  }

  /// Decide whether a chargingOn edge should raise a notification.
  ///
  /// [eventTsEpoch] is the strap timestamp of the event that set `charging`
  /// (null when unknown). [wasCharging] is the in-process edge state (null =
  /// nothing seen yet this process). [lastAnnouncedEventTs] and
  /// [lastAnnouncedWallSec] are the persisted results of the previous
  /// announcement — they are what survives an Android process restart.
  static ChargeAlertVerdict evaluate({
    required int? eventTsEpoch,
    required int wallNowSec,
    required bool? wasCharging,
    required int? lastAnnouncedEventTs,
    required int? lastAnnouncedWallSec,
  }) {
    if (wasCharging == true) return ChargeAlertVerdict.alreadyCharging;

    if (!timestampUsable(eventTsEpoch, wallNowSec: wallNowSec)) {
      // No usable strap clock → we cannot tell news from replay. Fall back to a
      // blunt wall-clock cooldown rather than guessing.
      if (lastAnnouncedWallSec != null &&
          wallNowSec - lastAnnouncedWallSec < untimedCooldownSec) {
        return ChargeAlertVerdict.cooldown;
      }
      return ChargeAlertVerdict.announce;
    }

    final ts = eventTsEpoch!;
    if (wallNowSec - ts > liveWindowSec) return ChargeAlertVerdict.stale;

    final identityLive = lastAnnouncedWallSec == null ||
        wallNowSec - lastAnnouncedWallSec <= identityExpirySec;
    if (identityLive &&
        lastAnnouncedEventTs != null &&
        ts <= lastAnnouncedEventTs) {
      return ChargeAlertVerdict.alreadyAnnounced;
    }
    return ChargeAlertVerdict.announce;
  }
}
