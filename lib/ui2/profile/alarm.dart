// The band alarm.
//
// This screen exists because the alarm is the one thing in the app that keeps
// working when the app does not. It is armed on the STRAP's own real-time
// clock, so it survives the app being killed, the phone rebooting, and the
// phone being out of range entirely. The rebuild shipped with no alarm UI at
// all while `AppState` still restored `alarm_epoch` on launch and still ran the
// confirmation state machine — which means an alarm armed on an older build
// went on firing every morning with nothing anywhere to see it or stop it.
//
// The honesty problem is confirmation. Writing SET_ALARM to the band is not
// evidence that the band latched it; the strap says so separately, by emitting
// event 56, and it might never arrive. And after a relaunch there is no live
// confirmation at all — only the epoch we wrote down. Three different states,
// and the screen says which one it is rather than drawing a confident green
// tick over all three.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../ui2.dart';

/// What we actually know about the armed alarm.
enum AlarmArmState {
  /// Nothing armed.
  none,

  /// Written to the band; its confirmation event may still be in flight.
  pending,

  /// The band emitted ALARM_SET — it latched.
  confirmed,

  /// Armed, but unconfirmed: either the band never acknowledged the write, or
  /// this is an alarm from a previous run of the app and there is no live
  /// confirmation to read. Both mean the same thing to the user — we cannot
  /// promise it will fire — so they share one state rather than being dressed
  /// up as two.
  unknown,
}

class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final epoch = app.alarmEpoch;
    return AlarmScreenView(
      armedAt: epoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch * 1000),
      state: epoch == null
          ? AlarmArmState.none
          : app.alarmConfirmed
              ? AlarmArmState.confirmed
              : app.alarmPending
                  ? AlarmArmState.pending
                  : AlarmArmState.unknown,
      connected: app.isConnected,
      onSet: (when) => app.setAlarm(when),
      onTest: app.testAlarmBuzz,
      onCancel: app.disableAlarm,
    );
  }
}

class AlarmScreenView extends StatelessWidget {
  final DateTime? armedAt;
  final AlarmArmState state;
  final bool connected;

  /// Injectable clock. "Tomorrow" vs "Later today" is relative, so a golden of
  /// this screen is otherwise a function of when the suite happens to run.
  final DateTime? now;

  /// All three talk to the band and all three throw when it is not connected —
  /// the screen reports the failure rather than pretending it worked.
  final Future<void> Function(DateTime when)? onSet;
  final Future<void> Function()? onTest, onCancel;

