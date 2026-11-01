// Sources, not "devices".
//
// This is where the band-agnostic thesis has to be legible, because this is
// where someone goes to ask "which of my things is this number coming from?".
//
// The answer is a quality ladder, and the ordering rule is the inverse of the
// platform health stores, which rank by whatever wrote last. Here the better
// sensor wins (the band over the phone) and recency only breaks a tie within
// a tier. There is no user preference and the
// screen no longer claims one — no control ever set an order.
//
// Only what is measuring is listed. Importing a history is data adoption, not
// device support, so it never appears here.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../ble/adapters/_registry.dart'
    show kBandRegistry;
import '../../ble/band_status_l10n.dart' show localizedBandStatus;
import '../../ble/ble_state.dart' show BandStatus;
import '../../data/db.dart' show LocalDb;
import '../../l10n/app_localizations.dart';
import '../../notify/battery_forecast.dart';
import '../../sync/paired_device.dart' show cleanDeviceLabel;
import '../../state/app_state.dart';
import '../onboarding/pairing.dart';
import '../onboarding/profile_setup.dart' show formatDay;
import '../ui2.dart';
import 'profile.dart';
import 'settings.dart' show backToRoot;

/// Measurement quality, which is the ONLY thing that decides precedence.
enum SourceTier {
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
    'The phone’s own motion coprocessor. Steps and nothing else.',
    C.orange,
  );

  const SourceTier(this.rank, this.label, this.detail, this.accent);

  final int rank;
  final String label;
  final String detail;
  final Color accent;
}

/// Localized label/detail for a [SourceTier]. The enum's own `.label`/
/// `.detail` stay English-only (a const enum constructor can't take a
/// BuildContext) — this is the wrapper every render call site should use
/// instead, same split as `sourceState`/`_localizedSourceState` below.
String sourceTierLabel(BuildContext c, SourceTier t) {
  final l = AppLocalizations.of(c);
  switch (t) {
    case SourceTier.wristOptical:
      return l?.devicesTierWristOpticalLabel ?? t.label;
    case SourceTier.phone:
      return l?.devicesTierPhoneLabel ?? t.label;
  }
}

String sourceTierDetail(BuildContext c, SourceTier t) {
  final l = AppLocalizations.of(c);
  switch (t) {
    case SourceTier.wristOptical:
      return l?.devicesTierWristOpticalDetail ?? t.detail;
    case SourceTier.phone:
      return l?.devicesTierPhoneDetail ?? t.detail;
  }
}

/// This band's name, from the registry entry that decodes it — never asserted.
///
/// The two call sites here and in `day_steps.dart` both used to be
/// `generation == 'gen5' ? 'WHOOP 5' : 'WHOOP 4'`, which does not name a band,
/// it ASSERTS one: every future adapter, every imported day and every row
/// banked before the family stamp existed was published as a WHOOP 4. Null is
/// the honest answer for all of those, and every caller has a word for it.
String? bandLabelFor(String? adapterId) {
  if (adapterId == null || adapterId.isEmpty) return null;
  for (final e in kBandRegistry) {
    if (e.id == adapterId) return e.label;
  }
  return null;
}

/// Bands the owner has personally held and cross-confirmed. Everything else is
/// publicly EXPERIMENTAL, however well its fixtures pass — a fixture proves
/// determinism and physiological sanity, never correctness, and a decoder with
/// a 2× scale error reads a resting 50 bpm as 100 and passes every generic
/// bound. Hardware in his hands is the only promotion path.
///
/// ponytail: a const set here until the CODEOWNERS-gated `_verified.dart`
/// exists (ASSUMPTIONS E5). Move it there and delete this — it must never
/// become a CI rule, which would hand the key to the PR author.
const Set<String> kOwnerConfirmedBandIds = {'gen4', 'gen5'};
// Promotion requires physical-device validation, not only passing fixtures.

