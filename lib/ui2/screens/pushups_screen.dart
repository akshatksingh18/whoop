// Pushups (build 86): the movement-break day from AkshatOS Pushup Reminder,
// inside Train. One state card with the next scheduled reminder, sets today
// against the daily goal with its streak, Log a set with Undo, the day's
// lifecycle (Start my day · Pause · Resume · End my day), the day's logged
// sets, History, Home auto-pause and Settings. Plain words; a Done is one
// completed set, never reps, minutes or calories.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/home_region.dart';
import '../../data/pushup_reminders.dart';
import '../../data/pushups.dart';
import '../charts.dart';
import '../grammar.dart';
import '../theme.dart';
import 'metric_detail.dart' show detailScaffold;
import 'today_plan.dart' show PlanRow;

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _span(Duration d) {
  final m = d.inMinutes;
  return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
}

String _dayTitle(String day) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = DateTime.parse(day);
  return '${d.day} ${months[d.month - 1]}';
}

Future<void> _push(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

class PushupsScreen extends StatefulWidget {
  const PushupsScreen({super.key});
  @override
  State<PushupsScreen> createState() => _PushupsScreenState();
}

class _PushupsScreenState extends State<PushupsScreen> {
  PushupStatus? _s;
  HomeBoundary? _home;
  HomeAutomation? _auto;
  bool _busy = false, _openLog = false;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    PushupDb.changes.addListener(_load);
    // The countdown moves; a minute is its finest step.
    _tick = Timer.periodic(Motion.tick * 30, (_) {
      if (mounted) setState(() {});
    });
    unawaited(Pushups.reconcile().then((_) => _load()));
  }

  @override
  void dispose() {
    PushupDb.changes.removeListener(_load);
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await Pushups.status();
    final h = await HomeRegion.boundary();
    final a = await HomeRegion.automation();
    if (mounted) setState(() => (_s = s, _home = h, _auto = a));
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => (_busy = true, _error = null));
    try {
      await f();
    } catch (e) {
      _error = '$e'.replaceFirst(RegExp(r'^\w+Error: '), '');
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    // Known to be away from Home: ask rather than guess.
    if (_home != null && _auto?.presence == HomePresence.outside) {
      final paused = await confirmRemove(
        context,
        title: "You're away from Home",
        body:
            'Start paused until you get back, or start reminders now. '
            'Arriving home resumes a day started paused.',
        remove: 'Start paused',
        keep: 'Start reminders now',
      );
      return _run(() => Pushups.start(paused: paused));
    }
    return _run(Pushups.start);
  }

  Future<void> _end() async {
    final ok = await confirmRemove(
      context,
      title: 'End your day?',
      body: 'Reminders stop. You can start again today if you need to.',
      remove: 'End my day',
      keep: 'Not yet',
    );
    if (!ok || !mounted) return;
    PushupSession? ended;
    await _run(() async => ended = await Pushups.end());
    if (!mounted || ended == null) return;
    final day = PushupDay.of(
      ended!.day,
      _s?.sessions ?? [ended!],
      DateTime.now(),
    );
    if (day != null) await _push(context, PushupDayScreen(day: day));
  }

  @override
  Widget build(BuildContext c) {
    final s = _s;
    return detailScaffold(c, 'Pushups', [
      if (s == null)
        const Padding(
          padding: EdgeInsets.all(S.x8),
          child: Center(child: CircularProgressIndicator()),
        )
      else ...[
        _stateCard(c, s),
        const SizedBox(height: S.x3),
        _setsCard(c, s),
        const SizedBox(height: S.x3),
        _goalCard(c, s),
        if (_error != null) ...[
          const SizedBox(height: S.x2),
          Text(_error!, style: F.cap.copyWith(color: P.of(c).on(C.red))),
        ],
        const SizedBox(height: S.x3),
        _loggedToday(c, s),
        const SizedBox(height: S.x5),
        _links(c, s),
      ],
    ]);
  }

  Widget _stateCard(BuildContext c, PushupStatus s) {
    final p = P.of(c);
    final a = s.active;
    final now = DateTime.now();
    final (String title, String sub, Color color) = switch ((
      a?.state,
      s.health,
    )) {
      (null, _) => (
        'Not started',
        'Start your day to get a reminder every ${s.interval} min.',
        C.n500,
      ),
      (PushupState.running, PushupHealth.blocked) => (
        'Reminders are blocked',
        'Notifications are off for WHOOP. Sets you log still count.',
        C.red,
      ),
      (PushupState.running, PushupHealth.repair) => (
        'Reminders are missing',
        'iOS holds none for this day. Re-arm them below.',
        C.orange,
      ),
      (PushupState.running, _) => (
        'Running',
        () {
          final due = pushupNextDue(a!, now);
          if (due == null) return 'Every ${a.interval} min.';
          final nudge = a.anchor != null && !a.anchor!.isAfter(now);
          final left = due.difference(now);
          return '${nudge ? 'Reminder due · next nudge' : 'Next reminder'} '
              '${_hm(due)} (scheduled) · in ${left.inMinutes < 1 ? 'under a minute' : _span(left)}';
        }(),
        C.green,
      ),
      (PushupState.paused, _) => (
        'Paused',
        a!.pauseReason == kHomeAwayReason
            ? 'Paused because you left Home. Arriving home resumes it.'
            : 'No reminders until you resume. Sets still count.',
        C.yellow,
      ),
      (PushupState.ended, _) => ('Ended', '', C.n500),
    };
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Pill(title, color),
              const Spacer(),
              if (s.inboxWaiting > 0)
                Text(
                  '${s.inboxWaiting} waiting to merge',
                  style: F.over.copyWith(color: p.ink3),
                ),
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: S.x2),
            Text(sub, style: F.cap.copyWith(color: p.ink2)),
          ],
          const SizedBox(height: S.x3),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              if (a == null)
                _button(
                  c,
                  'Start my day',
                  LucideIcons.play,
                  _start,
                  primary: true,
                ),
              if (a?.state == PushupState.running)
                _button(
                  c,
                  'Pause',
                  LucideIcons.pause,
                  () => _run(Pushups.pause),
                ),
              if (a?.state == PushupState.paused)
                _button(
                  c,
                  'Resume',
                  LucideIcons.play,
                  () => _run(Pushups.resume),
                  primary: true,
                ),
              if (s.health == PushupHealth.repair)
                _button(
                  c,
                  'Re-arm reminders',
                  LucideIcons.bellRing,
                  () => _run(Pushups.reconcile),
                ),
              if (s.health == PushupHealth.blocked)
                _button(
                  c,
                  'Open Settings',
                  LucideIcons.settings2,
                  () => Geolocator.openAppSettings(),
                ),
              if (a != null) _button(c, 'End my day', LucideIcons.flag, _end),
            ],
          ),
          if (a?.state == PushupState.running) ...[
            const SizedBox(height: S.x2),
            Text(
              'Focus modes and Scheduled Summary can delay or silence reminders.',
              style: F.over.copyWith(color: p.ink3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _setsCard(BuildContext c, PushupStatus s) {
    final p = P.of(c);
    final n = s.today;
    final goal = s.active?.goal ?? (s.goal > 0 ? s.goal : null);
    final status = n == 0
        ? 'No sets yet'
        : goal == null
        ? '$n ${n == 1 ? 'set' : 'sets'} today'
        : n >= goal
        ? 'Goal reached'
        : '$n of $goal · ${goal - n} to go';
    return Surface(
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: Ring(
                    goal == null ? 0 : (n / goal).clamp(0.0, 1.0),
                    p.on(C.orange),
                    p.track,
                    stroke: 7,
                    solid: true,
                  ),
                ),
                Text('$n', style: F.n24.copyWith(color: p.ink)),
              ],
            ),
          ),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sets today', style: F.cap.copyWith(color: p.ink3)),
                Text(status, style: F.body.copyWith(color: p.ink)),
                if (s.active != null && s.active!.count > 0)
                  Pressable(
                    semanticLabel: 'Undo the last set',
                    onTap: () => _run(Pushups.undo),
                    child: Padding(
                      padding: const EdgeInsets.only(top: S.x1),
                      child: Text(
                        'Undo last set',
                        style: F.cap.copyWith(color: p.ink2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (s.active != null)
            Pressable(
              semanticLabel: 'Log a set',
              onTap: () => _run(Pushups.done),
              child: Pill('Log a set', C.orange, icon: LucideIcons.plus),
            ),
        ],
      ),
    );
  }

  Widget _goalCard(BuildContext c, PushupStatus s) {
    final p = P.of(c);
    final st = s.streaks;
    final goal = s.active?.goal ?? (s.goal > 0 ? s.goal : null);
    final n = s.today;
    final line = goal == null
        ? 'The streak is off. Set a daily goal in Settings.'
        : n >= goal
        ? 'Reached today.'
        : st.current > 0
        ? '${goal - n} more ${goal - n == 1 ? 'set keeps' : 'sets keep'} the streak (at risk today).'
        : '${goal - n} more ${goal - n == 1 ? 'set' : 'sets'} reach today\'s goal.';
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Daily goal', style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(height: S.x2),
          Row(
            children: [
              _stat(c, '${st.current}', 'day streak'),
              _stat(c, '${st.best}', 'best'),
              _stat(c, goal == null ? 'Off' : '$goal', 'sets a day'),
            ],
          ),
          const SizedBox(height: S.x2),
          Text(line, style: F.cap.copyWith(color: p.ink2)),
        ],
      ),
    );
  }

  Widget _stat(BuildContext c, String v, String label) {
    final p = P.of(c);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v, style: F.n24.copyWith(color: p.ink)),
          Text(label, style: F.over.copyWith(color: p.ink3)),
        ],
      ),
    );
  }

  Widget _loggedToday(BuildContext c, PushupStatus s) {
    final p = P.of(c);
    final today = dayLabelOf(DateTime.now());
    final times = [
      for (final x in s.sessions)
        if (x.day == today) ...x.completions,
    ]..sort();
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            semanticLabel: _openLog ? 'Hide logged sets' : 'Show logged sets',
            onTap: () => setState(() => _openLog = !_openLog),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Logged today · ${times.length}',
                      style: F.body.copyWith(color: p.ink),
                    ),
                  ),
                  Icon(
                    _openLog ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 18,
                    color: p.ink3,
                  ),
                ],
              ),
            ),
          ),
          if (_openLog)
            for (var i = 0; i < times.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: S.x2),
                child: Text(
                  'Set ${i + 1} · ${_hm(times[i])}',
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ),
        ],
      ),
    );
  }

  Widget _links(BuildContext c, PushupStatus s) {
    final p = P.of(c);
    final days = PushupDay.all(s.sessions, DateTime.now()).length;
    Widget row(IconData icon, String title, String sub, VoidCallback onTap) =>
        Pressable(
          semanticLabel: title,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(
              children: [
                Icon(icon, size: 18, color: p.ink2),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: F.body.copyWith(color: p.ink)),
                      Text(sub, style: F.over.copyWith(color: p.ink3)),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
              ],
            ),
          ),
        );
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(
        children: [
          row(
            LucideIcons.history,
            'History',
            '$days ${days == 1 ? 'day' : 'days'} kept',
            () => _push(c, PushupHistoryScreen(sessions: s.sessions)),
          ),
          Divider(color: p.line, height: 1),
          row(
            LucideIcons.house,
            'Home auto-pause',
            _home == null
                ? 'Off'
                : _auto?.presence == HomePresence.outside
                ? 'On · away from Home'
                : 'On',
            () async {
              await _push(c, const HomeSetupScreen());
              await _load();
            },
          ),
          Divider(color: p.line, height: 1),
          row(
            LucideIcons.settings2,
            'Settings',
            'Every ${s.interval} min · ${s.goal == 0 ? 'streak off' : '${s.goal} sets a day'}',
            () async {
              await _push(
                c,
                PushupSettingsScreen(canEditInterval: s.active == null),
              );
              await _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _button(
    BuildContext c,
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool primary = false,
  }) => Pressable(
    semanticLabel: label,
    onTap: _busy ? null : onTap,
    child: Pill(label, primary ? C.orange : C.n500, icon: icon),
  );
}

/// One day's recap: sets, goal result, start and end, active and paused
/// time, the completion times and pauses, and the interval used.
class PushupDayScreen extends StatelessWidget {
  const PushupDayScreen({super.key, required this.day});
  final PushupDay day;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final goal = day.goal;
    final result = switch (day.status) {
      PushupGoalStatus.reached =>
        'Goal reached: this day counts for the streak.',
      PushupGoalStatus.atRisk =>
        '${goal! - day.sets} short of the goal. The day is not over, so the streak is at risk, not broken.',
      PushupGoalStatus.missed =>
        '${goal! - day.sets} short of the goal of $goal.',
      PushupGoalStatus.notSet => 'No goal that day.',
    };
    Widget line(String a, String b) => Padding(
      padding: const EdgeInsets.only(top: S.x2),
      child: Row(
        children: [
          Expanded(
            child: Text(a, style: F.cap.copyWith(color: p.ink3)),
          ),
          Text(b, style: F.cap.copyWith(color: p.ink)),
        ],
      ),
    );
    return detailScaffold(c, _dayTitle(day.day), [
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${day.sets} ${day.sets == 1 ? 'set' : 'sets'}'
              '${goal == null ? '' : ' of $goal'}',
              style: F.n24.copyWith(color: p.ink),
            ),
            const SizedBox(height: S.x1),
            Text(result, style: F.cap.copyWith(color: p.ink2)),
            const SizedBox(height: S.x2),
            line('Started', _hm(day.started)),
            line('Ended', day.ended == null ? 'Still open' : _hm(day.ended!)),
            line('Active', _span(day.active)),
            line(
              'Paused',
              '${_span(day.paused)} · ${day.pauses.length} '
                  '${day.pauses.length == 1 ? 'pause' : 'pauses'}',
            ),
            line('Interval', day.intervals.map((m) => '$m min').join(', ')),
          ],
        ),
      ),
      const SizedBox(height: S.x3),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sets', style: F.cap.copyWith(color: p.ink3)),
            if (day.completions.isEmpty)
              Text('None logged.', style: F.cap.copyWith(color: p.ink2)),
            for (var i = 0; i < day.completions.length; i++)
              line('Set ${i + 1}', _hm(day.completions[i])),
            if (day.pauses.isNotEmpty) ...[
              const SizedBox(height: S.x3),
              Text('Pauses', style: F.cap.copyWith(color: p.ink3)),
              for (final x in day.pauses)
                line(
                  '${_hm(x.from)} – ${_hm(x.to)}',
                  _span(x.to.difference(x.from)),
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: S.x2),
      Text(
        'Only sets you marked Done count. Reminders iOS showed are not counted.',
        style: F.over.copyWith(color: p.ink3),
      ),
    ]);
  }
}

