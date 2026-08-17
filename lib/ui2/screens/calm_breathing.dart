// Paced breathing — the one screen in the app whose job is to slow you down.
//
// The phase engine is `lib/stress/breath_phases.dart`, which is pure and
// shared with the interval timer. This screen owns only the clock: a `Ticker`
// hands it elapsed time, `phaseAt` turns that into a phase, and `BreathRing`
// draws the phase. Nothing here loops on its own — the design system bans
// `.repeat()` precisely because thirteen ungated tickers is what the old UI
// shipped, and a loop nobody owns cannot be stopped by the reduced-motion
// gate.
//
// Coherence needs live RR from the band. Breathing does not. When the band is
// not connected the pacer still runs; it just says plainly that there will be
// no score.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../../stress/breath_phases.dart';
import '../ui2.dart';

/// Session lengths offered, in minutes. Converted to whole pattern cycles so
/// a session always ends on a completed breath rather than mid-exhale.
const _minuteOptions = <int>[2, 5, 10];

// ── RESP-06 · find your own pace ───────────────────────────────────────────
//
// The 5.5 breaths/min default is one number for everybody, and the pace an
// individual heart responds to most strongly genuinely sits somewhere between
// about 4.5 and 6.5. So this is a RANKING OVER A COARSE GRID, run on the same
// pacer and the same coherence estimator the ordinary session uses — the state
// machine is forked, not rebuilt: each block IS a session, started and banked
// through the same `startBreathingSession`/`stopBreathingSession` pair, which
// is also what gives each block its own coherence rather than one score smeared
// over the whole sweep.
//
// What it may never become: a decimal the grid cannot support, a clinical
// claim, or a number that moves on one sitting.

/// The paces the sweep tests, in breaths per minute.
///
/// THREE, not five. Five two-minute blocks is ten minutes of paced breathing;
/// people bail out of that, and a bailed sweep leaves a half-measured pace
/// stored as a fact about them. Six minutes is a sitting someone finishes.
const kPaceSweepRates = <double>[6.5, 5.5, 4.5];

/// Minutes per block. Two is the floor for a coherence estimate with enough
/// beats in it, and three of them is the whole session.
const kPaceSweepBlockMinutes = 2;

/// The profile key holding the winners of past sweeps, oldest first.
const kPaceWinsKey = 'breath_pace_wins';

/// A resonance pattern at [rate] breaths a minute — even in, even out.
///
/// 5.5 returns the SHIPPED resonance pattern rather than a lookalike: two
/// patterns at the same pace under two different keys would split her breathing
/// history in half for no reason anyone could see.
BreathPattern paceAt(double rate) {
  final shipped = kBreathPatterns.first;
  if ((rate - shipped.rate).abs() < 0.05) return shipped;
  final half = 30.0 / rate;
  return BreathPattern(
    key: 'resonance_${rate.toStringAsFixed(1).replaceAll('.', '_')}',
    label: 'Resonance',
    description:
        'Even in and out at about ${rate.toStringAsFixed(1)} breaths a '
        'minute. The one with a coherence score.',
    phases: [
      BreathPhase(BreathPhaseKind.inhale, half),
      BreathPhase(BreathPhaseKind.exhale, half),
    ],
    coherenceRated: true,
  );
}

/// The pace one sweep picked, or null when the sweep did not pick one.
///
/// EVERY block has to have scored. A sweep where one pace produced too few
/// clean beats is a comparison with a hole in it, and taking the best of the
/// two that did score is quietly a different experiment with a different
/// answer. A tie is not a winner either — at this resolution two equal scores
/// mean the grid cannot separate them, which is a real result and not a
/// reason to pick the first one.
double? sweepWinner(List<double> rates, List<int?> scores) {
  if (scores.length != rates.length || scores.any((s) => s == null)) {
    return null;
  }
  var best = 0;
  for (var i = 1; i < scores.length; i++) {
    if (scores[i]! > scores[best]!) best = i;
  }
  return scores.where((s) => s == scores[best]).length > 1 ? null : rates[best];
}