/// One thing that can produce measurements.
class HealthSource {
  final String name, kind;

  /// Where this source sits on the quality ladder, or NULL when it has no
  /// place on it.
  final SourceTier? tier;
  final IconData icon;
  final bool connected;

  /// Records are landing right now. Narrower than [connected] — an idle link
  /// is not a sync, and a multi-minute offload used to look identical to one.
  final bool syncing;
  final double? batteryPct;
  final bool charging;
  final DateTime? lastData;

  /// True for the PRIMARY band — the only source the offload engine drives,
  /// and the only one with band controls (rename, find, battery forecast).
  ///
  /// FALSE for the phone: it counts steps and is no substitute for a band.
  final bool isBand;

  /// The ingest-stamped sensor family (`'gen4'` / `'gen5'`), or null when the
  /// link has not said yet. Not cosmetic: it is the key every sensor-dependent
  /// metric looks its own constants up under, and null is a refusal.
  final String? family;

  /// Publicly EXPERIMENTAL — this band is decoded but the owner has never held
  /// one (see [kOwnerConfirmedBandIds]). Not a quality tier and not a
  /// confidence: it says who has checked, not how good the numbers are.
  bool get experimental =>
      family != null && !kOwnerConfirmedBandIds.contains(family);

  const HealthSource({
    required this.name,
    required this.kind,
    required this.tier,
    required this.icon,
    this.connected = false,
    this.syncing = false,
    this.batteryPct,
    this.charging = false,
    this.lastData,
    this.isBand = false,
    this.family,
  });
}

/// The one-row device disclosure (MT-12 / CV-04a).
///
/// Metrics whose correct behaviour depends on the sensor carry their own
/// per-family constants, so a gen4 strap and a gen5 strap can land on different
/// tiers for identical physiology. If that asymmetry is nowhere on screen the
/// tier stops meaning anything — so it lives on the band's own page, as one
/// row, next to the battery.
///
/// Returns null for a non-band source: the phone reports steps and nothing that
/// is calibrated per sensor.
(String value, String sub)? calibrationDisclosure(HealthSource s) {
  if (!s.isBand) return null;
  final label = bandLabelFor(s.family);
  if (label != null) {
    return (
      label,
      'Metrics that depend on the sensor use this band’s own constants, so two '
          'different bands can land on different tiers for the same physiology.'
    );
  }
  // Null is the honest majority case, not an error: every row banked before
  // the stamp existed, every import and every raw replay carries no family,
  // and those metrics abstain rather than borrow gen4's numbers. A family this
  // build has no registry entry for lands here too — an unknown band is not a
  // WHOOP 4.
  return (
    'Not stated yet',
    'This band has not said which generation it is, and imported or older '
        'days never will. Metrics that depend on the sensor abstain rather '
        'than borrow another band’s numbers.'
  );
}

/// The sources that actually exist right now. Nothing is listed that cannot
/// produce a number today.
///
List<HealthSource> liveSources(AppState app) => [
      if (app.isPaired)
        HealthSource(
          name: app.strapName ?? 'Your band',
          // The registry's own word for this band, or just what it is when the
          // link has not said. Never an assertion that an unnamed band is a
          // WHOOP 4.
          kind: [
            ?bandLabelFor(app.device.generation),
            'wrist optical',
          ].join(' · '),
          tier: SourceTier.wristOptical,
          icon: LucideIcons.watch,
          connected: app.isConnected,
          syncing: app.syncingNow,
          batteryPct: app.device.batteryPct,
          charging: app.device.charging ?? false,
          lastData: app.lastRecordAt,
          isBand: true,
          family: app.device.generation,
        ),
      if (app.phoneStepsEnabled)
        HealthSource(
          name: 'This phone',
          kind: 'Motion coprocessor',
          tier: SourceTier.phone,
          icon: LucideIcons.smartphone,
          // NOT the toggle. On iOS `requestAuthorization` reports success even
          // when the user denied READ, so the toggle sits on while every read
          // comes back empty — this row used to hardcode `true` and claim a
          // source that was measuring nothing. Steps actually banked is the
          // only evidence the phone is a source.
          connected: app.phoneStepsLastSyncedDays != null &&
              (app.phoneStepsLastTotal ?? 0) > 0,
        ),
    ];

