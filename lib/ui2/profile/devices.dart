// Sources, not "devices".
//
// This is where the band-agnostic thesis has to be legible, because this is
// where someone goes to ask "which of my things is this number coming from?".
//
// The answer is a quality ladder, and the ordering rule is the inverse of the
// platform health stores: Apple Health and Health Connect rank by whatever
// wrote last (with a manual priority list bolted on top), so a phone's step
// estimate can quietly outrank a chest strap. Here the better sensor wins,
// recency only breaks a tie within a tier, and a user preference is the last
// word rather than the first.
//
// The ladder is shown in full even when a tier is empty — an unfilled Tier 1
// row is the honest statement that beat-to-beat data is available to this app
// and simply not present on this wrist yet.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../onboarding/pairing.dart';
import '../ui2.dart';
import 'profile.dart';
import 'settings.dart' show backToRoot;

/// Measurement quality, which is the ONLY thing that decides precedence.
enum SourceTier {
  /// An electrical beat detector: R-peaks, so genuine beat-to-beat intervals.
  beatToBeat(
    1,
    'Beat-to-beat intervals',
    'Electrical R-peak detection. The only source whose HRV is HRV rather '
        'than a pulse-timing proxy.',
    C.green,
  ),

  /// Optical pulse at the wrist. Everything this app ships today.
  wristOptical(
    2,
    'Wrist optical pulse',
    'Continuous 24/7 pulse, sleep and temperature. Beat timing is inferred '
        'from a pulse wave, so HRV here is PRV.',
    C.blue,
  ),

  /// The phone in a pocket.
  phone(
    3,
    'Steps only',
    'The phone’s own motion coprocessor. Steps and nothing else — it is not '
        'on your body often enough to measure anything continuous.',
    C.orange,
  );

  const SourceTier(this.rank, this.label, this.detail, this.accent);

  final int rank;
  final String label;
  final String detail;
  final Color accent;
}

/// One thing that can produce measurements.
class HealthSource {
  final String name, kind;
  final SourceTier tier;
  final IconData icon;
  final bool connected;
  final double? batteryPct;
  final bool charging;
  final DateTime? lastData;

  /// True for the paired band — the only source with device controls.
  final bool isBand;

  const HealthSource({
    required this.name,
    required this.kind,
    required this.tier,
    required this.icon,
    this.connected = false,
    this.batteryPct,
    this.charging = false,
    this.lastData,
    this.isBand = false,
  });
}

/// The sources that actually exist right now. Nothing is listed that cannot
/// produce a number today.
List<HealthSource> liveSources(AppState app) => [
      if (app.isPaired)
        HealthSource(
          name: app.strapName ?? 'WHOOP band',
          kind: app.device.generation == 'gen5'
              ? 'WHOOP 5 · wrist optical'
              : 'WHOOP 4 · wrist optical',
          tier: SourceTier.wristOptical,
          icon: LucideIcons.watch,
          connected: app.isConnected,
          batteryPct: app.device.batteryPct,
          charging: app.device.charging ?? false,
          lastData: app.lastRecordAt,
          isBand: true,
        ),
      if (app.phoneStepsEnabled)
        const HealthSource(
          name: 'This phone',
          kind: 'Motion coprocessor',
          tier: SourceTier.phone,
          icon: LucideIcons.smartphone,
          connected: true,
        ),
    ];

/// Quality first, then recency, then the user's own order. The inverse of
/// last-writer-wins.
List<HealthSource> rankSources(List<HealthSource> sources,
    {List<String> preferred = const []}) {
  final out = [...sources];
  out.sort((a, b) {
    final byTier = a.tier.rank.compareTo(b.tier.rank);
    if (byTier != 0) return byTier;
    final at = a.lastData, bt = b.lastData;
    if (at != null && bt != null && at != bt) return bt.compareTo(at);
    if (at != null) return -1;
    if (bt != null) return 1;
    final ai = preferred.indexOf(a.name), bi = preferred.indexOf(b.name);
    if (ai != bi) {
      return (ai < 0 ? preferred.length : ai)
          .compareTo(bi < 0 ? preferred.length : bi);
    }
    return a.name.compareTo(b.name);
  });
  return out;
}

