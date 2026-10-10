// Pushups day control and reminders (build 86). Every path — the screen,
// Today's row, a notification's Done/Pause, the Home boundary — goes
// through the same idempotent commands here, serialized one at a time.
//
// Reminders are a bounded batch of one-shots: the ordinary reminder one
// interval after Start/Resume/Done, then ten-minute nudges if it is ignored
// (NotificationService.maxPushupNudges of them, topped up on every
// foreground pass from the saved anchor, so the clock never restarts).
//
// A notification action can arrive with WHOOP closed and the phone locked.
// That runs in a background isolate, which never opens the database: it
// writes the action to a small inbox file and moves the reminders using a
// mirror file of the open day. The app merges the inbox on its next pass;
// each action has a receipt, so one tap never counts twice.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import '../notify/notification_event.dart' show NotifCategory;
import '../notify/notification_service.dart';
import '../notify/tap_router.dart' show kRoutePushups;
import 'day_label.dart';
import 'home_region.dart';
import 'pushups.dart';

const String kPushupCategory = 'whoop.pushups.reminder';
const String kPushupDoneAction = 'whoop.pushups.done';
const String kPushupPauseAction = 'whoop.pushups.pause';

/// A notification action, run with WHOOP closed. Must stay top-level.
@pragma('vm:entry-point')
Future<void> pushupNotificationBackground(NotificationResponse r) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  await PushupReminders.onAction(r, background: true);
}

/// The open day as the background handler needs it.
typedef PushupMirror = ({
  String session,
  String day,
  String state,
  int interval,
});

class PushupReminders {
  PushupReminders._();

  static Future<File> _file(String name) async =>
      File('${(await getApplicationSupportDirectory()).path}/$name');