/// Quality first, then recency, then the name. The inverse of last-writer-wins.
///
/// There was a `preferred` list here that no caller ever passed and no screen
/// could set — the card above it told the user their own preference was "the
/// last word", which was a mechanism that did not exist.
List<HealthSource> rankSources(List<HealthSource> sources) {
  final out = [...sources];
  out.sort((a, b) {
    // An unranked source sorts BELOW every ranked one — it is not competing
    // for precedence, because it supplies nothing to compete with.
    final byTier = (a.tier?.rank ?? 99).compareTo(b.tier?.rank ?? 99);
    if (byTier != 0) return byTier;
    final at = a.lastData, bt = b.lastData;
    if (at != null && bt != null && at != bt) return bt.compareTo(at);
    if (at != null) return -1;
    if (bt != null) return 1;
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
      // The band row's dot says connected or not. That covers six different
      // problems with six different fixes, and a user cannot fix a problem the
      // app will not name — so the engine's own verdict rides alongside it.
      status: app.isPaired ? app.engine.bandStatus : null,
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

  /// The band's own state, from `bandStatusFor`. Null when nothing is paired.
  final BandStatus? status;

  const MyDevicesView({
    super.key,
    this.sources = const [],
    this.onPair,
    this.status,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final localizedStatus =
        status == null ? null : localizedBandStatus(c, status!);
    final fault = localizedStatus?.isFault == true ? localizedStatus : null;
    // A BAND, not "a source". The phone is a source and it is not a substitute
    // for one: gating this on `sources.isEmpty` meant a phone counting steps
    // hid the only route back to pairing, and forgetting a band left the user
    // stranded with a steps row and no way to add another.
    final hasBand = sources.any((s) => s.isBand);

    // THE PHONE ROW IS LISTED WHENEVER THE TOGGLE IS ON, connected or not —
    // `connected` there is "steps have actually been banked", because on iOS
    // the toggle sits on while a denied READ permission returns nothing. So
    // "a source exists" was the wrong test for this card: it told a user
    // whose phone was measuring nothing that "the phone counts steps".
    final phoneCounting = sources.any((s) => !s.isBand && s.connected);
    final l = AppLocalizations.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.devicesMySources ?? 'My sources'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                // FIRST, in the tier-2 slot the missing band would occupy —
                // not appended under the phone. Someone who has just forgotten
                // a band is here to add one, and the row they can see is not
                // the one they came for.
                if (!hasBand) ...[
                  StatusCard(
                    phoneCounting
                        ? (l?.devicesNoBandPaired ?? 'No band is paired')
                        : (l?.devicesNothingMeasuringYet ??
                            'Nothing is measuring yet'),
                    phoneCounting
                        ? (l?.devicesPhoneCountingBody ??
                            'The phone counts steps and nothing else. Heart '
                                'rate, sleep, recovery and temperature all abstain '
                                'until a band is paired.')
                        : (l?.devicesNothingMeasuringBody ??
                            'No band is paired and no phone steps are arriving, '
                                'so every metric in the app will abstain rather '
                                'than estimate.'),
                    fix: l?.devicesPairABand ?? 'Pair a band',
                    icon: LucideIcons.watch,
                    onFix: onPair,
                  ),
                  if (sources.isNotEmpty) const SizedBox(height: S.x3),
                ],
                // LIVE — the first of the two buckets. Only drawn when there is
                // something in it: a heading over nothing is the empty rung
                // problem again, one level up.
                if (sources.isNotEmpty) ...[
                  Text(l?.devicesLive ?? 'LIVE', style: F.over.copyWith(color: p.ink3)),
                  const SizedBox(height: S.x3),
                ],
                for (final s in sources) ...[
                  SourceRow(s, onTap: () => goto(c, DeviceDetail(s))),
                  if (s.isBand && fault != null) ...[
                    const SizedBox(height: S.x2),
                    StatusCard(fault.title, fault.reason,
                        fix: fault.fix ?? '',
                        icon: LucideIcons.bluetoothOff),
                  ],
                  const SizedBox(height: S.x3),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// The one line under a source's name.
///
/// "Not connected" is a statement about a radio link, and the phone has none:
/// it is either handing steps over or it is not, which is exactly the failure
/// the row used to hide behind a hardcoded "Connected".
// Kept context-free and directly tested (see ui2_router_test.dart) — this
// is the tier/connection LOGIC, not just
// copy. `_localizedSourceState` below is what the UI actually renders.
String sourceState(HealthSource s) {
  if (s.tier == SourceTier.phone) {
    return s.connected ? 'Reporting steps' : 'No steps arriving';
  }
  if (s.syncing) return 'Syncing';
  return s.connected ? 'Connected' : 'Not connected';
}

String _localizedSourceState(BuildContext c, HealthSource s) {
  final l = AppLocalizations.of(c);
  if (s.tier == SourceTier.phone) {
    return s.connected
        ? (l?.devicesReportingSteps ?? 'Reporting steps')
        : (l?.devicesNoStepsArriving ?? 'No steps arriving');
  }
  if (s.syncing) return l?.devicesSyncing ?? 'Syncing';
  return s.connected
      ? (l?.devicesConnected ?? 'Connected')
      : (l?.devicesNotConnected ?? 'Not connected');
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
                // Flexible because this string is not fixed: "Not connected"
                // and "No steps arriving" are 10 px wider than the column at
                // 390 pt, and an unflexed Text in a Wrap simply overflows.
                Flexible(
                  child: Text(_localizedSourceState(c, s),
                      style: F.over.copyWith(
                          color: s.connected ? p.on(C.green) : p.ink3)),
                ),
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
              // IN THE WRAP, not a second trailing pill: this line already
              // wraps at accessibility sizes, and a pill column beside it does
              // not. The band's own page carries the explanation.
              if (s.experimental)
                Text(AppLocalizations.of(c)?.devicesExperimental ?? 'Experimental',
                    style: F.over.copyWith(color: p.on(C.orange))),
            ]),
          ]),
        ),
        const SizedBox(width: S.x2),
        // No pill for an unranked source. A blank one reads as tier zero.
        if (s.tier case final t?)
          Pill(AppLocalizations.of(c)?.devicesTierRank(t.rank) ?? 'Tier ${t.rank}',
              t.accent),
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
            Text(
                AppLocalizations.of(c)?.devicesTierRankLabel(
                        tier.rank, sourceTierLabel(c, tier)) ??
                    'Tier ${tier.rank} · ${tier.label}',
                style: F.body.copyWith(
                    color: filled ? p.ink : p.ink2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: S.x1),
            Text(sourceTierDetail(c, tier),
                style: F.cap.copyWith(color: p.ink3, height: 1.5)),
            if (!filled) ...[
              const SizedBox(height: S.x1),
              // A dashed circle and a paler wash are not a statement. Without
              // a word here an empty rung reads exactly like the tier you do
              // have — including to a screen reader, which sees neither.
              Text(AppLocalizations.of(c)?.devicesNothingHereYet ?? 'Nothing here yet',
                  style: F.over.copyWith(color: p.ink3)),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════ DEVICE DETAIL ══════════════════

class DeviceDetail extends StatefulWidget {
  final HealthSource s;
  const DeviceDetail(this.s, {super.key});

  @override
  State<DeviceDetail> createState() => _DeviceDetailState();
}

class _DeviceDetailState extends State<DeviceDetail>
    with WidgetsBindingObserver {
  /// Held, not rebuilt: this screen watches AppState, so a FutureBuilder given
  /// a fresh `batteryHealth()` on every build would rescan the sample table on
  /// every connection tick.
  Map<String, dynamic>? _health;

  /// The same projection the overnight charge warning fires on, read here
  /// rather than recomputed: this screen is where someone asks "how long have I
  /// got", and the answer was already being calculated and only ever spent on a
  /// notification they may have dismissed.
  BatteryForecast? _forecast;
  AppState? _app;
  int _load = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = widget.s.isBand ? context.read<AppState>() : null;
    if (identical(app, _app)) return;
    _app?.batteryRevision.removeListener(_loadForecast);
    _app = app;
    _app?.batteryRevision.addListener(_loadForecast);
    _loadForecast();
  }

  @override
  void didUpdateWidget(covariant DeviceDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.s.batteryPct != widget.s.batteryPct ||
        oldWidget.s.charging != widget.s.charging ||
        oldWidget.s.family != widget.s.family)
      _loadForecast();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadForecast();
  }

  @override
  void dispose() {
    _load++;
    _app?.batteryRevision.removeListener(_loadForecast);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadForecast() async {
    final load = ++_load;
    if (!widget.s.isBand) return;
    setState(() {
      _forecast = null;
      _health = null;
    });
    try {
      final rows = await LocalDb.recentBandBatterySamples(limit: 400);
      final health = await LocalDb.batteryHealth();
      final now = DateTime.now();
      final f = const BatteryForecaster().forecast(
        samples: [
          for (final r in rows)
            if (r['battery_pct'] != null && r['ts'] != null)
              BatterySample(
                tsSec: (r['ts'] as num).toInt(),
                pct: (r['battery_pct'] as num).toDouble(),
                charging: (r['charging'] as num?)?.toInt() == 1,
              ),
        ],
        now: now,
        // Only `predictedEmptyAt` is read below, and it does not depend on the
        // wake time — the projection to a wake time is the notification's
        // question, not this screen's.
        wakeAt: now,
      );
      if (mounted && load == _load)
        setState(() {
          _forecast = f;
          _health = health;
        });
    } catch (_) {
      // A projection is a nicety. The screen's real job is the band's state.
    }
  }

  @override
  Widget build(BuildContext c) {
    final app = widget.s.isBand ? c.watch<AppState>() : null;
    // Build 93 (Codex audit C07): the band's name, battery, charging and
    // last data are read from the live state on every change, not from the
    // list row this page was opened from.
    final s = app == null
        ? widget.s
        : liveSources(app).where((x) => x.isBand).firstOrNull ?? widget.s;
    return DeviceDetailView(
      s,
      status: app?.engine.bandStatus,
      health: _health,
      forecast: s.charging ? null : _forecast,
      onFind: app != null && app.isConnected
          ? () async {
              final messenger = ScaffoldMessenger.maybeOf(c);
              final sent = await app.buzzBand();
              messenger?.showSnackBar(
                SnackBar(content: Text(sent ? 'Buzz command sent to the band.' : 'Could not send the buzz. Reconnect your band and try again.')),
              );
            }
          : null,
      liveHr: s.isBand ? app?.liveHr : null,
      onRename: (app != null && app.isConnected)
          ? () => _renameBand(c, app, s.name)
          : null,
      onForget: app == null ? null : () => _confirmForget(c, app, s.name),
    );
  }
}

/// Rename the strap.
///
/// This was in the old UI and did not survive the rebuild, which left the
/// advertising name readable and not writable — and it is the one label a user
/// with two straps needs, since both otherwise read "Your band".
///
/// The band's own limits are the field's limits, checked here so a refusal is
/// immediate instead of a silent truncation 20 characters in: 20 ASCII
/// characters, the charset `cleanDeviceLabel` accepts on the way back, and at
/// least one letter or digit. Anything the strap would reject or mangle is
/// rejected in the sheet, where the user can still fix it.
Future<void> _renameBand(BuildContext c, AppState app, String current) async {
  // Captured before the dialog: `c` is not safe to touch after the await.
  final messenger = ScaffoldMessenger.maybeOf(c);
  final l = AppLocalizations.of(c);
  final nameGuidance = l?.devicesNameCharset ??
      "Letters, numbers, space, and ' . _ -";
  var draft = current;
  String? error;
  final name = await showDialog<String>(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, setDialogState) => AlertDialog(
        scrollable: true,
        insetPadding: bigText(d)
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        title: Text(l?.devicesNameThisBand ?? 'Name this band'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            initialValue: current,
            onChanged: (value) => draft = value,
            autofocus: true,
            maxLength: 20,
            decoration: InputDecoration(
              hintText: l?.devicesYourBand ?? 'Your band',
              errorText: error,
              helperText: nameGuidance,
              helperMaxLines: nameGuidance.runes.length,
              errorMaxLines: error?.runes.length,
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(d).pop(),
              child: Text(l?.actionCancel ?? 'Cancel')),
          TextButton(
            onPressed: () {
              final value = draft.trim();
              if (value.isEmpty) {
                setDialogState(() => error = l?.devicesGiveItAName ?? 'Give it a name');
              } else if (cleanDeviceLabel(value) == null) {
                setDialogState(() => error = l?.devicesNameCharsetError ??
                    "Only letters, numbers, space, and ' . _ -");
              } else {
                Navigator.of(d).pop(value);
              }
            },
            child: Text(l?.actionSave ?? 'Save'),
          ),
        ],
      ),
    ),
  );
  if (name == null) return;
  try {
    await app.renameStrap(name);
    if (messenger?.mounted != true) return;
    messenger?.showSnackBar(
        SnackBar(content: Text(l?.devicesRenamedTo(name) ?? 'Renamed to $name')));
  } catch (e) {
    // The write goes to the strap, so a dropped link loses it. Say that,
    // rather than leaving the old name on screen with no explanation.
    if (messenger?.mounted != true) return;
    messenger?.showSnackBar(SnackBar(
        content: Text(l?.devicesCouldNotRename(e.toString()) ??
            'Could not rename the band: $e')));
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
  final l = AppLocalizations.of(c);
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(l?.devicesForgetBand(name) ?? 'Forget $name?'),
      content: Text(
        l?.devicesForgetBandBody ??
            'The band stops syncing and has to be paired again to measure '
                'anything. Everything already banked on this phone is kept — this '
                'removes the source, not the data.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l?.devicesKeepItPaired ?? 'Keep it paired')),
        TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l?.devicesForgetIt ?? 'Forget it')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await app.unpair();
  } catch (_) {
    if (c.mounted) {
      ScaffoldMessenger.maybeOf(c)?.showSnackBar(
        const SnackBar(content: Text(
          'The band disconnected, but forgetting it did not finish. Try again.',
        )),
      );
    }
    return;
  }
  if (c.mounted) backToRoot(c);
}

class DeviceDetailView extends StatelessWidget {
  final HealthSource s;
  final VoidCallback? onFind, onForget;

  /// The beat arriving right now, or null when nothing fresh is streaming.
  /// Passed IN rather than read from a provider here: this view is rendered in
  /// tests with no Provider above it, which is the point of it being a view.
  final int? liveHr;

  /// Rename the band. Null when there is nothing to rename (the phone) or no
  /// link to carry the write — the name lives on the strap, not on the phone,
  /// so an offline rename would be a lie the next connect quietly undoes.
  final VoidCallback? onRename;

  /// The band's own state, from `bandStatusFor`. Null for a non-band source.
  final BandStatus? status;

  /// `LocalDb.batteryHealth()` — the recent `band_battery` series, which is the
  /// one table nothing prunes. Null until it loads, and on a non-band source.
  final Map<String, dynamic>? health;

  /// `BatteryForecaster.forecast` over the same series. Null until it loads and
  /// on a non-band source; an ABSTAINING forecast is a valid value and draws
  /// nothing.
  final BatteryForecast? forecast;

  const DeviceDetailView(this.s,
      {super.key,
      this.onFind,
      this.onForget,
      this.onRename,
      this.liveHr,
      this.status,
      this.health,
      this.forecast});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final localizedStatus =
        status == null ? null : localizedBandStatus(c, status!);
    final battery = s.batteryPct;
    final last = s.lastData;
    final fault =
        localizedStatus?.isFault == true ? localizedStatus : null;
    final calibration = calibrationDisclosure(s);
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
                // A fault names itself in the card below; repeating its title
                // here would say the same thing twice in two type sizes.
                if (fault == null)
                  Center(
                      child: Text(
                          localizedStatus?.title ?? _localizedSourceState(c, s),
                          style: F.cap.copyWith(
                              color: s.connected ? p.on(C.green) : p.ink3))),
                const SizedBox(height: S.x6),
                if (fault != null) ...[
                  StatusCard(fault.title, fault.reason,
                      fix: fault.fix ?? '', icon: LucideIcons.bluetoothOff),
                  const SizedBox(height: S.x5),
                ],
                if (s.tier case final t?) ...[
                  TierRow(t, filled: true),
                  const SizedBox(height: S.x5),
                ],
                // Band rows only. The phone has no radio link and no battery
                // this app can read, so "Not reported since the last
                // connection" named a connection it does not have — on the
                // exact screen someone lands on when phone steps are silently
                // failing, where the answer is the permission, not a battery.
                if (s.isBand)
                  Surface(
                    pad: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: Column(children: [
                      // The name is the band's own advertising name, written
                      // to the strap — not a phone-side label. So it is only
                      // editable on a live link, and the row says so rather
                      // than opening an editor whose save cannot land.
                      SetRow(LucideIcons.tag, C.blue, l?.devicesName ?? 'Name',
                          value: s.name,
                          sub: onRename == null
                              ? (l?.devicesConnectToRename ??
                                  'Connect to the band to change it')
                              : '',
                          chevron: onRename != null,
                          onTap: onRename),
                      Divider(color: p.line, height: 1),
                      SetRow(LucideIcons.batteryMedium, C.green,
                          l?.devicesBattery ?? 'Battery',
                          value: battery == null ? '' : '${battery.round()}%',
                          // L11 — the band's own charge history, on the row
                          // that already exists rather than a new one. Within
                          // THIS band only: `charge_cycles` counts times it went
                          // on the charger, not full cycles, and the millivolts
                          // are the highest reading seen while charging — so
                          // neither is ever put against a cell spec, turned
                          // into a percentage of original capacity, or read as
                          // "replace the battery".
                          //
                          // Both were structurally blank until schema 45: the
                          // voltage had no writer at all, so this line has shown
                          // nothing on every install there has ever been.
                          sub: battery == null
                              ? (l?.devicesBatteryNotReported ??
                                  'Not reported since the last connection')
                              : [
                                  if (s.charging) (l?.devicesCharging ?? 'Charging'),
                                  ?_timeLeft(forecast),
                                  ?_chargeHistory(health),
                                ].join(' · '),
                          chevron: false),
                      Divider(color: p.line, height: 1),
                      // Live, not a stored reading: present only while the
                      // band is actually streaming, and gone the moment it
                      // stops.
                      if (liveHr != null) ...[
                        SetRow(LucideIcons.heartPulse, C.red,
                            l?.devicesHeartRate ?? 'Heart rate',
                            value: '$liveHr bpm',
                            sub: l?.devicesRightNow ?? 'Right now',
                            chevron: false),
                        Divider(color: p.line, height: 1),
                      ],
                      SetRow(LucideIcons.refreshCw, C.purple,
                          l?.devicesLastData ?? 'Last data',
                          value: last == null ? '' : formatDayTime(last, l),
                          sub: last == null
                              ? (l?.devicesNothingBankedYet ?? 'Nothing banked yet')
                              : '',
                          chevron: false),
                      if (calibration != null) ...[
                        Divider(color: p.line, height: 1),
                        SetRow(LucideIcons.sliders, C.teal,
                            l?.devicesCalibration ?? 'Calibration',
                            value: calibration.$1,
                            sub: calibration.$2,
                            chevron: false),
                      ],
                      // WHO HAS CHECKED, not how good the numbers are. Said
                      // here rather than only as a word on the list row,
                      // because "experimental" without the reason reads as a
                      // disclaimer instead of a fact about this band.
                      if (s.experimental) ...[
                        Divider(color: p.line, height: 1),
                        SetRow(LucideIcons.flaskConical, C.orange,
                            l?.devicesSupport ?? 'Support',
                            value: l?.devicesExperimental ?? 'Experimental',
                            sub: l?.devicesBandExperimentalSub ??
                                'This band is decoded but nobody here has worn '
                                    'one. Its numbers have not been checked against '
                                    'the hardware, only against the protocol.',
                            chevron: false),
                      ],
                      if (onFind != null) ...[
                        Divider(color: p.line, height: 1),
                        SetRow(LucideIcons.bellRing, C.orange,
                            l?.devicesBuzzTheBand ?? 'Buzz the band',
                            sub: l?.devicesFindItByFeel ?? 'Find it by feel',
                            chevron: false,
                            onTap: onFind),
                      ],
                    ]),
                  ),
                const SizedBox(height: S.x5),
                if (onForget != null)
                  Surface(
                    pad: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: SetRow(LucideIcons.trash2, C.red,
                        l?.devicesForgetThisBand ?? 'Forget this band',
                        danger: true, chevron: false, onTap: onForget),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// "about 2 days left" — or null on an abstention, which is most of the time
/// and is meant to be: the forecaster refuses on the charger, on too few
/// samples, on too short a span and on an implausible rate, and a battery
/// number the user can read for themselves is better than a made-up deadline.
///
/// Deliberately coarse. The estimate is a median slope through a percentage
/// that only moves in whole points, so it does not support a time of day, and
/// printing one would claim a precision this cannot carry. "About" is doing
/// real work in that sentence.
String? _timeLeft(BatteryForecast? f) {
  final empty = f?.predictedEmptyAt;
  if (empty == null) return null;
  final left = empty.difference(DateTime.now());
  if (left.isNegative) return null;
  if (left.inHours < 1) return 'under an hour left';
  if (left.inHours < 36) return 'about ${left.inHours} h left';
  return 'about ${(left.inHours / 24).round()} days left';
}

/// "12 charges logged, up to 4,180 mV" — or null when there is no history to
/// report yet. Two facts about this band and nothing derived from them: nothing
/// here knows the pack's design capacity, and going on the charger is not a
/// cycle.
String? _chargeHistory(Map<String, dynamic>? h) {
  final cycles = (h?['charge_cycles'] as num?)?.toInt() ?? 0;
  if (cycles <= 0) return null;
  final mv = (h?['full_charge_mv'] as num?)?.toInt();
  return '$cycles charge${cycles == 1 ? '' : 's'} logged'
      '${mv == null ? '' : ', up to $mv mV'}';
}

/// "Thu 4 Sep, 07:12" — local, which is what every day label in this app is.
///
/// It used to render `4/9, 07:12`, which a US reader reads as 9 April. The
/// month name is the whole point; `formatDay` already writes one.
String formatDayTime(DateTime d, [AppLocalizations? l]) {
  return '${formatDay(d, l)}, ${formatClock(d)}';
}
