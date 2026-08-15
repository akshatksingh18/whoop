// Set the session up, then start it.
//
// One screen, four decisions, and only the ones this activity can honour: a
// distance goal is not offered to a lift, and the GPS row is not offered to an
// indoor bike. The privacy toggle is offered to everything and defaults on for
// the entries that carry `private` — same posture Apple Health takes, and the
// copy says exactly what it does.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../grammar.dart';
import '../theme.dart';
import 'catalogue.dart';
import 'live.dart';

enum Goal { open, time, distance, calories }

class ActivitySetup extends StatefulWidget {
  final Activity a;
  final double? weightKg;

  /// The app behind the screen — the feed, the session lifecycle, the strap's
  /// real connection state and the user's own lifting history.
  final ActivityHost host;

  const ActivitySetup(
    this.a, {
    super.key,
    this.weightKg,
    this.host = ActivityHost.none,
  });

  @override
  State<ActivitySetup> createState() => _ActivitySetupState();
}

class _ActivitySetupState extends State<ActivitySetup> {
  Goal goal = Goal.open;
  late bool private = widget.a.private;
  int targetMin = 45;

  bool _starting = false;
  bool _refused = false;

  /// Open the session in the app FIRST, then the screen. The screen used to
  /// be pushed on its own, so a "live" workout ran its own clock while the
  /// app recorded nothing and `sessions` gained no row.
  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final start = widget.host.onStart;
    final ok = start == null || await start(widget.a);
    if (!mounted) return;
    setState(() {
      _starting = false;
      _refused = !ok;
    });
    if (!ok) return;
    // The draft opens with the session, not with the screen: everything the
    // user types from here belongs to the session, and has to survive the
    // screen being minimised or the process being killed.
    if (start != null) {
      LiveDraft.begin(widget.a, private: private, weightKg: widget.weightKg);
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => liveFor(widget.a,
          private: private, weightKg: widget.weightKg, host: widget.host),
    ));
  }

  /// Back into the session that is already running. The refusal used to be a
  /// dead end: "finish that one first", with no way to reach the one screen
  /// that can finish it.
  void _resume() {
    final d = LiveDraft.current;
    final a = d == null ? null : activityByName(d.activityKey);
    if (a == null) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => liveFor(a,
          private: d!.private, weightKg: d.weightKg, host: widget.host),
    ));
  }

  /// A distance goal only makes sense where something measures distance.
  List<Goal> get goals => [
        Goal.open,
        Goal.time,
        if (widget.a.gps) Goal.distance,
        if (widget.weightKg != null) Goal.calories,
      ];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final a = widget.a;
    final est = a.kcal(widget.weightKg, targetMin);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(a.name),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                Center(
                  child: Column(children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                          color: p.wash(a.color), shape: BoxShape.circle),
                      child: Icon(a.icon, size: 38, color: p.on(a.color)),
                    ),
                    const SizedBox(height: S.x4),
                    Text(a.name, style: F.t2.copyWith(color: p.ink)),
                    const SizedBox(height: S.x1),
                    Text(_trackLabel(a.track),
                        textAlign: TextAlign.center,
                        style: F.cap.copyWith(color: p.ink3)),
                  ]),
                ),
                const SizedBox(height: S.x8),
                Text('GOAL', style: F.over.copyWith(color: p.ink3)),
                const SizedBox(height: S.x3),
                SubTabs(
                    [for (final g in goals) _goalLabel(g)],
                    goals.indexOf(goal),
                    (i) => setState(() => goal = goals[i]),
                    color: a.color),
                const SizedBox(height: S.x5),
                if (goal == Goal.time) ...[
                  Surface(
                    child: Row(children: [
                      Text('$targetMin minutes',
                          style: F.n34.copyWith(color: p.ink)),
                      const Spacer(),
                      Pressable(
                        semanticLabel: 'Less time',
                        onTap: () => setState(
                            () => targetMin = (targetMin - 5).clamp(5, 300)),
                        child: Icon(LucideIcons.minus,
                            size: 20, color: p.ink2),
                      ),
                      const SizedBox(width: S.x4),
                      Pressable(
                        semanticLabel: 'More time',
                        onTap: () => setState(
                            () => targetMin = (targetMin + 5).clamp(5, 300)),
                        child:
                            Icon(LucideIcons.plus, size: 20, color: p.ink2),
                      ),
                    ]),
                  ),
                  const SizedBox(height: S.x4),
                ],
                Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Column(children: [
                    if (a.gps) ...[
                      // No tick. Nothing here has asked for location yet, and
                      // an unconditional green check claimed a fix that a
                      // permission dialog had not even been shown for.
                      _row(p, LucideIcons.mapPin, 'Route',
                          'Recorded if location is available, and kept on '
                              'this device',
                          null),
                      Divider(color: p.line, height: 1),
                    ],
                    _row(
                        p,
                        LucideIcons.heartPulse,
                        'Heart rate',
                        widget.host.bandConnected
                            ? 'Strap connected'
                            : 'No strap connected — the session still runs, '
                                'without heart rate',
                        widget.host.bandConnected),
                    Divider(color: p.line, height: 1),
                    _toggle(
                        p,
                        LucideIcons.lock,
                        'Private session',
                        'Hidden from summaries and exports',
                        private,
                        () => setState(() => private = !private)),
                  ]),
                ),
                const SizedBox(height: S.x4),
                Surface(
                  elevation: 0,
                  color: p.card2,
                  child: Row(children: [
                    const ConfDots(Conf.estimated, size: 6),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Text(
                          est == null
                              ? 'Calories cannot be estimated without your '
                                  'body weight — ${a.met.toStringAsFixed(1)} '
                                  'MET on its own is not a kilocalorie.'
                              // No error bar: nothing computes one, and the
                              // "±15%" this used to quote was a number with
                              // no estimator behind it.
                              : 'About $est kcal for $targetMin min at your '
                                  'weight. Estimated from '
                                  '${a.met.toStringAsFixed(1)} MET, refined '
                                  'by heart rate once you start.',
                          style: F.cap.copyWith(color: p.ink3, height: 1.5)),
                    ),
                  ]),
                ),
                if (_refused) ...[
                  const SizedBox(height: S.x4),
                  StatusCard(
                    'A session is already running',
                    'Only one can be live at a time — the strap, the zone '
                        'tally and the route recorder all belong to it.',
                    fix: LiveDraft.current == null
                        ? ''
                        : 'Open the running session',
                    onFix: LiveDraft.current == null ? null : _resume,
                    icon: LucideIcons.circleAlert,
                  ),
                ],
                const SizedBox(height: S.x8),
                BigButton('Start',
                    icon: LucideIcons.play,
                    color: a.color,
                    onTap: _starting ? null : _start),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  String _goalLabel(Goal g) => switch (g) {
        Goal.open => 'Open',
        Goal.time => 'Time',
        Goal.distance => 'Distance',
        Goal.calories => 'Calories',
      };

  /// What this session will actually produce. Distance and pace are promised
  /// only where a route can be recorded — a treadmill was being sold "distance
  /// and pace" that nothing in this app can measure indoors.
  String _trackLabel(Track t) => switch (t) {
        Track.sets => 'Sets, reps and load — entered by you',
        Track.distance when widget.a.gps => 'Distance, pace and heart rate',
        Track.distance || Track.duration => 'Time and heart rate',
        Track.interval => 'Rounds and heart rate',
        Track.stillness => 'Time, breathing and heart rate',
      };

  /// [on] null means "not known yet" — no glyph at all, rather than a tick
  /// or a cross, both of which are claims.
  Widget _row(P p, IconData i, String n, String s, bool? on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Icon(i, size: 17, color: p.ink2),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n, style: F.body.copyWith(color: p.ink)),
                  Text(s, style: F.over.copyWith(color: p.ink3)),
                ]),
          ),
          if (on != null)
            Icon(on ? LucideIcons.circleCheck : LucideIcons.circleSlash,
                size: 20, color: on ? p.on(C.green) : p.line),
        ]),
      );

  Widget _toggle(P p, IconData i, String n, String s, bool on,
          VoidCallback onTap) =>
      Pressable(
        semanticLabel: '$n, ${on ? 'on' : 'off'}',
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Row(children: [
            Icon(i, size: 17, color: p.ink2),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n, style: F.body.copyWith(color: p.ink)),
                    Text(s, style: F.over.copyWith(color: p.ink3)),
                  ]),
            ),
            AnimatedContainer(
              duration: motion(context, Motion.base),
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color: on ? p.fill(C.green) : p.track,
                  borderRadius: R.rPill),
              child: AnimatedAlign(
                duration: motion(context, Motion.base),
                alignment:
                    on ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                      color: p.inkOnFill, shape: BoxShape.circle),
                ),
              ),
            ),
          ]),
        ),
      );
}