/// RESP-06 — the pace TWO SITTINGS AGREED ON, or null.
///
/// One assessment is noisy: each block is a couple of minutes of breathing on
/// one morning, in one mood, at one point in the day, and a winner that does
/// not come back is a coin toss stored as a fact about her heart. So the
/// default only moves when the two most recent completed sweeps picked the
/// same pace, and until then 5.5 stands.
double? agreedPace(Object? wins) {
  final w = <double>[
    for (final v in (wins as List? ?? const []))
      if (v is num) v.toDouble(),
  ];
  if (w.length < 2) return null;
  return w[w.length - 1] == w[w.length - 2] ? w.last : null;
}

/// The patterns the picker offers. The resonance entry is paced at [yours]
/// when two sittings have agreed on one, and is the shipped 5.5 otherwise —
/// one entry either way, never a personal pace sitting next to the default as
/// if they were two different exercises.
List<BreathPattern> patternsFor(double? yours) => [
  yours == null ? kBreathPatterns.first : paceAt(yours),
  ...kBreathPatterns.skip(1),
];

class CalmBreathing extends StatefulWidget {
  const CalmBreathing({super.key});

  @override
  State<CalmBreathing> createState() => _CalmBreathingState();
}

class _CalmBreathingState extends State<CalmBreathing>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  /// The reduced-motion clock. The rendered ring is already pinned by
  /// `animate` when the gate is closed, so a 60 Hz `setState` under it redraws
  /// a static picture sixty times a second — for the users who asked for less
  /// motion, and everyone's battery. One second is the resolution the clock and
  /// the phase cues actually need.
  Timer? _slowTick;
  final _watch = Stopwatch();

  Duration _elapsed = Duration.zero;
  BreathPattern _pattern = kBreathPatterns.first;
  int _minutes = 5;
  BreathPhaseKind? _lastPhase;
  bool _running = false;
  bool _finished = false;

  /// Whether the band accepted the session. False means the pacer is running
  /// unscored and unrecorded — still worth doing, and said out loud.
  bool _banded = false;

  /// RESP-06 — the running sweep, or null for an ordinary session. Holds the
  /// block index and one score per finished block (null where a block produced
  /// no clean estimate), so the ranking is only ever read off blocks that
  /// actually measured something.
  int? _block;
  final List<int?> _blockScores = [];
  bool _sweepAborted = false;
  bool get _sweeping => _block != null;

  Duration? get _target => sessionEnd(_pattern, _rounds);
  int get _rounds => (_minutes * 60 / _pattern.cycleSeconds).round();

  @override
  void initState() {
    super.initState();
    // The pace two sittings agreed on, read once. `read` rather than `watch`:
    // the pattern is the user's choice from here on, and a profile write mid
    // session must not silently repace her.
    final yours = agreedPace(context.read<AppState>().user?[kPaceWinsKey]);
    if (yours != null) _pattern = paceAt(yours);
  }

  @override
  void dispose() {
    _slowTick?.cancel();
    _ticker?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final app = context.read<AppState>();
    await app.startBreathingSession(pattern: _pattern, target: _target);
    if (!mounted) return;
    setState(() {
      _banded = app.breathingActive;
      _running = true;
      _finished = false;
      _elapsed = Duration.zero;
      _lastPhase = null;
    });
    _ticker?.dispose();
    _slowTick?.cancel();
    _watch
      ..reset()
      ..start();
    if (Motion.enabled(context)) {
      _ticker = createTicker(_onTick)..start();
    } else {
      _slowTick = Timer.periodic(Motion.tick, (_) => _onTick(_watch.elapsed));
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final target = _target;
    if (target != null && elapsed >= target) {
      _stop();
      return;
    }
    final at = phaseAt(_pattern, elapsed);
    if (at != null && at.phase.kind != _lastPhase) {
      _lastPhase = at.phase.kind;
      // Best-effort haptic cue so the session works with the screen off.
      context.read<AppState>().buzzBreathPhase(at.phase.kind);
    }
    setState(() => _elapsed = elapsed);
  }

  /// RESP-06 — start the three-block sweep. Refuses without a band, because
  /// the entire output is a comparison of beat timing and six minutes of
  /// breathing that cannot produce one is six minutes taken for nothing.
  Future<void> _startSweep() async {
    setState(() {
      _block = 0;
      _blockScores.clear();
      _minutes = kPaceSweepBlockMinutes;
      _pattern = paceAt(kPaceSweepRates.first);
    });
    await _start();
  }

  /// [abort] is the user stopping, as opposed to a block reaching its target.
  /// The distinction is the whole sweep: a block that ENDED feeds the ranking
  /// and hands over to the next pace, and a sweep the user stopped is a
  /// half-measured comparison that must never be banked as one.
  Future<void> _stop({bool abort = false}) async {
    _ticker?.stop();
    _slowTick?.cancel();
    _watch.stop();
    final app = context.read<AppState>();
    // Read BEFORE stopping: the next block's `startBreathingSession` clears
    // `breathingResult`, and the block that just ended owns this one.
    final res = app.breathingResult;
    await app.stopBreathingSession();
    if (!mounted) return;

    final block = _block;
    if (block != null && !abort) {
      _blockScores.add(
        res != null && res['ok'] == true
            ? (res['score'] as num?)?.round()
            : null,
      );
      if (block + 1 < kPaceSweepRates.length) {
        setState(() {
          _block = block + 1;
          _pattern = paceAt(kPaceSweepRates[block + 1]);
        });
        await _start();
        return;
      }
      await _bankSweep();
      if (!mounted) return;
    }
    setState(() {
      _running = false;
      _finished = true;
      if (block != null && abort) _sweepAborted = true;
    });
  }

  /// Append this sweep's winner to the profile. A sweep that measured nothing
  /// writes NOTHING — an unmeasured sitting must not be able to agree with a
  /// measured one and move the default between them.
  Future<void> _bankSweep() async {
    final winner = sweepWinner(kPaceSweepRates, _blockScores);
    if (winner == null) return;
    final app = context.read<AppState>();
    final prev = <double>[
      for (final v in (app.user?[kPaceWinsKey] as List? ?? const []))
        if (v is num) v.toDouble(),
    ];
    final wins = [...prev, winner];
    await app.updateProfile({
      // Only the recent run matters — the gate reads the last two, and an
      // unbounded list in a profile that is written on every edit is a slow
      // leak nobody would ever look for.
      kPaceWinsKey: wins.length > 4 ? wins.sublist(wins.length - 4) : wins,
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // Swiping back is the same exit as the X, and it used to be a different
    // one: the ticker stopped, nothing banked the session, `breathingActive`
    // stayed true, and the band's live streams stayed on until the app died.
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_running) return;
        await _stop(abort: true);
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Pressable(
                    semanticLabel: 'Close breathing',
                    onTap: () async {
                      if (_running) await _stop(abort: true);
                      if (c.mounted) Navigator.of(c).pop();
                    },
                    child: Icon(LucideIcons.x, size: 22, color: p.ink2),
                  ),
                ),
                Expanded(
                  child: _finished
                      ? (_sweeping
                            ? _SweepResult(
                                scores: _blockScores,
                                aborted: _sweepAborted,
                              )
                            : _Result(onDone: () => Navigator.of(c).pop()))
                      : _running
                      ? _Running(
                          pattern: _pattern,
                          elapsed: _elapsed,
                          target: _target,
                          banded: _banded,
                          block: _block,
                        )
                      : _Setup(
                          pattern: _pattern,
                          minutes: _minutes,
                          onPattern: (v) => setState(() => _pattern = v),
                          onMinutes: (v) => setState(() => _minutes = v),
                          onSweep: _startSweep,
                        ),
                ),
                BigButton(
                  _running
                      ? (_sweeping ? 'Stop' : 'End session')
                      : (_finished ? 'Done' : 'Begin'),
                  icon: _running ? LucideIcons.square : LucideIcons.play,
                  color: C.domMind,
                  soft: _running,
                  onTap: _running
                      ? () => _stop(abort: true)
                      : (_finished ? () => Navigator.of(c).pop() : _start),
                ),
                const SizedBox(height: S.x6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── setup ──────────────────────────────────────────────────────────────────

class _Setup extends StatelessWidget {
  const _Setup({
    required this.pattern,
    required this.minutes,
    required this.onPattern,
    required this.onMinutes,
    required this.onSweep,
  });

  final BreathPattern pattern;
  final int minutes;
  final ValueChanged<BreathPattern> onPattern;
  final ValueChanged<int> onMinutes;
  final VoidCallback onSweep;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final app = c.watch<AppState>();
    final yours = agreedPace(app.user?[kPaceWinsKey]);
    return ListView(
      children: [
        const SizedBox(height: S.x4),
        Text('Take a breath.', style: F.t1.copyWith(color: p.ink)),
        const SizedBox(height: S.x2),
        // The buzz is band-dependent and this screen does not yet know whether
        // the band will accept the session, so it is not promised here. The
        // `!banded` card during the run is where that gets said.
        Text(
          'The ring leads. Put the phone down.',
          style: F.cap.copyWith(color: p.ink2, height: 1.5),
        ),
        for (final b in patternsFor(yours))
          Padding(
            padding: const EdgeInsets.only(top: S.x3),
            child: Surface(
              onTap: () => onPattern(b),
              color: b.key == pattern.key ? P.of(c).wash(C.domMind) : null,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                b.label,
                                style: F.body.copyWith(
                                  color: p.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (b.coherenceRated) ...[
                              const SizedBox(width: S.x2),
                              const Pill('Scored', C.domMind),
                            ],
                          ],
                        ),
                        const SizedBox(height: S.x1),
                        Text(
                          b.description,
                          style: F.cap.copyWith(color: p.ink3, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Text(
                    '${b.rate.toStringAsFixed(1)}/min',
                    style: F.n17.copyWith(color: p.on(C.domMind)),
                  ),
                ],
              ),
            ),
          ),
        Section(
          'How long',
          Row(
            children: [
              for (final m in _minuteOptions) ...[
                Expanded(
                  child: Pressable(
                    onTap: () => onMinutes(m),
                    semanticLabel: '$m minutes',
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: S.x3),
                      decoration: BoxDecoration(
                        color: m == minutes ? p.fill(C.domMind) : p.card,
                        borderRadius: R.rMd,
                      ),
                      child: Center(
                        child: Text(
                          '$m min',
                          style: F.body.copyWith(
                            color: m == minutes ? p.inkOnFill : p.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (m != _minuteOptions.last) const SizedBox(width: S.x3),
              ],
            ],
          ),
        ),
        // RESP-06 — the door, and only a door. The sweep itself is six minutes
        // and a comparison, which is not what someone who opened this screen
        // to breathe came for; it lives one tap away rather than as a fourth
        // thing to read before beginning.
        Section('Your own pace', _sweepDoor(c, p, app.isConnected, yours)),
      ],
    );
  }

  Widget _sweepDoor(
    BuildContext c,
    P p,
    bool connected,
    double? yours,
  ) => Surface(
    // Not offered without a band: the entire output is a comparison of
    // beat timing, so an unbanded sweep is six minutes taken for nothing.
    onTap: connected ? onSweep : null,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Find the pace your heart follows',
                style: F.body.copyWith(
                  color: connected ? p.ink : p.ink3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: S.x1),
              Text(
                !connected
                    ? 'Needs the band on — the comparison is made from '
                          'beat timing.'
                    : yours == null
                    ? 'Six minutes: '
                          '${kPaceSweepRates.map((r) => r.toStringAsFixed(1)).join(', ')} '
                          'breaths a minute, two minutes each. It takes '
                          'two sittings that agree before anything changes.'
                    : 'Two sittings agreed on '
                          '${yours.toStringAsFixed(1)} breaths a minute, '
                          'and Resonance is paced there. Run it again to '
                          'check.',
                style: F.cap.copyWith(color: p.ink3, height: 1.4),
              ),
            ],
          ),
        ),
        if (connected) ...[
          const SizedBox(width: S.x3),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ],
      ],
    ),
  );
}