// ══════════════════ MY DEVICES ══════════════════

class MyDevices extends StatelessWidget {
  const MyDevices({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    return MyDevicesView(
      sources: rankSources(liveSources(app)),
      // This used to clear a preference and nothing else — the gate that
      // renders the pairing step is MaterialApp.home, underneath this pushed
      // screen, so the button appeared completely inert. And the gate is no
      // longer an option regardless: an onboarded user is never routed back
      // into first-run pairing (that was the bug where forgetting a band threw
      // months of data behind an onboarding screen), which makes this the only
      // way back to pairing. So push it.
      onPair: () => goto(c, const RePair()),
    );
  }
}

/// Pairing, pushed rather than gated.
///
/// The onboarding gate is what used to take the pairing screen away once a
/// band answered. A pushed copy has no gate under it, so it closes itself —
/// otherwise it sits there on "Paired · Continue", whose button re-runs the
/// scan.
class RePair extends StatelessWidget {
  const RePair({super.key});

  @override
  Widget build(BuildContext c) {
    if (c.watch<AppState>().isPaired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (c.mounted) Navigator.of(c).maybePop();
      });
    }
    return PairingScreen(onSkip: () => Navigator.of(c).maybePop());
  }
}

class MyDevicesView extends StatelessWidget {
  final List<HealthSource> sources;
  final VoidCallback? onPair;

  const MyDevicesView({super.key, this.sources = const [], this.onPair});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('My sources'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                for (final s in sources) ...[
                  SourceRow(s, onTap: () => goto(c, DeviceDetail(s))),
                  const SizedBox(height: S.x3),
                ],
                if (sources.isEmpty)
                  StatusCard(
                    'Nothing is measuring yet',
                    'No band is paired and phone steps are off, so every '
                        'metric in the app will abstain rather than estimate.',
                    fix: 'Pair a band',
                    icon: LucideIcons.watch,
                    onFix: onPair,
                  ),
                const SizedBox(height: S.x5),
                Text('THE QUALITY LADDER',
                    style: F.over.copyWith(color: p.ink3)),
                const SizedBox(height: S.x3),
                for (final t in SourceTier.values) ...[
                  TierRow(t,
                      filled: sources.any((s) => s.tier == t)),
                  const SizedBox(height: S.x3),
                ],
                const SizedBox(height: S.x3),
                const StatusCard(
                  'Sources are ranked by measurement quality',
                  'When two sources report the same thing, the better sensor '
                      'wins — not the one that wrote last. Recency only '
                      'breaks a tie inside a tier, and your own preference '
                      'is the last word rather than the first.',
                  icon: LucideIcons.arrowUpDown,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// One connected source.
class SourceRow extends StatelessWidget {
  final HealthSource s;
  final VoidCallback? onTap;
  const SourceRow(this.s, {super.key, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final battery = s.batteryPct;
    return Surface(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
          child: Icon(s.icon, size: 24, color: p.ink2),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name,
                style: F.body
                    .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            Text(s.kind, style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: 5),
            // Wrap, not Row: at 2x text "Not connected · 78%" is wider than
            // the card and a Flex would simply clip the battery away.
            Wrap(spacing: S.x3, runSpacing: S.x1, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: s.connected ? p.on(C.green) : p.ink3,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(s.connected ? 'Connected' : 'Not connected',
                    style: F.over.copyWith(
                        color: s.connected ? p.on(C.green) : p.ink3)),
              ]),
              if (battery != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      s.charging
                          ? LucideIcons.batteryCharging
                          : LucideIcons.battery,
                      size: 13,
                      color: p.ink3),
                  const SizedBox(width: 3),
                  Text('${battery.round()}%',
                      style: F.over.copyWith(color: p.ink3)),
                ]),
            ]),
          ]),
        ),
        const SizedBox(width: S.x2),
        Pill('Tier ${s.tier.rank}', s.tier.accent),
      ]),
    );
  }
}

