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

class CalmBreathing extends StatefulWidget {
  const CalmBreathing({super.key});

  @override
  State<CalmBreathing> createState() => _CalmBreathingState();
}

class _CalmBreathingState extends State<CalmBreathing>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _elapsed = Duration.zero;
  BreathPattern _pattern = kBreathPatterns.first;
  int _minutes = 5;
  BreathPhaseKind? _lastPhase;
  bool _running = false;
  bool _finished = false;

  /// Whether the band accepted the session. False means the pacer is running
  /// unscored and unrecorded — still worth doing, and said out loud.
  bool _banded = false;

  Duration? get _target => sessionEnd(_pattern, _rounds);
  int get _rounds => (_minutes * 60 / _pattern.cycleSeconds).round();

  @override
  void dispose() {
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
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
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

  Future<void> _stop() async {
    _ticker?.stop();
    final app = context.read<AppState>();
    await app.stopBreathingSession();
    if (!mounted) return;
    setState(() {
      _running = false;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
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
                  expand: false,
                  semanticLabel: 'Close breathing',
                  onTap: () async {
                    if (_running) await _stop();
                    if (c.mounted) Navigator.of(c).pop();
                  },
                  child: Icon(LucideIcons.x, size: 22, color: p.ink2),
                ),
              ),
              Expanded(
                child: _finished
                    ? _Result(onDone: () => Navigator.of(c).pop())
                    : _running
                    ? _Running(
                        pattern: _pattern,
                        elapsed: _elapsed,
                        target: _target,
                        banded: _banded,
                      )
                    : _Setup(
                        pattern: _pattern,
                        minutes: _minutes,
                        onPattern: (v) => setState(() => _pattern = v),
                        onMinutes: (v) => setState(() => _minutes = v),
                      ),
              ),
              BigButton(
                _running ? 'End session' : (_finished ? 'Done' : 'Begin'),
                icon: _running ? LucideIcons.square : LucideIcons.play,
                color: C.domMind,
                soft: _running,
                onTap: _running
                    ? _stop
                    : (_finished ? () => Navigator.of(c).pop() : _start),
              ),
              const SizedBox(height: S.x6),
            ],
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
  });

  final BreathPattern pattern;
  final int minutes;
  final ValueChanged<BreathPattern> onPattern;
  final ValueChanged<int> onMinutes;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return ListView(
      children: [
        const SizedBox(height: S.x4),
        Text('Take a breath.', style: F.t1.copyWith(color: p.ink)),
        const SizedBox(height: S.x2),
        Text(
          'Pick a pace. The ring leads, the strap buzzes at each change, and '
          'you can put the phone down.',
          style: F.cap.copyWith(color: p.ink2, height: 1.5),
        ),
        for (final b in kBreathPatterns)
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
      ],
    );
  }
}

// ── running ────────────────────────────────────────────────────────────────

class _Running extends StatelessWidget {
  const _Running({
    required this.pattern,
    required this.elapsed,
    required this.target,
    required this.banded,
  });

  final BreathPattern pattern;
  final Duration elapsed;
  final Duration? target;
  final bool banded;

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
        BreathCircle(t: t, label: kind.label),
        const SizedBox(height: S.x8),
        Text(_clock(elapsed), style: F.n34.copyWith(color: p.ink2)),
        if (target != null) ...[
          const SizedBox(height: S.x1),
          Text(
            'of ${_clock(target!)}',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
        if (!banded) ...[
          const SizedBox(height: S.x6),
          const StatusCard(
            'No coherence score for this session',
            'Coherence is measured from your heart beat timing, which comes '
                'from the band. It is not connected, so this session paces you '
                'but is not scored or saved.',
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
            painter: BreathRing(t, C.domMind),
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
    // The estimator returns {ok, score, confidence, tier, note}; `score` is
    // its value field, so it is renamed on the way into the envelope rather
    // than hand-mapping tiers at the call site.
    final m = raw == null || raw['ok'] != true
        ? null
        : Metric.parse({...raw, 'value': raw['score']});
    final absent = StatusCard.forMetric(
      'No coherence score for this session',
      m,
      why: app.breathingError ??
          'Coherence needs a clean run of beat timings across the whole '
              'session. Not enough of them landed to score it honestly.',
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
            conf: ConfX.of(m),
          ),
      ],
    );
  }
}