/// Every day kept, one dropdown per month, newest month open.
class PushupHistoryScreen extends StatefulWidget {
  const PushupHistoryScreen({super.key, required this.sessions});
  final List<PushupSession> sessions;
  @override
  State<PushupHistoryScreen> createState() => _PushupHistoryScreenState();
}

class _PushupHistoryScreenState extends State<PushupHistoryScreen> {
  String? _open;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final days = PushupDay.all(widget.sessions, DateTime.now());
    final months = <String, List<PushupDay>>{};
    for (final d in days) {
      (months[d.day.substring(0, 7)] ??= []).add(d);
    }
    final open = _open ?? months.keys.firstOrNull;
    return detailScaffold(c, 'Pushup history', [
      if (days.isEmpty)
        Text('No days yet.', style: F.cap.copyWith(color: p.ink3)),
      for (final e in months.entries) ...[
        Pressable(
          semanticLabel: 'Month ${e.key}',
          onTap: () => setState(() => _open = open == e.key ? '' : e.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dayTitle('${e.key}-01').split(' ').last +
                        ' ${e.key.substring(0, 4)}',
                    style: F.body.copyWith(color: p.ink),
                  ),
                ),
                Text(
                  '${e.value.fold<int>(0, (n, d) => n + d.sets)} sets',
                  style: F.cap.copyWith(color: p.ink3),
                ),
                const SizedBox(width: S.x2),
                Icon(
                  open == e.key
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 18,
                  color: p.ink3,
                ),
              ],
            ),
          ),
        ),
        if (open == e.key)
          for (final d in e.value)
            Pressable(
              semanticLabel: '${_dayTitle(d.day)}, ${d.sets} sets',
              onTap: () => _push(c, PushupDayScreen(day: d)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x2),
                child: Row(
                  children: [
                    Icon(
                      d.status == PushupGoalStatus.reached
                          ? LucideIcons.circleCheck
                          : LucideIcons.circle,
                      size: 16,
                      color: d.status == PushupGoalStatus.reached
                          ? p.on(C.green)
                          : p.ink3,
                    ),
                    const SizedBox(width: S.x2),
                    Expanded(
                      child: Text(
                        _dayTitle(d.day),
                        style: F.cap.copyWith(color: p.ink),
                      ),
                    ),
                    Text(
                      '${d.sets}${d.goal == null ? '' : ' / ${d.goal}'}',
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                  ],
                ),
              ),
            ),
        Divider(color: p.line, height: 1),
      ],
    ]);
  }
}