/// One rung of the ladder, filled or not. An empty rung is information.
class TierRow extends StatelessWidget {
  final SourceTier tier;
  final bool filled;
  const TierRow(this.tier, {super.key, this.filled = false});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      elevation: 0,
      color: filled ? p.wash(tier.accent) : p.card2,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(filled ? LucideIcons.badgeCheck : LucideIcons.circleDashed,
            size: 20, color: filled ? p.on(tier.accent) : p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tier ${tier.rank} · ${tier.label}',
                style: F.body.copyWith(
                    color: filled ? p.ink : p.ink2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: S.x1),
            Text(tier.detail, style: F.cap.copyWith(color: p.ink3, height: 1.5)),
            if (!filled) ...[
              const SizedBox(height: S.x2),
              Text('Nothing at this tier yet.',
                  style: F.over.copyWith(color: p.ink3)),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════ DEVICE DETAIL ══════════════════

class DeviceDetail extends StatelessWidget {
  final HealthSource s;
  const DeviceDetail(this.s, {super.key});

  @override
  Widget build(BuildContext c) {
    final app = s.isBand ? c.read<AppState>() : null;
    return DeviceDetailView(
      s,
      onFind: app?.buzzBand,
      onForget: app == null ? null : () => _confirmForget(c, app, s.name),
    );
  }
}

/// Forgetting a band is destructive — it ends the only connection to the one
/// sensor in the app that measures anything continuously — and it used to
/// happen on a single tap with no confirmation, leaving this screen still
/// showing the band's battery afterwards. Mirrors the reset confirmation in
/// settings.dart, including the pop: `unpair()` changes the gate underneath
/// this pushed screen, so without it the user is left reading a device page
/// for a device that is gone.
Future<void> _confirmForget(BuildContext c, AppState app, String name) async {
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text('Forget $name?'),
      content: const Text(
        'The band stops syncing and has to be paired again to measure '
        'anything. Everything already banked on this phone is kept — this '
        'removes the source, not the data.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Keep it paired')),
        TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Forget it')),
      ],
    ),
  );
  if (ok != true) return;
  await app.unpair();
  if (c.mounted) backToRoot(c);
}

class DeviceDetailView extends StatelessWidget {
  final HealthSource s;
  final VoidCallback? onFind, onForget;

  const DeviceDetailView(this.s, {super.key, this.onFind, this.onForget});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final battery = s.batteryPct;
    final last = s.lastData;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(''),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(color: p.card2, borderRadius: R.rXxl),
                    child: Icon(s.icon, size: 54, color: p.ink2),
                  ),
                ),
                const SizedBox(height: S.x5),
                Center(child: Text(s.name, style: F.t2.copyWith(color: p.ink))),
                const SizedBox(height: S.x2),
                Center(
                    child: Text(
                        s.connected ? 'Connected' : 'Not connected',
                        style: F.cap.copyWith(
                            color: s.connected ? p.on(C.green) : p.ink3))),
                const SizedBox(height: S.x6),
                TierRow(s.tier, filled: true),
                const SizedBox(height: S.x5),
                Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Column(children: [
                    SetRow(LucideIcons.batteryMedium, C.green, 'Battery',
                        value: battery == null ? '' : '${battery.round()}%',
                        sub: battery == null
                            ? 'Not reported since the last connection'
                            : (s.charging ? 'Charging' : ''),
                        chevron: false),
                    Divider(color: p.line, height: 1),
                    SetRow(LucideIcons.refreshCw, C.purple, 'Last data',
                        value: last == null ? '' : formatDayTime(last),
                        sub: last == null ? 'Nothing banked yet' : '',
                        chevron: false),
                    if (onFind != null) ...[
                      Divider(color: p.line, height: 1),
                      SetRow(LucideIcons.bellRing, C.orange, 'Buzz the band',
                          sub: 'Find it by feel', chevron: false,
                          onTap: onFind),
                    ],
                  ]),
                ),
                const SizedBox(height: S.x5),
                if (onForget != null)
                  Surface(
                    pad: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: SetRow(LucideIcons.trash2, C.red, 'Forget this band',
                        danger: true, chevron: false, onTap: onForget),
                  ),
                const SizedBox(height: S.x5),
                StatusCard(
                  'What this source can and cannot measure',
                  s.tier.detail,
                  icon: LucideIcons.activity,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// "Thu 4 Sep, 07:12" — local, which is what every day label in this app is.
String formatDayTime(DateTime d) {
  final t = '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
  return '${d.day}/${d.month}, $t';
}
