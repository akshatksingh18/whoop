// Pairing.
//
// The failure states are the screen. A hardware app that says "Couldn't pair"
// and offers a Retry button has told the user nothing and given them nowhere
// to go — the audit found exactly that here: a refused bond and a dismissed
// picker fell through to the same dead end. They are different problems with
// different fixes, and neither of them is the user's fault.
//
// There is also always a way out. Someone whose band is flat, or who is
// installing this before the hardware arrives, must be able to reach the app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../ble/band_status_l10n.dart' show localizedBandStatus;
import '../../ble/ble_state.dart';
import '../../l10n/app_localizations.dart';
import '../localization.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../ui2.dart';

/// Onboarding steps the user deliberately walked past.
///
/// [AppState.route] is derived purely from device + profile state, so a user
/// who skips pairing (band flat, hardware not arrived) or who leaves an
/// optional profile field blank would be bounced back to the same step
/// forever. The bypass is the user's answer to that, and it is theirs to
/// give — so it is recorded here rather than by weakening the conditions
/// AppState uses for everything else.
abstract final class OnboardingBypass {

  static const kPairing = 'onboard.skipped_pairing';
  static const kProfile = 'onboard.saw_profile_setup';

  /// Bumped on every skip so the gate — which selects on the AppState route,
  /// not on SharedPreferences — rebuilds.
  static final revision = ValueNotifier<int>(0);

  static bool get pairingSkipped => Prefs.getBool(kPairing, false);
  static bool get profileSeen => Prefs.getBool(kProfile, false);

  static void mark(String key) {
    Prefs.setBool(key, true);
    revision.value++;
  }

  // No `clear`. Un-skipping cannot walk the gate back to pairing: the shell
  // latches `onboarded` on its first frame and the gate sends pairing/profile
  // straight to the shell from then on. "Pair a band" pushes `RePair` instead
  // — see `profile/devices.dart`.
}

enum PairPhase {
  /// Nothing tried yet.
  idle,
  scanning,

  /// The phone's own Bluetooth stack refused us — permission, radio off, or no
  /// BLE at all. Nothing about the band is known yet, and every band-side
  /// instruction ("wake it, hold it close") is a wasted walk around the house.
  bluetoothBlocked,

  /// The scan completed and found nothing in range.
  notFound,

  /// The link came up but the band refused to bond. Distinct because the fix
  /// is in the phone's own Bluetooth settings, not in this app.
  bondRefused,

  /// The system picker was dismissed. Not an error — do not shout.
  cancelled,

  /// Anything else, with the real message attached.
  failed,
  paired,
}

/// The phone-side blocker behind a thrown pairing error, or null when the
/// failure is genuinely about the band.
///
/// [BleUnavailableException] is checked before the string matcher because it
/// carries the verdict already: its `adapterOff` case does not contain any of
/// the phrases the matcher looks for, so classifying it by text alone would
/// silently demote a radio-off to a band fault.
BleBlocker? pairBlocker(Object error) => error is BleUnavailableException
    ? error.blocker
    : classifyBleBlocker(error: error);

/// Classify a thrown pairing error. Pure — this is the whole reason the
/// distinct states exist rather than one "Couldn't pair".
PairPhase classifyPairError(Object error, {int bondRefusals = 0}) {
  // First, because this is the one failure that is not about the band at all.
  // It used to fall through to `failed` (or, via a null scan, to "No band in
  // range"), which sends someone who revoked a permission looking for hardware.
  if (pairBlocker(error) != null) return PairPhase.bluetoothBlocked;
  final s = error.toString().toLowerCase();
  if (s.contains('cancel') || s.contains('dismiss')) return PairPhase.cancelled;
  if (bondRefusals > 0 || s.contains('bond') || s.contains('encrypt')) {
    return PairPhase.bondRefused;
  }
  return PairPhase.failed;
}

class PairingScreen extends StatefulWidget {
  /// Walk past pairing and open the app anyway. Supplied by the router.
  final VoidCallback? onSkip;

  const PairingScreen({super.key, this.onSkip});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  PairPhase _phase = PairPhase.idle;
  String _detail = '';
  BleBlocker? _blocker;

  Future<void> _pair() async {
    final app = context.read<AppState>();
    setState(() {
      _phase = PairPhase.scanning;
      _detail = '';
      _blocker = null;
    });
    try {
      if (await app.accessorySetupSupported()) {
        await app.pairViaAccessorySetup();
      } else {
        final found = await app.scanForBand();
        if (found == null) {
          if (mounted) setState(() => _phase = PairPhase.notFound);
          return;
        }
        await app.pairWith(found);
      }
      if (!mounted) return;
      setState(() => _phase = PairPhase.paired);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _blocker = pairBlocker(e);
        _phase = classifyPairError(e, bondRefusals: app.device.bondRefusals);
        _detail = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext c) => PairingView(
        phase: _phase,
        detail: _detail,
        blocker: _blocker,
        onPair: _pair,
        onSkip: widget.onSkip,
      );
}

class PairingView extends StatelessWidget {
  final PairPhase phase;
  final String detail;
  final VoidCallback onPair;
  final VoidCallback? onSkip;

  /// Which phone-side blocker, when [phase] is `bluetoothBlocked`.
  final BleBlocker? blocker;

