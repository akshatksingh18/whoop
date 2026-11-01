// The Notifications page's record of what this app put on the phone
// (Build 95, Akshat: "a notification panel which shows all of our
// notifications date wise chronologically"). A tapped notification used to
// vanish with nothing in the app to go back to.
//
// Two ways in, because two kinds of notification exist:
//   • shown now (NotificationService.presentEvent) — recorded as it is shown;
//   • scheduled (zonedSchedule) — iOS fires these with no Dart running, so
//     each schedule is written down as a PLAN, and an occurrence is recorded
//     once its time has passed (at launch, on every return to the app, and
//     before the plan is cancelled or replaced, so nothing that already
//     fired is lost).
//
// On this phone only, in preferences, for 90 days. Never uploaded, and not
// part of a backup.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/day_label.dart';
import 'tap_router.dart';

/// What the app can establish, not proof the person saw a banner.
enum NotificationOrigin { submitted, scheduled, unknown }

/// One submitted notification or inferred due occurrence.
class LoggedNotification {
  /// Stable for the life of the entry; what marks one read.
  final String key;
  final DateTime at;
  final String title;
  final String body;

  /// Where tapping it goes, as the notification's own payload.
  final String? route;

  /// `NotifCategory.name`, for the row's icon.
  final String category;
  final bool read;
  final NotificationOrigin origin;

  const LoggedNotification({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
    required this.category,
    this.route,
    this.read = false,
    this.origin = NotificationOrigin.unknown,
  });

  LoggedNotification asRead() => LoggedNotification(
    key: key,
    at: at,
    title: title,
    body: body,
    category: category,
    route: route,
    read: true,
    origin: origin,
  );

  Map<String, Object?> toJson() => {
    'k': key,
    'at': at.millisecondsSinceEpoch,
    't': title,
    'b': body,
    'c': category,
    if (route != null) 'r': route,
    if (read) 'read': true,
    'origin': origin.name,
  };

  static LoggedNotification? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = j['at'], key = j['k'], title = j['t'];
    if (at is! int || key is! String || title is! String) return null;
    return LoggedNotification(
      key: key,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      title: title,
      body: j['b'] is String ? j['b'] as String : '',
      category: j['c'] is String ? j['c'] as String : 'reminders',
      route: j['r'] is String ? j['r'] as String : null,
      read: j['read'] == true,
      origin:
          NotificationOrigin.values
              .where((v) => v.name == j['origin'])
              .firstOrNull ??
          NotificationOrigin.unknown,
    );
  }
}

/// How a scheduled notification repeats.
enum PlanRepeat { once, daily, weekly }

class NotificationLog {
  NotificationLog._();
  static final NotificationLog instance = NotificationLog._();

  static const String _kLog = 'notify.log';
  static const String _kPlans = 'notify.plans';
  static const Duration keep = Duration(days: 90);

  /// Unread entries, for the bell on Today.
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// Bumped on every change, so an open page re-reads.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Test seam for "now".
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  Future<void> _chain = Future<void>.value();
  bool _needsReload = false;

  Future<void> _authoritative(SharedPreferences p) async {
    if (!_needsReload) return;
    await p.reload();
    _needsReload = false;
  }

  Future<void> _save(SharedPreferences p, String key, String value) async {
    await _authoritative(p);
    try {
      if (!await p.setString(key, value)) {
        throw StateError('Notification history could not save');
      }
    } catch (_) {
      // SharedPreferences mutates its cache before persistence completes.
      // A refused/throwing write must never make Retry trust that cache.
      _needsReload = true;
      try {
        await _authoritative(p);
      } catch (_) {}
      rethrow;
    }
  }

