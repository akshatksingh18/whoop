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
            child: NavBar(l?.alarmNavTitle ?? 'Alarm',
                sub: l?.alarmNavSub ?? 'Wakes you on the band, not the phone'),
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
                          Text(l?.alarmArmedFor ?? 'ARMED FOR',
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
                    l?.alarmNotConnectedTitle ?? 'The band is not connected',
                    l?.alarmNotConnectedBody ??
                        'Setting, testing and cancelling all write to the band, so '
                            'they need a live connection. An alarm that is already '
                            'armed is unaffected — it lives on the band.',
                    icon: LucideIcons.bluetoothOff,
                  )
                else ...[
                  BigButton(
                      at == null
                          ? (l?.alarmSetAnAlarm ?? 'Set an alarm')
                          : (l?.alarmChangeTheTime ?? 'Change the time'),
                      icon: LucideIcons.clock,
                      onTap: () => _pick(c, at)),
                  const SizedBox(height: S.x3),
                  if (at != null) ...[
                    BigButton(l?.alarmTestTheBuzz ?? 'Test the buzz',
                        icon: LucideIcons.vibrate,
                        color: C.blue,
                        soft: true,
                        onTap: () => _run(
                            c, onTest, l?.alarmBuzzingTheBand ?? 'Buzzing the band')),
                    const SizedBox(height: S.x3),
                    BigButton(l?.alarmCancelTheAlarm ?? 'Cancel the alarm',
                        icon: LucideIcons.bellOff,
                        color: C.red,
                        soft: true,
                        onTap: () => _run(
                            c, onCancel, l?.alarmCancelled ?? 'Alarm cancelled')),
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
    final wall = DateTime.now();
    final picked = await showTimePicker(
      context: c,
      initialTime: TimeOfDay.fromDateTime(current ?? wall),
    );
    if (picked == null || !c.mounted) return;
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

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _whichDay(BuildContext c, DateTime d, DateTime now) {
    final l = AppLocalizations.of(c);
    final days = DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days < 0) {
      return l?.alarmInThePast ??
          'In the past — it has already fired or been missed';
    }
    if (days == 0) return l?.alarmLaterToday ?? 'Later today';
    if (days == 1) return l?.alarmTomorrow ?? 'Tomorrow';
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
    return switch (s) {
      AlarmArmState.confirmed => l?.alarmStateConfirmed ?? 'Confirmed',
      AlarmArmState.pending => l?.alarmStateWaiting ?? 'Waiting',
      AlarmArmState.unknown => l?.alarmStateNotConfirmed ?? 'Not confirmed',
      AlarmArmState.none => l?.alarmStateNotSet ?? 'Not set',
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
        l?.alarmHeadlineConfirmed ?? 'The band has this alarm',
      AlarmArmState.pending =>
        l?.alarmHeadlinePending ?? 'Sent — waiting for the band to confirm',
      AlarmArmState.unknown =>
        l?.alarmHeadlineUnknown ?? 'We cannot tell whether this will fire',
      AlarmArmState.none => l?.alarmHeadlineNone ?? 'No alarm is set',
    };
  }

  static String? _stateDetail(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed => l?.alarmDetailConfirmed ??
          'The band reported that it latched the alarm.',
      AlarmArmState.pending => l?.alarmDetailPending ??
          'The write reached the band. Its confirmation usually arrives within '
              'a few seconds.',
      AlarmArmState.unknown => l?.alarmDetailUnknown ??
          'The time above is what this app last sent. The band never confirmed '
              'it — or it was set in an earlier run of the app, and there is no '
              'way to ask the band what it is holding. Set it again while '
              'connected if you need to be sure.',
      AlarmArmState.none => null,
    };
  }
}
