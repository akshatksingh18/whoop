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

  const NotificationEvent({
    required this.dedupeKey,
    required this.category,
    required this.title,
    required this.body,
    required this.date,
    this.priority = NotifPriority.normal,
    this.route,
  });

  /// Stable OS notification id, partitioned by category so a health alert can
  /// never overwrite a reminder (and vice-versa). Bands are 100k apart and start
  /// well above the fixed device/insight ids (< 3000) defined in the service.
  int get osId {
    final base = switch (category) {
      NotifCategory.recovery => 200000,
      NotifCategory.health => 300000,
      NotifCategory.reminders => 400000,
      NotifCategory.device => 100000,
    };
    return base + (dedupeKey.hashCode.abs() % 100000);
  }
}
