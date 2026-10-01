// Breathing pattern in sleep — the across-nights heart-rate-cycling screen.
//
// Restored from the removed Nerd stats screen because it is a sleep-quality
// signal no other screen carries. Only the ACROSS-NIGHTS card comes back, not
// the per-night table: one night's cycle count moves for a dozen reasons, and
// the aggregate exists precisely so no single night is read as a finding.
//
// It stays one tap below Sleep rather than on it, for the reason the original
// gave: as a headline on the Sleep screen, a pattern that also fires on an
// irregular rhythm, altitude or any broken-up night becomes a diagnosis in
// somebody's head. The copy names no condition, shows no number except how
// many nights are behind it, never reassures, and ends in a clinician.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart' show envValue, pointsOf;
import 'metric_detail.dart' show detailScaffold;

class SleepBreathingScreen extends StatefulWidget {
  const SleepBreathingScreen({super.key, this.data});

  /// Injected by tests; null loads from the repository.
  final ana.Metric<ana.CvhrDistribution>? data;

  /// Assemble the stored nights and hand them to the analytics screen. A night
  /// the screen abstained on is not a zero and never enters the denominator.
  ///
  /// ponytail: one bundle read per night over the window, paid once on open.
  /// If it ever feels slow, add a repo read of `cvhr_per_hour` and
  /// `analyzed_hours` without the payload rather than shrinking the window.
  static Future<ana.Metric<ana.CvhrDistribution>> load(
      LocalRepository repo) async {
    final days = await repo.availableDays();
    final flags = <String, double>{
      for (final p in pointsOf(await repo.getChart('irregular_rhythm_flag')))
        dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)): p.v,
    };
    final nights = <ana.CvhrNight>[];
    for (final day in days.take(ana.cvhrDistributionWindowNights)) {
      final v = envValue((await repo.getDayLungs(day))['cvhr']);
      final rate = v?['cvhr_per_hour'] as num?;
      final hours = v?['analyzed_hours'] as num?;
      if (rate == null || hours == null) continue;
      nights.add(ana.CvhrNight(
        dayKey: day,
        cvhrPerHour: rate.toDouble(),
        analyzedHours: hours.toDouble(),
        irregularRhythm: (flags[day] ?? 0) >= 1,
      ));
    }
    return ana.cvhrPersonalDistribution(nights);
  }

  @override
  State<SleepBreathingScreen> createState() => _SleepBreathingScreenState();
}

class _SleepBreathingScreenState extends State<SleepBreathingScreen> {
  ana.Metric<ana.CvhrDistribution>? _m;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _m = widget.data;
      _loading = false;
      return;
    }
    final repo = context.read<AppState>().repo;
    if (repo == null) {
      _loading = false;
      return;
    }
    SleepBreathingScreen.load(repo).then((m) {
      if (mounted) setState(() => (_m = m, _loading = false));
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final m = _m;
    final v = m?.value;
    return detailScaffold(c, 'Breathing pattern in sleep', [
      if (_loading) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else if (v == null)
        StatusCard(
          l?.investigateNotEnoughNightsAcross ??
              'Not enough nights for the across-nights view',
          l?.investigateNeedsSeveralNights ??
              'This needs several nights with a few observed hours each.',
          icon: LucideIcons.wind,
        )
      else
        Surface(
          color: p.card2,
          elevation: 0,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                l?.investigateAcrossNOwnNights(v.nightsUsed) ??
                    'ACROSS ${v.nightsUsed} OF YOUR OWN NIGHTS',
                style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x3),
            Text(
              v.aboveOwnUsual
                  ? (l?.investigateCvhrAboveUsual(v.nightsUsed) ??
                      'Over your most recent nights, the heart-rate cycling '
                          'this screen counts has been running higher than '
                          'across the ${v.nightsUsed} nights behind it.')
                  : (l?.investigateCvhrInsideUsual(v.nightsUsed) ??
                      'Over your most recent nights, the heart-rate cycling '
                          'this screen counts has stayed inside the range of '
                          'the ${v.nightsUsed} nights behind it.'),
              style: F.body.copyWith(color: p.ink, height: 1.5),
            ),
            const SizedBox(height: S.x3),
            Text(
              l?.investigateCvhrExplainer ??
                  'It is a pattern in your pulse, not a measurement of your '
                      'breathing, and it is not a test for anything. The same '
                      'cycling comes from an irregular rhythm, from being at '
                      'altitude, and from any broken-up night — and '
                      'beta-blockers, diabetes and nerve conditions flatten '
                      'it, so genuinely disturbed breathing often leaves '
                      'nothing here at all.',
              style: F.cap.copyWith(color: p.ink2, height: 1.6),
            ),
            const SizedBox(height: S.x3),
            Text(
              l?.investigateCvhrNotNegativeResult ??
                  'So nothing here is a negative result and nothing here '
                      'clears anything, and none of it says anything about '
                      'any one night.',
              style: F.cap.copyWith(color: p.ink2, height: 1.6),
            ),
            const SizedBox(height: S.x3),
            Text(
              l?.investigateCvhrSeeClinicianIfSymptoms ??
                  'If you snore, wake unrefreshed, or someone has seen you '
                      'stop breathing in your sleep, a clinician can test '
                      'that properly.',
              style: F.cap.copyWith(color: p.ink2, height: 1.6),
            ),
          ]),
        ),
    ]);
  }
}