  const AlarmScreenView({
    super.key,
    this.armedAt,
    this.state = AlarmArmState.none,
    this.connected = false,
    this.now,
    this.onSet,
    this.onTest,
    this.onCancel,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final at = armedAt;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(withEnglishFallback(l).alarmNavTitle,
                sub: withEnglishFallback(l).alarmNavSub),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                if (at != null) ...[
                  Surface(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(withEnglishFallback(l).alarmArmedFor,
                              style: F.over.copyWith(color: p.ink3)),
                          const SizedBox(height: S.x1),
                          Text(_hhmm(at),
                              style: F.n48.copyWith(color: p.ink)),
                          Text(_whichDay(c, at, now ?? DateTime.now()),
                              style: F.cap.copyWith(color: p.ink2)),
                          const SizedBox(height: S.x3),
                          Pill(_localizedStateLabel(c, state), _stateColor(state),
                              icon: _stateIcon(state)),
                        ]),
                  ),
                  if (_stateDetail(c, state) case final detail?) ...[
                    const SizedBox(height: S.x3),
                    StatusCard(_stateHeadline(c, state), detail,
                        icon: _stateIcon(state)),
                  ],
                ],
                const SizedBox(height: S.x4),
                if (!connected)
                  StatusCard(
                    withEnglishFallback(l).alarmNotConnectedTitle,
                    withEnglishFallback(l).alarmNotConnectedBody,
                    icon: LucideIcons.bluetoothOff,
                  )
                else ...[
                  BigButton(
                      at == null
                          ? (withEnglishFallback(l).alarmSetAnAlarm)
                          : (withEnglishFallback(l).alarmChangeTheTime),
                      icon: LucideIcons.clock,
                      onTap: () => _pick(c, at)),
                  const SizedBox(height: S.x3),
                  if (at != null) ...[
                    BigButton(withEnglishFallback(l).alarmTestTheBuzz,
                        icon: LucideIcons.vibrate,
                        color: C.blue,
                        soft: true,
                        onTap: () => _run(
                            c, onTest, withEnglishFallback(l).alarmBuzzingTheBand)),
                    const SizedBox(height: S.x3),
                    BigButton(withEnglishFallback(l).alarmCancelTheAlarm,
                        icon: LucideIcons.bellOff,
                        color: C.red,
                        soft: true,
                        onTap: () => _run(
                            c, onCancel, withEnglishFallback(l).alarmCancelled)),
                  ],
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _pick(BuildContext c, DateTime? current) async {
    final picked = await showTimePicker(
      context: c,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );
    if (picked == null || !c.mounted) return;
    // The clock when the picker CLOSED: a time chosen slowly across its own
    // minute is still "next" from then, not from when it opened (Codex copy).
    final wall = DateTime.now();
    await _run(c, () => onSet!(nextAt(picked.hour, picked.minute, wall)),
        AppLocalizations.of(c)?.alarmSentToBand ?? 'Alarm sent to the band');
  }

  /// The next wall-clock instant at [hour]:[minute], today if it is still
  /// ahead, otherwise tomorrow. CALENDAR arithmetic — `add(Duration(days: 1))`
  /// is 24 elapsed hours, which is a different wall-clock time across a DST
  /// change and would arm the alarm an hour out.
  @visibleForTesting
  static DateTime nextAt(int hour, int minute, DateTime now) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    return today.isAfter(now)
        ? today
        : DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  /// Run a band write and report what happened. Every one of these throws when
  /// the band is not connected, and silence would read as success.
  static Future<void> _run(
      BuildContext c, Future<void> Function()? action, String ok) async {
    if (action == null) return;
    try {
      await action();
      if (c.mounted) _say(c, ok);
    } catch (e) {
      if (c.mounted) _say(c, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  static void _say(BuildContext c, String msg) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

  static String _hhmm(DateTime d) => formatClock(d);

  static String _whichDay(BuildContext c, DateTime d, DateTime now) {
    final l = AppLocalizations.of(c);
    // Calendar days, in UTC so a DST night (23 elapsed hours) is still one
    // day and tomorrow is never "Later today".
    final days = DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    if (!d.isAfter(now)) {
      return withEnglishFallback(l).alarmInThePast;
    }
    if (days == 0) return withEnglishFallback(l).alarmLaterToday;
    if (days == 1) return withEnglishFallback(l).alarmTomorrow;
    return l?.alarmInDays(days) ?? 'In $days days';
  }

  // Kept context-free and @visibleForTesting: the arm-state contract this
  // guards ("only `confirmed` may claim it") is tested without a widget tree.
  @visibleForTesting
  static String stateLabel(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => 'Confirmed',
        AlarmArmState.pending => 'Waiting',
        AlarmArmState.unknown => 'Not confirmed',
        AlarmArmState.none => 'Not set',
      };

  static String _localizedStateLabel(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    if (l == null) return stateLabel(s);
    return switch (s) {
      AlarmArmState.confirmed => l.alarmStateConfirmed,
      AlarmArmState.pending => l.alarmStateWaiting,
      AlarmArmState.unknown => l.alarmStateNotConfirmed,
      AlarmArmState.none => l.alarmStateNotSet,
    };
  }

  static Color _stateColor(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => C.green,
        AlarmArmState.pending => C.blue,
        AlarmArmState.unknown => C.orange,
        AlarmArmState.none => C.blue,
      };

  static IconData _stateIcon(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => LucideIcons.badgeCheck,
        AlarmArmState.pending => LucideIcons.loader,
        AlarmArmState.unknown => LucideIcons.circleHelp,
        AlarmArmState.none => LucideIcons.alarmClock,
      };

  static String _stateHeadline(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed =>
        withEnglishFallback(l).alarmHeadlineConfirmed,
      AlarmArmState.pending =>
        withEnglishFallback(l).alarmHeadlinePending,
      AlarmArmState.unknown =>
        withEnglishFallback(l).alarmHeadlineUnknown,
      AlarmArmState.none => withEnglishFallback(l).alarmHeadlineNone,
    };
  }

  static String? _stateDetail(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed => withEnglishFallback(l).alarmDetailConfirmed,
      AlarmArmState.pending => withEnglishFallback(l).alarmDetailPending,
      AlarmArmState.unknown => withEnglishFallback(l).alarmDetailUnknown,
      AlarmArmState.none => null,
    };
  }
}