  /// Serialised: a present and a reconcile landing together must not each
  /// read the list, add one, and write back over the other.
  Future<T> _locked<T>(Future<T> Function() f) {
    final run = _chain.then((_) => f());
    _chain = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<List<LoggedNotification>> _read(SharedPreferences p) async {
    await _authoritative(p);
    try {
      final raw = p.getString(_kLog);
      if (raw == null) return [];
      return [
        for (final j in jsonDecode(raw) as List)
          ?LoggedNotification.fromJson(j),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(SharedPreferences p, List<LoggedNotification> all) async {
    final cutoff = clock().subtract(keep);
    final kept = [
      for (final e in all)
        if (e.at.isAfter(cutoff)) e,
    ]..sort((a, b) => b.at.compareTo(a.at));
    final encoded = jsonEncode([for (final e in kept) _dated(e).toJson()]);
    final old = p.getString(_kLog);
    final changed = old != encoded && (old != null || kept.isNotEmpty);
    if (changed) await _save(p, _kLog, encoded);
    unread.value = kept.where((e) => !e.read).length;
    if (changed) revision.value++;
  }

  LoggedNotification _dated(LoggedNotification e) {
    if (e.route == null || routePath(e.route!) != '/food') return e;
    return LoggedNotification(
      key: e.key,
      at: e.at,
      title: e.title,
      body: e.body,
      category: e.category,
      read: e.read,
      origin: e.origin,
      route: datedRoute(
        kRouteFoodDay,
        dayLabelAtSec(e.at.millisecondsSinceEpoch ~/ 1000),
      ),
    );
  }

  /// Newest first, the last 90 days.
  Future<List<LoggedNotification>> entries() => _locked(() async {
    await _reconcile();
    final p = await SharedPreferences.getInstance();
    final all = await _read(p);
    final cutoff = clock().subtract(keep);
    final out = [
      for (final e in all)
        if (e.at.isAfter(cutoff)) e,
    ]..sort((a, b) => b.at.compareTo(a.at));
    await _write(p, out);
    return [for (final e in out) _dated(e)];
  });

  /// Record a notification shown now.
  Future<void> record({
    required String title,
    required String body,
    required String category,
    String? route,
    DateTime? at,
  }) => _locked(() async {
    try {
      final when = at ?? clock();
      final p = await SharedPreferences.getInstance();
      final all = await _read(p)
        ..add(
          LoggedNotification(
            key: 'n${when.microsecondsSinceEpoch}',
            at: when,
            title: title,
            body: body,
            category: category,
            route: route,
            origin: NotificationOrigin.submitted,
          ),
        );
      await _write(p, all);
    } catch (_) {}
  });

  // ── scheduled notifications ──────────────────────────────────────────────

  Future<Map<String, Map<String, Object?>>> _plans(SharedPreferences p) async {
    await _authoritative(p);
    try {
      final raw = p.getString(_kPlans);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map(
        (k, v) => MapEntry(k as String, (v as Map).cast<String, Object?>()),
      );
    } catch (_) {
      return {};
    }
  }

  /// The occurrences of [plan] in (after, upTo], oldest first.
  @visibleForTesting
  static List<DateTime> occurrences(
    DateTime first,
    PlanRepeat repeat,
    DateTime after,
    DateTime upTo,
  ) {
    final out = <DateTime>[];
    var t = first;
    if (repeat != PlanRepeat.once && t.isBefore(after)) {
      final days = DateTime.utc(
        after.year,
        after.month,
        after.day,
      ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
      final jump = repeat == PlanRepeat.weekly ? (days ~/ 7) * 7 : days;
      t = DateTime(
        first.year,
        first.month,
        first.day + jump,
        first.hour,
        first.minute,
      );
    }
    // Calendar steps, not fixed hours, so a DST change keeps the wall time.
    DateTime step(DateTime d) => switch (repeat) {
      PlanRepeat.daily => DateTime(
        d.year,
        d.month,
        d.day + 1,
        d.hour,
        d.minute,
      ),
      PlanRepeat.weekly => DateTime(
        d.year,
        d.month,
        d.day + 7,
        d.hour,
        d.minute,
      ),
      PlanRepeat.once => d,
    };
    for (var i = 0; i < 400 && !t.isAfter(upTo); i++) {
      if (t.isAfter(after)) out.add(t);
      if (repeat == PlanRepeat.once) break;
      t = step(t);
    }
    return out;
  }

  /// Record every planned occurrence whose time has passed. [only] limits it
  /// to one notification id (before that plan is replaced or cancelled).
  Future<void> reconcile({int? only}) => _locked(() => _reconcile(only: only));

  Future<void> _reconcile({int? only}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final plans = await _plans(p);
      final now = clock();
      final floor = now.subtract(keep);
      final all = await _read(p);
      final keys = {for (final e in all) e.key};
      for (final MapEntry(key: id, value: plan) in plans.entries.toList()) {
        if (only != null && id != '$only') continue;
        final first = DateTime.fromMillisecondsSinceEpoch(plan['first'] as int);
        final done = DateTime.fromMillisecondsSinceEpoch(
          (plan['done'] as int?) ?? first.millisecondsSinceEpoch - 1,
        );
        final repeat = PlanRepeat.values.byName(plan['repeat'] as String);
        final after = done.isBefore(floor) ? floor : done;
        for (final t in occurrences(first, repeat, after, now)) {
          final key = 's$id-${t.millisecondsSinceEpoch}';
          if (!keys.add(key)) continue;
          all.add(
            LoggedNotification(
              key: key,
              at: t,
              title: plan['title'] as String,
              body: (plan['body'] as String?) ?? '',
              category: (plan['category'] as String?) ?? 'reminders',
              route: plan['route'] as String?,
              origin: NotificationOrigin.scheduled,
            ),
          );
        }
        if (repeat == PlanRepeat.once && !first.isAfter(now)) {
          plans.remove(id);
        } else {
          plans[id] = {...plan, 'done': now.millisecondsSinceEpoch};
        }
      }
      // History must commit before the processed watermark. A failed watermark
      // write can replay safely because occurrence keys are stable.
      await _write(p, all);
      await _save(p, _kPlans, jsonEncode(plans));
    } catch (_) {}
  }

  /// A notification [id] was handed to iOS for [first] (and every day or
  /// week after, for a repeat). Replaces any earlier plan for the same id,
  /// after recording what that one already showed.
  Future<void> plan({
    required int id,
    required DateTime first,
    required PlanRepeat repeat,
    required String title,
    required String body,
    required String category,
    String? route,
  }) => _locked(() async {
    try {
      await _reconcile(only: id);
      final p = await SharedPreferences.getInstance();
      final plans = await _plans(p);
      plans['$id'] = {
        'first': first.millisecondsSinceEpoch,
        'repeat': repeat.name,
        'title': title,
        'body': body,
        'category': category,
        'route': ?route,
      };
      await _save(p, _kPlans, jsonEncode(plans));
    } catch (_) {}
  });

  /// [id] was cancelled: what already fired stays in the log.
  Future<void> unplan(int id) => _locked(() async {
    try {
      await _reconcile(only: id);
      final p = await SharedPreferences.getInstance();
      final plans = await _plans(p);
      if (plans.remove('$id') != null) {
        await _save(p, _kPlans, jsonEncode(plans));
      }
    } catch (_) {}
  });

  // ── read state ────────────────────────────────────────────────────────────

  Future<void> markRead(String key) => _locked(() async {
    final p = await SharedPreferences.getInstance();
    final all = await _read(p);
    final i = all.indexWhere((e) => e.key == key && !e.read);
    if (i < 0) return;
    all[i] = all[i].asRead();
    await _write(p, all);
  });

  /// A notification was opened from the phone's own list: its newest unread
  /// entry with the same route reads as read here too.
  Future<void> markRouteRead(String route) => _locked(() async {
    try {
      await _reconcile();
      final p = await SharedPreferences.getInstance();
      final all = await _read(p)
        ..sort((a, b) => b.at.compareTo(a.at));
      final i = all.indexWhere(
        (e) =>
            !e.read &&
            (e.route == route ||
                (routePath(route) == '/food' &&
                    e.route != null &&
                    routePath(e.route!) == kRouteFoodDay)),
      );
      if (i < 0) return;
      all[i] = all[i].asRead();
      await _write(p, all);
    } catch (_) {}
  });

  Future<void> markAllRead() => _locked(() async {
    final p = await SharedPreferences.getInstance();
    final all = await _read(p);
    await _write(p, [for (final e in all) e.read ? e : e.asRead()]);
  });

  /// "Delete everything": the log and the plans go with the data.
  Future<void> clear() => _locked(() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kLog);
      await p.remove(_kPlans);
      unread.value = 0;
      revision.value++;
    } catch (_) {}
  });
}