  static Future<void> _writeAtomic(File f, String text) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
  }

  // ── mirror and inbox ──

  static Future<void> writeMirror(PushupSession? s) async {
    try {
      final f = await _file('pushups_live.json');
      if (s == null || !s.isActive) {
        if (await f.exists()) await f.delete();
        return;
      }
      await _writeAtomic(
        f,
        jsonEncode({
          'session': s.id,
          'day': s.day,
          'state': s.state.name,
          'interval': s.interval,
        }),
      );
    } catch (_) {}
  }

  static Future<PushupMirror?> readMirror() async {
    try {
      final f = await _file('pushups_live.json');
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map;
      return (
        session: m['session'] as String,
        day: m['day'] as String,
        state: m['state'] as String,
        interval: (m['interval'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<PushupAction>> readInbox() async {
    try {
      final f = await _file('pushups_inbox.json');
      if (!await f.exists()) return const [];
      return [
        for (final e in jsonDecode(await f.readAsString()) as List)
          PushupAction.fromJson(e as Map),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _addToInbox(PushupAction a) async {
    final f = await _file('pushups_inbox.json');
    final now = await readInbox();
    if (now.any((x) => x.id == a.id)) return;
    await _writeAtomic(
      f,
      jsonEncode([
        for (final x in [...now, a]) x.toJson(),
      ]),
    );
  }

  /// Drop merged actions, re-reading first so one added meanwhile stays.
  static Future<void> _clearInbox(Set<String> done) async {
    try {
      final f = await _file('pushups_inbox.json');
      final left = [
        for (final x in await readInbox())
          if (!done.contains(x.id)) x,
      ];
      if (left.isEmpty) {
        if (await f.exists()) await f.delete();
      } else {
        await _writeAtomic(f, jsonEncode([for (final x in left) x.toJson()]));
      }
    } catch (_) {}
  }

  // ── notification actions ──

  static Future<void> onAction(
    NotificationResponse r, {
    required bool background,
  }) async {
    final q = Uri.tryParse(r.payload ?? '')?.queryParameters ?? const {};
    final sid = q['s'];
    if (sid == null) return;
    final kind = r.actionId == kPushupDoneAction ? 'done' : 'pause';
    final action = PushupAction(
      // One delivery of one batch, one action: replays are no-ops.
      id: '$sid|${r.id}|${q['a']}|$kind',
      kind: kind,
      sessionId: sid,
      at: DateTime.now(),
    );
    if (!background) {
      await Pushups.apply(action);
      return;
    }
    try {
      await _addToInbox(action);
    } catch (_) {
      // Nothing durable to show for it: leave the reminders as they are so
      // the next one asks again rather than pretending the set was logged.
      return;
    }
    final live = await readMirror();
    if (live == null || live.session != sid) return;
    await NotificationService.instance.init();
    if (kind == 'pause') {
      await cancelBatch();
      await _writeMirrorState(live, 'paused');
    } else if (live.state == 'running' && dayLabelOf(action.at) == live.day) {
      await scheduleBatch(sid, action.at.add(Duration(minutes: live.interval)));
    }
  }

  static Future<void> _writeMirrorState(PushupMirror m, String state) async {
    try {
      await _writeAtomic(
        await _file('pushups_live.json'),
        jsonEncode({
          'session': m.session,
          'day': m.day,
          'state': state,
          'interval': m.interval,
        }),
      );
    } catch (_) {}
  }

  // ── the batch ──

  static List<int> get _batchIds => [
    NotificationService.idPushupRegular,
    for (var i = 0; i < NotificationService.maxPushupNudges; i++)
      NotificationService.idPushupNudgeBase + i,
  ];

  static Future<void> cancelBatch() async {
    for (final id in _batchIds) {
      await NotificationService.instance.cancel(id);
    }
  }

  /// The ordinary reminder at [anchor] (when still ahead) and the nudges
  /// after it. Returns false when any request was refused.
  static Future<bool> scheduleBatch(String session, DateTime anchor) async {
    await cancelBatch();
    final now = DateTime.now();
    final payload = Uri(
      path: kRoutePushups,
      queryParameters: {'s': session, 'a': '${anchor.millisecondsSinceEpoch}'},
    ).toString();
    var ok = true;
    if (anchor.isAfter(now)) {
      ok &= await NotificationService.instance.schedulePushup(
        id: NotificationService.idPushupRegular,
        title: 'Pushup time',
        body: 'Do a set, then tap Done.',
        at: anchor,
        payload: payload,
      );
    }
    const step = Duration(minutes: kPushupNudgeMinutes);
    var next = anchor.add(step);
    while (!next.isAfter(now)) {
      next = next.add(step);
    }
    for (var i = 0; i < NotificationService.maxPushupNudges; i++) {
      ok &= await NotificationService.instance.schedulePushup(
        id: NotificationService.idPushupNudgeBase + i,
        title: 'Pushup set still due',
        body: 'Do a set, then tap Done to get back to your normal interval.',
        at: next.add(step * i),
        payload: payload,
      );
    }
    if (!ok) await cancelBatch();
    return ok;
  }

  /// How many of this batch's requests iOS still holds; null when unknown.
  static Future<int?> pendingInBatch() async {
    final ids = await NotificationService.instance.pendingIds();
    if (ids == null) return null;
    return _batchIds.where(ids.contains).length;
  }

  static Future<void> setDailyStart(bool on) async {
    if (!on) {
      await NotificationService.instance.cancel(
        NotificationService.idPushupDailyStart,
      );
      return;
    }
    await NotificationService.instance.scheduleDaily(
      id: NotificationService.idPushupDailyStart,
      category: NotifCategory.reminders,
      title: 'Pushups',
      body: "Start your day when you're ready.",
      hour: 9,
      minute: 0,
      route: kRoutePushups,
    );
  }
}

/// Why reminders are not running as the day says they should.
enum PushupHealth { ok, blocked, repair }

/// Everything the Pushups screen and Today's row show.
class PushupStatus {
  PushupStatus({
    required this.active,
    required this.sessions,
    required this.interval,
    required this.goal,
    required this.health,
    required this.inboxWaiting,
  });

  final PushupSession? active;
  final List<PushupSession> sessions;
  final int interval, goal;
  final PushupHealth health;
  final int inboxWaiting;

  int get today {
    final d = dayLabelOf(DateTime.now());
    return sessions
        .where((s) => s.day == d)
        .fold<int>(0, (n, s) => n + s.count);
  }

  ({int current, int best}) get streaks =>
      pushupStreaks(sessions, DateTime.now());
}

class Pushups {
  Pushups._();

  static Future<void> _chain = Future.value();

  /// Run [f] after every command before it, one at a time.
  static Future<T> _serial<T>(Future<T> Function() f) {
    final next = _chain.then((_) => f());
    _chain = next.then<void>((_) {}, onError: (Object e, StackTrace st) {});
    return next;
  }

  static Future<void> _commit(PushupSession s) async {
    await PushupDb.save(s);
    await PushupReminders.writeMirror(s);
  }

  /// Reminders for [s] from its saved anchor; false when iOS refused them.
  static Future<bool> _arm(PushupSession s) async {
    final a = s.anchor;
    if (s.state != PushupState.running || a == null) {
      await PushupReminders.cancelBatch();
      return true;
    }
    return PushupReminders.scheduleBatch(s.id, a);
  }

  static Future<PushupStatus> status() async {
    final sessions = await PushupDb.all();
    final active = sessions.where((s) => s.isActive).lastOrNull;
    var health = PushupHealth.ok;
    if (active?.state == PushupState.running) {
      if (!await NotificationService.instance.ensurePermission(
        allowPrompt: false,
      )) {
        health = PushupHealth.blocked;
      } else if ((await PushupReminders.pendingInBatch() ?? 1) == 0) {
        health = PushupHealth.repair;
      }
    }
    return PushupStatus(
      active: active,
      sessions: sessions,
      interval: await PushupDb.interval(),
      goal: await PushupDb.goal(),
      health: health,
      inboxWaiting: (await PushupReminders.readInbox()).length,
    );
  }

  /// Start my day. With [paused] the day opens paused until Resume (for
  /// starting while away from Home). Returns the open day.
  static Future<PushupSession> start({bool paused = false}) =>
      _serial(() async {
        final open = await PushupDb.active();
        if (open != null) return open;
        await NotificationService.instance.ensurePermission();
        final now = DateTime.now();
        final goal = await PushupDb.goal();
        final s = PushupSession(
          day: dayLabelOf(now),
          started: now,
          interval: await PushupDb.interval(),
          goal: goal > 0 ? goal : null,
          state: paused ? PushupState.paused : PushupState.running,
          pauseReason: paused ? kHomeAwayReason : null,
        );
        if (!paused) s.anchor = now.add(Duration(minutes: s.interval));
        if (paused) {
          s.log(
            PushupEvent(
              at: now,
              kind: PushupEventKind.pause,
              source: kHomeAwayReason,
            ),
          );
        }
        await _commit(s);
        await PushupReminders.setDailyStart(false);
        await _arm(s);
        return s;
      });

  static Future<void> pause({String source = 'manual'}) => _serial(() async {
    final s = await PushupDb.active();
    if (s == null) return;
    if (s.state == PushupState.running || s.pauseReason != source) {
      s.log(
        PushupEvent(
          at: DateTime.now(),
          kind: PushupEventKind.pause,
          source: source,
        ),
      );
    }
    s.state = PushupState.paused;
    s.pauseReason = source;
    s.anchor = null;
    await _commit(s);
    await PushupReminders.cancelBatch();
  });

  /// Resume with a fresh full interval. A manual resume while known to be
  /// outside Home stops leaving from pausing it again until the next arrival.
  static Future<void> resume({String source = 'manual'}) => _serial(() async {
    final s = await PushupDb.active();
    if (s == null || s.state != PushupState.paused) return;
    final now = DateTime.now();
    s.log(PushupEvent(at: now, kind: PushupEventKind.resume, source: source));
    s.state = PushupState.running;
    s.pauseReason = null;
    s.anchor = now.add(Duration(minutes: s.interval));
    await _commit(s);
    if (source == 'manual' && await HomeRegion.boundary() != null) {
      final a = await HomeRegion.automation();
      if (a.presence == HomePresence.outside) {
        a.suppressExit = true;
        await HomeRegion.saveAutomation(a);
      }
    }
    await _arm(s);
  });

  /// One completed set. A running day starts a fresh full interval from it.
  static Future<void> done({String source = 'app'}) => _serial(() async {
    final s = await PushupDb.active();
    if (s == null) return;
    final now = DateTime.now();
    if (!s.log(
      PushupEvent(at: now, kind: PushupEventKind.done, source: source),
    )) {
      return;
    }
    if (s.state == PushupState.running) {
      s.anchor = now.add(Duration(minutes: s.interval));
    }
    await _commit(s);
    await _arm(s);
  });

  static Future<void> undo() => _serial(() async {
    final s = await PushupDb.active();
    if (s == null || !s.undo()) return;
    await _commit(s);
  });

  /// End my day. Returns the ended day.
  static Future<PushupSession?> end() => _serial(() async {
    final s = await PushupDb.active();
    if (s == null) return null;
    s.state = PushupState.ended;
    s.ended = DateTime.now();
    s.anchor = null;
    await _commit(s);
    await PushupReminders.cancelBatch();
    await PushupReminders.setDailyStart(true);
    return s;
  });

  /// Apply one action (a notification's Done/Pause) once.
  static Future<void> apply(PushupAction a) => _serial(() async {
    final s = await PushupDb.active();
    if (s == null || !a.applyTo(s)) return;
    await _commit(s);
    await _arm(s);
  });

  /// The foreground and relaunch pass: merge notification actions taken
  /// while WHOOP was closed, apply Home boundary events, close a day left
  /// open past midnight, and make the reminders match the day again from
  /// its saved anchor.
  static Future<void> reconcile() => _serial(() async {
    var s = await PushupDb.active();
    // Actions taken while closed.
    final inbox = await PushupReminders.readInbox();
    if (inbox.isNotEmpty) {
      final merged = <String>{};
      for (final a in inbox) {
        if (s != null && a.applyTo(s)) await PushupDb.save(s);
        merged.add(a.id);
      }
      await PushupReminders._clearInbox(merged);
    }
    // Home boundary events, oldest first.
    final events = await HomeRegion.drain();
    if (events.isNotEmpty && await HomeRegion.boundary() != null) {
      final auto = await HomeRegion.automation();
      for (final e in events) {
        final what = auto.accept(
          e.presence,
          e.at,
          active: s,
          today: dayLabelOf(DateTime.now()),
        );
        if (s == null) continue;
        if (what == 'pause') {
          s.log(
            PushupEvent(
              at: e.at,
              kind: PushupEventKind.pause,
              source: kHomeAwayReason,
            ),
          );
          s.state = PushupState.paused;
          s.pauseReason = kHomeAwayReason;
          s.anchor = null;
        } else if (what == 'resume') {
          final now = DateTime.now();
          s.log(
            PushupEvent(
              at: now,
              kind: PushupEventKind.resume,
              source: kHomeAwayReason,
            ),
          );
          s.state = PushupState.running;
          s.pauseReason = null;
          s.anchor = now.add(Duration(minutes: s.interval));
        }
      }
      await HomeRegion.saveAutomation(auto);
    }
    // A day still open after its own midnight ends at that midnight.
    final now = DateTime.now();
    if (s != null && s.day != dayLabelOf(now)) {
      final d = DateTime.parse(s.day);
      final midnight = DateTime(d.year, d.month, d.day + 1);
      s.state = PushupState.ended;
      s.ended = midnight.isAfter(now) ? now : midnight;
      s.anchor = null;
    }
    if (s != null) await _commit(s);
    if (s == null || !s.isActive) {
      await PushupReminders.writeMirror(null);
      await PushupReminders.cancelBatch();
      // The 9:00 invitation only once Pushups has been used.
      final any = (await PushupDb.all()).isNotEmpty;
      await PushupReminders.setDailyStart(any);
      return;
    }
    await PushupReminders.setDailyStart(false);
    if (s.state != PushupState.running) {
      await PushupReminders.cancelBatch();
      return;
    }
    // Top up a low or drained batch from the saved anchor; the clock stays.
    final left = await PushupReminders.pendingInBatch();
    if (left == null || left < NotificationService.maxPushupNudges ~/ 2) {
      await _arm(s);
    }
  });

  /// After "Delete everything": stop the Home watch and every reminder.
  static Future<void> reset() async {
    await HomeRegion.clear();
    await PushupReminders.writeMirror(null);
    try {
      final f = await PushupReminders._file('pushups_inbox.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
