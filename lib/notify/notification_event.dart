// notification_event.dart — the single currency of the notification system.
//
// Everything that wants to reach the user (illness onset, recovery ready, a
// wind-down nudge, a step goal) is expressed as ONE NotificationEvent and handed
// to NotificationCenter.emit(), which decides whether it fires an OS
// notification based on the category + the user's NotificationPrefs. (There
// used to also be an in-app notifications feed/screen — removed; OS
// notifications are the only surface now.)
//
// Categories map 1:1 onto OS notification channels (see notification_service)
// so Android users can mute each kind independently. Priority drives the
// quiet-hours decision: `critical` can break through; everything else respects
// the user's quiet window.

enum NotifCategory { health, recovery, reminders, device }

enum NotifPriority { critical, normal, low }

/// The three — and only three — things this app may EMIT into the notification
/// shade. Everything else is an in-app card.
///
/// This governs the present path only. A standing schedule (the weekly
/// lookback, the hydration slots, the nightly sweep) is fired by the OS with no
/// Dart running, never reaches [classOf], and is allow-listed separately — see
/// NotificationService.schedulableIds.
///
/// The app used to be able to emit ~22 distinct kinds across four channels:
/// hydration slots, step goals, posture nudges, "your recovery is ready", AI
/// briefings, an unconditional weekly recap. Sixteen of them were nudges, none
/// aggregated, and a wrist band that buzzes twenty times a day is a band people
/// take off. The rule is now one class per REASON to interrupt:
enum NotifClass {
  /// The band alarm the user armed. It fires on the strap's own RTC, so the
  /// phone notification is a report, not the alarm itself.
  alarm,

  /// Something is wrong right now and the user can do something about it —
  /// the day's aggregated health exception, and the band's own failures (flat
  /// battery, gone quiet). One notification, not one per finding.
  exception,

  /// The weekly lookback, and ONLY when the week actually contained something.
  lookback,
}

/// Which class [e] belongs to, or null for anything that is not one of the
/// three — which [NotificationPrefs.shouldFireOs] then drops.
///
/// Classified from the category, because that is already the axis the emit
/// sites express: health/device signals are exceptions; a `reminders` event at
/// `critical` is the alarm (nothing else is allowed to claim that pair); the
/// `recovery` channel carried "your recovery is ready" and "did you work out?",
/// both nudges, and its genuine findings (low readiness, a shifted resting-HR
/// trend) are folded into the day's health exception at the point they are
/// computed rather than fired one at a time.
NotifClass? classOf(NotificationEvent e) => switch (e.category) {
      NotifCategory.health || NotifCategory.device => NotifClass.exception,
      NotifCategory.reminders
          when e.priority == NotifPriority.critical =>
        NotifClass.alarm,
      NotifCategory.reminders || NotifCategory.recovery => null,
    };

class NotificationEvent {
  /// Idempotency key — used for the feed row id AND to derive a stable OS id, so
  /// the same logical event (e.g. "2026-06-27:illness") never duplicates and a
  /// re-fire replaces in place. Convention: `"$date:$kind"`.
  final String dedupeKey;
  final NotifCategory category;
  final NotifPriority priority;
  final String title;
  final String body;

  /// Deep-link route to open on tap (e.g. '/heart', '/today', '/recap').
  final String? route;

  /// Calendar day this event belongs to (yyyy-m-d), stored on the feed row.
  final String date;

  /// A FIXED OS id this event must be posted on, instead of the allocated one.
  /// Only for a caller that also CANCELS the card later by id — the band
  /// battery/charging alerts, whose "on the charger" card has to disappear when
  /// the puck comes off. Everything else leaves this null and lets
  /// [NotificationIds] allocate.
  final int? osId;

  const NotificationEvent({
    required this.dedupeKey,
    required this.category,
    required this.title,
    required this.body,
    required this.date,
    this.priority = NotifPriority.normal,
    this.route,
    this.osId,
  });

  // The OS notification id is NOT derived here any more. It used to be
  // `categoryBase + dedupeKey.hashCode.abs() % 100000` — a hash modulo, so two
  // distinct dedupeKeys in the same category could map onto the same id, and
  // `_plugin.show` REPLACES rather than stacks: one notification silently
  // vanished. Ids are now allocated collision-free per dedupeKey — see
  // notification_ids.dart (NotificationIds.idFor).
}