// ── running ────────────────────────────────────────────────────────────────

class _Running extends StatelessWidget {
  const _Running({
    required this.pattern,
    required this.elapsed,
    required this.target,
    required this.banded,
    this.block,
  });

  final BreathPattern pattern;
  final Duration elapsed;
  final Duration? target;
  final bool banded;

  /// RESP-06 — which block of the sweep is running, or null for an ordinary
  /// session. Said out loud: the ring changing speed with no explanation is
  /// the pacer looking broken.
  final int? block;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final at = phaseAt(pattern, elapsed);
    final kind = at?.phase.kind ?? BreathPhaseKind.inhale;
    final progress = at?.progress ?? 0;
    // Reduced motion holds the ring still at the phase's destination rather
    // than sweeping to it — the words still change, so the pacing survives.
    final t = animate(c, breathScale(kind, progress));
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (block != null) ...[
          Text(
            'PACE ${block! + 1} OF ${kPaceSweepRates.length} · '
            '${pattern.rate.toStringAsFixed(1)} BREATHS A MINUTE',
            textAlign: TextAlign.center,
            style: F.over.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x5),
        ],
        BreathCircle(t: t, label: kind.label),
        const SizedBox(height: S.x8),
        Text(_clock(elapsed), style: F.n34.copyWith(color: p.ink2)),
        if (target != null) ...[
          const SizedBox(height: S.x1),
          Text('of ${_clock(target!)}', style: F.cap.copyWith(color: p.ink3)),
        ],
        if (!banded) ...[
          const SizedBox(height: S.x6),
          const StatusCard(
            'No coherence score for this session',
            'Scoring needs beat timing from the band. Not connected, so this '
                'one paces you but is not saved.',
            icon: LucideIcons.bluetoothOff,
          ),
        ],
      ],
    );
  }
}