  const PairingView({
    super.key,
    required this.phase,
    required this.onPair,
    this.detail = '',
    this.blocker,
    this.onSkip,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final busy = phase == PairPhase.scanning;
    // The copy for this one lives in the BLE layer, so this screen and the
    // Devices screen cannot drift into two different accounts of one state.
    final blocked = phase == PairPhase.bluetoothBlocked
        ? localizedBandStatus(
            c, bandStatusFor(connection: 'disconnected', blocker: blocker))
        : null;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x8, S.x4, S.x8),
          children: [
            Icon(
                blocked == null
                    ? LucideIcons.bluetooth
                    : LucideIcons.bluetoothOff,
                size: 36,
                color: p.on(C.blue)),
            const SizedBox(height: S.x5),
            Text(_title(c, phase, blocker), style: F.t1.copyWith(color: p.ink)),
            const SizedBox(height: S.x3),
            Text(_body(c, phase, blocker), style: F.body.copyWith(color: p.ink2)),
            if (blocked?.fix != null) ...[
              const SizedBox(height: S.x3),
              Text(blocked!.fix!,
                  style: F.body.copyWith(
                      color: p.on(C.blue), fontWeight: FontWeight.w600)),
            ],
            if (busy) ...[
              const SizedBox(height: S.x8),
              Center(child: CircularProgressIndicator(color: p.on(C.blue))),
            ],
            ..._advice(c, phase, detail),
            const SizedBox(height: S.x8),
            BigButton(_cta(c, phase),
                icon: LucideIcons.radio,
                color: C.blue,
                onTap: busy ? null : onPair),
            if (onSkip != null && phase != PairPhase.paired) ...[
              const SizedBox(height: S.x3),
              // Never disabled, not even mid-scan: waiting out a scan you
              // already know will fail is exactly the trap this exists for.
              BigButton(AppLocalizations.of(c)?.pairingSkipForNow ?? 'Skip for now',
                  color: C.blue, soft: true, onTap: onSkip),
              const SizedBox(height: S.x2),
              Text(
                AppLocalizations.of(c)?.pairingSkipNote ??
                    'The app opens without a band. Nothing is measured until one '
                        'is paired.',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _title(BuildContext c, PairPhase phase, [BleBlocker? blocker]) {
    final l = AppLocalizations.of(c);
    return switch (phase) {
      PairPhase.bluetoothBlocked => localizedBandStatus(
          c, bandStatusFor(connection: 'disconnected', blocker: blocker))
        .title,
      PairPhase.idle => withEnglishFallback(l).pairingIdleTitle,
      PairPhase.scanning => withEnglishFallback(l).pairingScanningTitle,
      PairPhase.notFound => withEnglishFallback(l).pairingNotFoundTitle,
      PairPhase.bondRefused =>
        withEnglishFallback(l).pairingBondRefusedTitle,
      PairPhase.cancelled => withEnglishFallback(l).pairingCancelledTitle,
      PairPhase.failed => withEnglishFallback(l).pairingFailedTitle,
      PairPhase.paired => withEnglishFallback(l).pairingPairedTitle,
    };
  }

  static String _body(BuildContext c, PairPhase phase, [BleBlocker? blocker]) {
    final l = AppLocalizations.of(c);
    return switch (phase) {
      PairPhase.bluetoothBlocked => localizedBandStatus(
          c, bandStatusFor(connection: 'disconnected', blocker: blocker))
        .reason,
      PairPhase.idle => withEnglishFallback(l).pairingIdleBody,
      PairPhase.scanning => withEnglishFallback(l).pairingScanningBody,
      PairPhase.notFound => withEnglishFallback(l).pairingNotFoundBody,
      PairPhase.bondRefused => withEnglishFallback(l).pairingBondRefusedBody,
      PairPhase.cancelled => withEnglishFallback(l).pairingCancelledBody,
      PairPhase.failed => withEnglishFallback(l).pairingFailedBody,
      PairPhase.paired => withEnglishFallback(l).pairingPairedBody,
    };
  }

  static String _cta(BuildContext c, PairPhase phase) {
    final l = AppLocalizations.of(c);
    return switch (phase) {
      PairPhase.idle => withEnglishFallback(l).pairingFindMyBand,
      PairPhase.scanning => withEnglishFallback(l).pairingSearching,
      PairPhase.cancelled => withEnglishFallback(l).pairingOpenPickerAgain,
      PairPhase.paired => withEnglishFallback(l).actionContinue,
      _ => withEnglishFallback(l).pairingTryAgain,
    };
  }

  /// The fix, spelled out, for the states that have one.
  List<Widget> _advice(BuildContext c, PairPhase phase, String detail) {
    final l = AppLocalizations.of(c);
    return switch (phase) {
      PairPhase.notFound => [
          const SizedBox(height: S.x6),
          StatusCard(
            withEnglishFallback(l).pairingNotFoundAdviceTitle,
            withEnglishFallback(l).pairingNotFoundAdviceBody,
            fix: withEnglishFallback(l).pairingNotFoundAdviceFix,
            icon: LucideIcons.searchX,
          ),
        ],
      PairPhase.bondRefused => [
          const SizedBox(height: S.x6),
          StatusCard(
            withEnglishFallback(l).pairingBondRefusedAdviceTitle,
            withEnglishFallback(l).pairingBondRefusedAdviceBody,
            fix: withEnglishFallback(l).pairingBondRefusedAdviceFix,
            icon: LucideIcons.unlink,
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: S.x3),
            _Detail(detail),
          ],
        ],
      PairPhase.failed => [
          const SizedBox(height: S.x6),
          StatusCard(
            withEnglishFallback(l).pairingFailedAdviceTitle,
            withEnglishFallback(l).pairingFailedAdviceBody,
            icon: LucideIcons.triangleAlert,
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: S.x3),
            _Detail(detail),
          ],
        ],
      _ => const [],
    };
  }
}

/// The raw error, kept but demoted. It is useless to most people and the only
/// thing that helps in a bug report.
class _Detail extends StatelessWidget {
  final String text;
  const _Detail(this.text);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      elevation: 0,
      color: p.card2,
      child: Text(text, style: F.cap.copyWith(color: p.ink3)),
    );
  }
}