class PushupSettingsScreen extends StatefulWidget {
  const PushupSettingsScreen({super.key, required this.canEditInterval});
  final bool canEditInterval;
  @override
  State<PushupSettingsScreen> createState() => _PushupSettingsScreenState();
}

class _PushupSettingsScreenState extends State<PushupSettingsScreen> {
  int? _interval, _goal;
  String? _note;

  @override
  void initState() {
    super.initState();
    () async {
      final i = await PushupDb.interval(), g = await PushupDb.goal();
      if (mounted) setState(() => (_interval = i, _goal = g));
    }();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final i = _interval, g = _goal;
    Widget choice(String label, bool on, VoidCallback? tap) => Pressable(
      semanticLabel: label,
      onTap: tap,
      child: Pill(label, on ? C.orange : C.n500),
    );
    return detailScaffold(c, 'Pushup settings', [
      if (i == null || g == null)
        const Center(child: CircularProgressIndicator())
      else ...[
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reminder every', style: F.cap.copyWith(color: p.ink3)),
              const SizedBox(height: S.x2),
              Wrap(
                spacing: S.x2,
                runSpacing: S.x2,
                children: [
                  for (final m in const [30, 45, 60, 90])
                    choice(
                      '$m min',
                      i == m,
                      widget.canEditInterval
                          ? () async {
                              await PushupDb.setInterval(m);
                              setState(() => _interval = m);
                            }
                          : null,
                    ),
                ],
              ),
              if (!widget.canEditInterval)
                Padding(
                  padding: const EdgeInsets.only(top: S.x2),
                  child: Text(
                    'Change it when no day is open.',
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ),
              const SizedBox(height: S.x4),
              Text('Daily goal', style: F.cap.copyWith(color: p.ink3)),
              const SizedBox(height: S.x2),
              Wrap(
                spacing: S.x2,
                runSpacing: S.x2,
                children: [
                  for (final n in const [0, 4, 6, 8, 10, 12])
                    choice(n == 0 ? 'Off' : '$n sets', g == n, () async {
                      await PushupDb.setGoal(n);
                      setState(() => _goal = n);
                    }),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: S.x2),
                child: Text(
                  'A new goal applies from your next day; earlier days keep theirs.',
                  style: F.over.copyWith(color: p.ink3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        Pressable(
          semanticLabel: 'Delete completed history',
          onTap: () async {
            final ok = await confirmRemove(
              c,
              title: 'Delete completed Pushups history?',
              body: 'Every ended day goes. An open day and your settings stay.',
              remove: 'Delete',
            );
            if (!ok) return;
            final n = await PushupDb.deleteHistory();
            if (mounted) setState(() => _note = '$n days deleted.');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Text(
              'Delete completed history',
              style: F.cap.copyWith(color: p.on(C.red)),
            ),
          ),
        ),
        if (_note != null) Text(_note!, style: F.cap.copyWith(color: p.ink2)),
        Text(
          'Import or export Pushups history from Settings → Your data.',
          style: F.over.copyWith(color: p.ink3),
        ),
      ],
    ]);
  }
}

/// Home auto-pause: use where you are now as Home, pick a radius, and allow
/// Always location. Shows honestly when it would not work.
class HomeSetupScreen extends StatefulWidget {
  const HomeSetupScreen({super.key});
  @override
  State<HomeSetupScreen> createState() => _HomeSetupScreenState();
}

class _HomeSetupScreenState extends State<HomeSetupScreen> {
  HomeBoundary? _saved;
  HomeRegionStatus _status = const HomeRegionStatus();
  ({double lat, double lon, double accuracy})? _here;
  double _radius = HomeRegion.defaultRadius;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await HomeRegion.boundary();
    final st = await HomeRegion.status();
    if (mounted) {
      setState(() {
        _saved = b;
        _status = st;
        if (b != null) _radius = b.radius;
      });
    }
  }

  Future<void> _locate() async {
    setState(() => (_busy = true, _error = null));
    try {
      final h = await HomeRegion.here();
      if (mounted) setState(() => _here = h);
    } catch (e) {
      _error = '$e'.replaceFirst('Bad state: ', '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final h = _here;
    if (h == null) return;
    setState(() => (_busy = true, _error = null));
    try {
      final auth = await HomeRegion.requestAlways();
      await HomeRegion.setHome((lat: h.lat, lon: h.lon, radius: _radius));
      if (auth != 'always') {
        _error =
            'Saved, but WHOOP has location only while open. Choose Always in Settings for it to work when closed.';
      }
    } catch (e) {
      _error = '$e'.replaceFirst('Invalid argument(s): ', '');
    } finally {
      await _load();
      if (mounted) setState(() => (_busy = false, _here = null));
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final saved = _saved;
    return detailScaffold(c, 'Home auto-pause', [
      Text(
        'Leaving Home pauses a running Pushups day. Arriving home resumes it, '
        'but only if leaving paused it. A pause you chose is never undone by '
        'arriving. WHOOP is told only when you cross the boundary; it keeps '
        'no record of where you go, and Home stays on this phone.',
        style: F.cap.copyWith(color: p.ink2),
      ),
      const SizedBox(height: S.x3),
      if (saved != null)
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Pill(
                    _status.healthy ? 'Working' : 'Not working',
                    _status.healthy ? C.green : C.orange,
                  ),
                  const Spacer(),
                  Text(
                    '${saved.radius.round()} m',
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                ],
              ),
              if (_status.problem case final why?) ...[
                const SizedBox(height: S.x2),
                Text(why, style: F.cap.copyWith(color: p.ink2)),
                Pressable(
                  semanticLabel: 'Open Settings',
                  onTap: () => Geolocator.openAppSettings(),
                  child: Padding(
                    padding: const EdgeInsets.only(top: S.x2),
                    child: Text(
                      'Open Settings',
                      style: F.cap.copyWith(color: p.on(C.blue)),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: S.x2),
              Text(
                'Boundary events are approximate and can arrive minutes late. '
                'Pause and Resume always work by hand.',
                style: F.over.copyWith(color: p.ink3),
              ),
            ],
          ),
        ),
      const SizedBox(height: S.x3),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              saved == null ? 'Set Home' : 'Move Home',
              style: F.body.copyWith(color: p.ink),
            ),
            const SizedBox(height: S.x2),
            if (_here == null)
              Pressable(
                semanticLabel: 'Use my current location as Home',
                onTap: _busy ? null : _locate,
                child: const Pill(
                  'Use my current location',
                  C.blue,
                  icon: LucideIcons.mapPin,
                ),
              )
            else ...[
              Text(
                'Located to within ${_here!.accuracy.round()} m.',
                style: F.cap.copyWith(color: p.ink2),
              ),
              const SizedBox(height: S.x2),
              Text('Radius', style: F.cap.copyWith(color: p.ink3)),
              const SizedBox(height: S.x1),
              Wrap(
                spacing: S.x2,
                runSpacing: S.x2,
                children: [
                  for (final r in const [100.0, 150.0, 250.0, 500.0])
                    Pressable(
                      semanticLabel: '${r.round()} metres',
                      onTap: () => setState(() => _radius = r),
                      child: Pill(
                        '${r.round()} m',
                        _radius == r ? C.orange : C.n500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: S.x3),
              Pressable(
                semanticLabel: 'Save Home',
                onTap: _busy ? null : _save,
                child: const Pill('Save Home and allow Always', C.orange),
              ),
            ],
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: S.x2),
        Text(_error!, style: F.cap.copyWith(color: p.on(C.red))),
      ],
      if (saved != null) ...[
        const SizedBox(height: S.x4),
        Pressable(
          semanticLabel: 'Turn off Home auto-pause',
          onTap: () async {
            final ok = await confirmRemove(
              c,
              title: 'Turn off Home auto-pause?',
              body:
                  'WHOOP stops watching Home and deletes it. An open day keeps its current state.',
              remove: 'Turn off',
            );
            if (!ok) return;
            await HomeRegion.clear();
            await _load();
          },
          child: Text(
            'Turn off and delete Home',
            style: F.cap.copyWith(color: p.on(C.red)),
          ),
        ),
      ],
    ]);
  }
}

/// Pushups on Today: sets against the goal and the next reminder, with Log
/// a set while a day is open and Start when it is not. Hidden until Pushups
/// has been used once.
class TodayPushupRow extends StatefulWidget {
  const TodayPushupRow({super.key, this.embedded = false});

  /// Drawn as one row of Today's plan card rather than its own card.
  final bool embedded;
  @override
  State<TodayPushupRow> createState() => _TodayPushupRowState();
}

class _TodayPushupRowState extends State<TodayPushupRow> {
  PushupStatus? _s;

  @override
  void initState() {
    super.initState();
    PushupDb.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    PushupDb.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await Pushups.status();
      if (mounted) setState(() => _s = s);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    final s = _s;
    if (s == null || (s.sessions.isEmpty && s.active == null)) {
      return const SizedBox.shrink();
    }
    final p = P.of(c);
    final a = s.active;
    final goal = a?.goal ?? (s.goal > 0 ? s.goal : null);
    final due = a == null ? null : pushupNextDue(a, DateTime.now());
    final sub = a == null
        ? 'Not started today'
        : a.state == PushupState.paused
        ? 'Paused'
        : due == null
        ? 'Running'
        : 'Next ${_hm(due)}';
    if (widget.embedded) {
      return PlanRow(
        icon: LucideIcons.alarmClock,
        color: C.orange,
        title: 'Pushups · ${s.today}${goal == null ? '' : ' of $goal'}',
        sub: sub,
        frac: goal == null ? null : s.today / goal,
        action: a == null ? 'Start' : 'Done',
        onAction: () async {
          await (a == null ? Pushups.start() : Pushups.done());
          await _load();
        },
        onTap: () => _push(c, const PushupsScreen()),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: Surface(
        onTap: () => _push(c, const PushupsScreen()),
        semanticLabel: 'Pushups, ${s.today} sets today. Opens Pushups.',
        child: Row(
          children: [
            Icon(LucideIcons.alarmClock, size: 18, color: p.on(C.orange)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pushups · ${s.today}${goal == null ? '' : ' of $goal'}',
                    style: F.body.copyWith(color: p.ink),
                  ),
                  Text(sub, style: F.over.copyWith(color: p.ink3)),
                ],
              ),
            ),
            Pressable(
              semanticLabel: a == null ? 'Start my day' : 'Log a set',
              onTap: () async {
                await (a == null ? Pushups.start() : Pushups.done());
                await _load();
              },
              child: Pill(a == null ? 'Start' : 'Done', C.orange),
            ),
          ],
        ),
      ),
    );
  }
}
