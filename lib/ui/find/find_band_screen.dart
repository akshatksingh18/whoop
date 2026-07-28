// find_band_screen.dart — the hunt. Buzz the band and follow the signal.
//
// The band is small, dark and silent, and it comes off in bed, in a gym bag, or
// beside a charger. Every other device you own can be made to announce itself;
// this one could too, and the two pieces needed have been sitting there all
// along — a haptic motor we can fire on command, and an RSSI we never read.
//
// HONESTY, because this screen is one long temptation to fake precision:
// RSSI is not distance. Converting it to metres needs a calibrated TX power and
// a free-space assumption, and a band down the side of a mattress breaks the
// assumption completely — the number would be confident and wrong, which is the
// one thing this app does not do. So the screen shows a coarse zone, a
// warmer/colder trend and a relative bar, and says plainly what it is.
//
// Presentation only: the smoothing, the zone thresholds and the hysteresis all
// live in ProximityTracker, which is unit-tested without a radio.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ble/proximity_policy.dart';
import '../../state/app_state.dart';
import '../design/design.dart';

class FindBandScreen extends StatefulWidget {
  const FindBandScreen({super.key});

  @override
  State<FindBandScreen> createState() => _FindBandScreenState();
}

class _FindBandScreenState extends State<FindBandScreen> {
  /// ~1.4 Hz. Fast enough to feel live as you sweep a room, slow enough that
  /// each GATT read comfortably completes before the next is due.
  static const _pollInterval = Duration(milliseconds: 700);

  /// Auto-buzz cadence. Long enough to locate the sound between pulses.
  static const _buzzInterval = Duration(seconds: 3);

  final _tracker = ProximityTracker();
  Timer? _poll;
  Timer? _buzzer;
  ProximityReading _reading = const ProximityReading(
    zone: ProximityZone.unknown,
    trend: ProximityTrend.unknown,
    samples: 0,
  );
  bool _autoBuzz = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _buzzer?.cancel();
    super.dispose();
  }

  void _start() {
    _poll?.cancel();
    _buzzer?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _tick());
    if (_autoBuzz) {
      _buzzer = Timer.periodic(_buzzInterval, (_) => _buzz());
    }
    _tick();
    _buzz();
  }

  Future<void> _tick() async {
    // A read can outlive its timer tick on a marginal link; skipping is better
    // than queueing reads behind each other.
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final app = context.read<AppState>();
      final rssi = await app.readBandRssi();
      if (!mounted) return;
      if (rssi == null) {
        // Link gone: drop the stale EWMA so a reconnect starts clean rather
        // than blending the old room's signal into the new one.
        _tracker.reset();
        setState(() => _reading = _tracker.current);
        return;
      }
      setState(() => _reading = _tracker.add(rssi));
    } finally {
      _busy = false;
    }
  }

  Future<void> _buzz() async {
    if (!mounted) return;
    final app = context.read<AppState>();
    if (!app.isConnected) return;
    await app.buzzBand();
  }

  void _toggleAutoBuzz(bool v) {
    setState(() => _autoBuzz = v);
    _buzzer?.cancel();
    if (v) {
      _buzzer = Timer.periodic(_buzzInterval, (_) => _buzz());
      _buzz();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.select<AppState, bool>((a) => a.isConnected);
    return FindBandView(
      connected: connected,
      reading: _reading,
      autoBuzz: _autoBuzz,
      onBuzzNow: _buzz,
      onAutoBuzzChanged: _toggleAutoBuzz,
      onBack: () => Navigator.of(context).maybePop(),
    );
  }
}

/// The pure board — plain values in, no AppState, so it can be widget-tested
/// for every state including the ones that are hard to produce on real radio.
class FindBandView extends StatelessWidget {
  const FindBandView({
    super.key,
    required this.connected,
    required this.reading,
    this.autoBuzz = true,
    this.onBuzzNow,
    this.onAutoBuzzChanged,
    this.onBack,
  });

  final bool connected;
  final ProximityReading reading;
  final bool autoBuzz;
  final VoidCallback? onBuzzNow;
  final ValueChanged<bool>? onAutoBuzzChanged;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AppScaffold(
      title: 'Find my strap',
      subtitle: connected ? 'Buzzing and tracking the signal' : 'Not connected',
      onBack: onBack,
      actions: [
        InfoDot(
          title: 'How this works',
          body: 'Your strap buzzes while the phone measures how strong its '
              'Bluetooth signal is. Stronger usually means closer.\n\n'
              'This is signal strength, not distance — we deliberately don\'t '
              'show metres. Walls, bedding and your own body all weaken the '
              'signal, so a strap under a duvet two feet away can read weaker '
              'than one across an empty room. Walk slowly and follow '
              '"warmer".',
        ),
      ],
      children: connected
          ? _hunting(context, t)
          : [const _Disconnected()],
    );
  }

  List<Widget> _hunting(BuildContext context, ThemeData t) {
    final strength = reading.strength;
    return [
      Center(
        child: ArcGauge(
          value: strength ?? double.nan,
          size: 200,
          valueText: reading.zone.label,
          label: reading.trend.label.isEmpty ? null : reading.trend.label,
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reading.zone.hint, style: t.textTheme.bodyMedium),
            if (reading.smoothedRssi != null) ...[
              const SizedBox(height: 8),
              Text(
                'Signal ${reading.smoothedRssi!.toStringAsFixed(0)} dBm',
                style: t.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      SurfaceCard(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: autoBuzz,
              onChanged: onAutoBuzzChanged,
              title: const Text('Keep buzzing'),
              subtitle: const Text('A pulse every few seconds while you look'),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBuzzNow,
                icon: const Icon(Icons.vibration),
                label: const Text('Buzz now'),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class _Disconnected extends StatelessWidget {
  const _Disconnected();

  @override
  Widget build(BuildContext context) {
    // Said plainly rather than dressed up as a spinner: the hunt needs the
    // link for BOTH halves — buzzing it and measuring it — so a strap we
    // cannot reach is one this screen genuinely cannot help with. Better to
    // explain that than to show a hopeful empty gauge forever.
    return const StateCard(
      icon: OsIcon.bluetooth,
      title: 'Can\'t reach your strap',
      message: 'Finding it needs a live connection — that\'s how we buzz it '
          'and how we measure the signal.\n\nIf it\'s in range it should '
          'reconnect on its own in a moment. If nothing happens it\'s probably '
          'out of range, out of battery, or still connected to another phone.',
    );
  }
}
