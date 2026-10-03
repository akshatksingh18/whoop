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
          LocalRepository repo) async =>
      ana.cvhrPersonalDistribution(await nights(repo));

  /// The stored nights the screen reads, newest first.
  static Future<List<ana.CvhrNight>> nights(LocalRepository repo) async {
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
    return nights;
  }

  @override
  State<SleepBreathingScreen> createState() => _SleepBreathingScreenState();
}

class _SleepBreathingScreenState extends State<SleepBreathingScreen> {
  ana.Metric<ana.CvhrDistribution>? _m;
  List<ana.CvhrNight> _nights = const [];
  bool _loading = true;
  bool _more = false;

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
    SleepBreathingScreen.nights(repo).then((ns) {
      if (mounted) {
        setState(() => (
              _nights = ns,
              _m = ana.cvhrPersonalDistribution(ns),
              _loading = false,
            ));
      }
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
      else ...[
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Icon(v.aboveOwnUsual ? LucideIcons.trendingUp : LucideIcons.check,
                  size: 20,
                  color: p.on(v.aboveOwnUsual ? C.yellow : C.green)),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(
                    v.aboveOwnUsual ? 'Higher than your usual' : 'Within your usual range',
                    style: F.head.copyWith(color: p.ink)),
              ),
            ]),
            const SizedBox(height: S.x1),
            Text('Heart-rate cycling while asleep · ${v.nightsUsed} nights',
                style: F.cap.copyWith(color: p.ink3)),
            if (_nights.length >= 2) ...[
              const SizedBox(height: S.x4),
              Builder(builder: (c) {
                final series = [
                  for (final n in _nights.reversed) n.cvhrPerHour,
                ];
                final axis = AxisSpec.of(series, floor: 0, ticks: 2);
                return ChartFrame(
                  title: 'Each night',
                  unit: 'per hour',
                  height: 90,
                  yAxis: axis,
                  series: series,
                  xLabels: const ['Oldest', 'Last night'],
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: Bars(series, p.on(C.sleep),
                        highlight: series.length - 1, axis: axis),
                  ),
                );
              }),
            ],
            const SizedBox(height: S.x3),
            Text('A pattern in your pulse, not a breathing test.',
                style: F.cap.copyWith(color: p.ink2)),
          ]),
        ),
        const SizedBox(height: S.x4),
        Pressable(
          onTap: () => setState(() => _more = !_more),
          semanticLabel: 'What this means',
          child: Row(children: [
            Expanded(
                child: Text('What this means',
                    style: F.cap.copyWith(color: p.ink2))),
            Icon(_more ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 16, color: p.ink3),
          ]),
        ),
        if (_more) ...[
          const SizedBox(height: S.x2),
          Surface(
            elevation: 0,
            color: p.card2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final line in const [
                'It counts how often your heart rate swings up and down while '
                    'you sleep. Breathing pauses cause that, but so do an '
                    'irregular rhythm, altitude and a broken-up night.',
                'It cannot rule anything in or out, and one night means little '
                    'on its own.',
                'If you snore, wake unrefreshed, or someone has seen you stop '
                    'breathing in your sleep, a clinician can test that properly.',
              ]) ...[
                Text(line, style: F.cap.copyWith(color: p.ink2, height: 1.5)),
                const SizedBox(height: S.x2),
              ],
            ]),
          ),
        ],
      ],
    ]);
  }
}