/// The ring plus its instruction. Public so the goldens can capture it —
/// the ring's phase is a plain number, which is the whole point of
/// `BreathRing.t`.
class BreathCircle extends StatelessWidget {
  const BreathCircle({super.key, required this.t, required this.label});

  final double t;
  final String label;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(240, 240),
            painter: BreathRing(t, p.on(C.domMind)),
          ),
          Text(label, style: F.head.copyWith(color: p.ink)),
        ],
      ),
    );
  }
}

/// Ring size for a phase at [progress]. Holds are still on purpose: a ring
/// that keeps moving during a hold is telling you to keep breathing.
double breathScale(BreathPhaseKind kind, double progress) => switch (kind) {
  BreathPhaseKind.inhale || BreathPhaseKind.work => progress,
  BreathPhaseKind.exhale || BreathPhaseKind.rest => 1 - progress,
  BreathPhaseKind.holdIn => 1,
  BreathPhaseKind.holdOut => 0,
};

String _clock(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ── result ─────────────────────────────────────────────────────────────────

class _Result extends StatelessWidget {
  const _Result({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final app = c.watch<AppState>();
    final raw = app.breathingResult;
    // Only the patterns the setup list marks "Scored" are scored. The
    // estimator runs for any pattern, so Box and 4-7-8 used to show a
    // coherence number here that `stopBreathingSession` then stored as null —
    // a number the user was shown and that exists nowhere afterwards.
    final rated = app.breathingPattern.coherenceRated;
    // The estimator returns {ok, score, confidence, tier, note}; `score` is
    // its value field, so it is renamed on the way into the envelope rather
    // than hand-mapping tiers at the call site.
    final m = !rated || raw == null || raw['ok'] != true
        ? null
        : Metric.parse({...raw, 'value': raw['score']});
    final absent = StatusCard.forMetric(
      'No coherence score for this session',
      m,
      why: !rated
          ? '${app.breathingPattern.label} is not scored. Resonance breathing '
                'is the one paced at the rate the score is defined against.'
          : app.breathingError ??
                'Too few clean beat timings across the session to score it.',
    );
    return ListView(
      children: [
        const SizedBox(height: S.x8),
        Text('That is done.', style: F.t1.copyWith(color: p.ink)),
        const SizedBox(height: S.x5),
        if (absent != null)
          absent
        else
          SignalCard(
            LucideIcons.wind,
            C.domMind,
            'Cardiac coherence',
            m!.value!.toStringAsFixed(0),
            sub: 'HOW STRONGLY YOUR HEART RATE FOLLOWED THE PACE',
          ),
      ],
    );
  }
}

// ── RESP-06 result ─────────────────────────────────────────────────────────

/// What the sweep found, which is usually "nothing you can act on yet".
///
/// A RANKING OVER THREE PACES, at the resolution tested, from one sitting —
/// never a decimal the grid cannot support, never a rate presented as a
/// property of her nervous system, and never a treatment for anything. The
/// three blocks run back to back, so each pace is measured while she is still
/// settling out of the one before; that is a real limit of a six-minute
/// protocol and it is printed rather than designed around.
class _SweepResult extends StatelessWidget {
  const _SweepResult({required this.scores, required this.aborted});

  /// One per finished block, oldest first. Null where a block produced too few
  /// clean beats to score. Shorter than [kPaceSweepRates] when [aborted].
  final List<int?> scores;
  final bool aborted;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final app = c.watch<AppState>();
    final winner = aborted ? null : sweepWinner(kPaceSweepRates, scores);
    final agreed = agreedPace(app.user?[kPaceWinsKey]);
    return ListView(
      children: [
        const SizedBox(height: S.x8),
        Text(
          aborted ? 'Stopped there.' : 'That is done.',
          style: F.t1.copyWith(color: p.ink),
        ),
        const SizedBox(height: S.x5),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HOW STRONGLY YOUR HEART RATE FOLLOWED EACH PACE',
                style: F.over.copyWith(color: p.ink3),
              ),
              const SizedBox(height: S.x3),
              for (var i = 0; i < kPaceSweepRates.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.x2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${kPaceSweepRates[i].toStringAsFixed(1)} breaths a '
                          'minute',
                          style: F.body.copyWith(
                            color: winner == kPaceSweepRates[i]
                                ? p.ink
                                : p.ink2,
                          ),
                        ),
                      ),
                      const SizedBox(width: S.x3),
                      // Never a bare dash: a block that did not run and a
                      // block that ran and could not be scored are different
                      // things, and both of them are sentences.
                      Text(
                        i >= scores.length
                            ? 'not reached'
                            : scores[i] == null
                            ? 'too few clean beats'
                            : '${scores[i]}',
                        style:
                            (i < scores.length && scores[i] != null
                                    ? F.n17
                                    : F.cap)
                                .copyWith(color: p.ink2),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        Text(
          _verdict(winner, agreed),
          style: F.body.copyWith(color: p.ink, height: 1.4),
        ),
        const SizedBox(height: S.x3),
        Text(
          'A ranking over three paces, at the resolution tested, from one '
          'sitting. The blocks run back to back, so each pace is measured '
          'while you are still settling out of the one before. It says which '
          'pace your heart rate followed most strongly and nothing else.',
          style: F.over.copyWith(color: p.ink3, height: 1.5),
        ),
      ],
    );
  }

  String _verdict(double? winner, double? agreed) {
    if (aborted) {
      return 'You stopped part way, so there was nothing to compare. Nothing '
          'has changed.';
    }
    if (winner == null) {
      return scores.any((s) => s == null)
          ? 'At least one pace could not be scored, so there is nothing to '
                'rank. Nothing has changed.'
          : 'Two of the paces scored the same, so this sitting cannot '
                'separate them. Nothing has changed.';
    }
    final w = '${winner.toStringAsFixed(1)} breaths a minute';
    return agreed == winner
        ? 'Of the paces tested, $w gave your strongest response — and that is '
              'now two sittings in a row. Resonance is paced there.'
        : 'Of the paces tested, $w gave your strongest response. Nothing is '
              'set yet: the pace only changes when two sittings pick the same '
              'one.';
  }
}
