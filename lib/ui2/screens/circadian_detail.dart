// BODY CLOCK — the highest-value thing the pipeline already knew and nothing
// ever asked it for.
//
// Chronotype, social jetlag and the sleep-regularity index are computed every
// cross-day rollup and, until this screen, were read by nothing. The actogram
// is built here from the per-night sleep windows: one column per night, noon
// to noon, so a night reads as one continuous block instead of being cut in
// half at midnight.
//
// The non-parametric rhythm family (interdaily stability, intradaily
// variability, relative amplitude, L5/M10) and the cosinor fit exist in the
// analytics package and are not wired to anything. The screen does not carry a
// card apologising for them: a metric this app does not produce is absent, not
// explained. See docs/internal/UI_ROADMAP.md.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/local_repository.dart';
import '../../models/metric.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'metric_detail.dart';

/// How many nights the actogram draws. Each night costs one day-bundle decode,
/// so this is a real cost, not a display choice.
// ponytail: N bundle reads per open. If this ever feels slow, the fix is a
// `sleepWindows({days})` repo method that reads onset/offset without the
// payload, not a smaller number here.
const _nights = 42;

class CircadianData {
  /// Newest last. One entry per night: 24 hourly fractions from local noon, or
  /// null when that night has no window.
  final List<List<double>?> actogram;
  final List<String> labels;
  final Metric jetlag, regularity;

  /// Chronotype is a CLASS, not a number: its label plus the confidence the
  /// classifier stated. It used to be carried as `Metric(value: 1)` — a
  /// fabricated value whose only job was to make three dots appear.
  final Conf chronotypeConf;
  final String chronotypeLabel;
  final num? midFreeH, midWorkH, nFree, nWork;

  const CircadianData({
    this.actogram = const [],
    this.labels = const [],
    this.chronotypeConf = Conf.none,
    this.jetlag = Metric.empty,
    this.regularity = Metric.empty,
    this.chronotypeLabel = '',
    this.midFreeH,
    this.midWorkH,
    this.nFree,
    this.nWork,
  });

  static Future<CircadianData> load(LocalRepository repo) async {
    final cd = await repo.getInsights();
    final chrono = cd['chronotype'];
    final sjl = cd['social_jetlag'];
    final reg = cd['regularity'];
    final chronoV = envValue(chrono) ?? const {};
    final sjlV = envValue(sjl) ?? const {};
    final regV = envValue(reg) ?? const {};

    final days = await repo.availableDays(); // newest first
    final take = days.length <= _nights ? days : days.sublist(0, _nights);
    final cols = <List<double>?>[];
    final labels = <String>[];
    for (final day in take.reversed) {
      final n = await repo.getDaySleepV2(day);
      cols.add(_column(n['onset_ts'] as num?, n['wake_ts'] as num?));
      labels.add(day);
    }

    return CircadianData(
      actogram: cols,
      labels: labels,
      chronotypeConf: confOfEnv(chrono),
      chronotypeLabel: (chronoV['type_label'] ?? '').toString(),
      jetlag: envMetric(sjl, sjlV['abs_hours'] as num?),
      regularity: envMetric(reg, regV['sri'] as num?),
      midFreeH: sjlV['mid_sleep_free_h'] as num?,
      midWorkH: sjlV['mid_sleep_work_h'] as num?,
      nFree: sjlV['n_free'] as num?,
      nWork: sjlV['n_work'] as num?,
    );
  }

  /// One night as 24 hourly asleep-fractions on a noon-anchored axis.
  static List<double>? _column(num? onsetTs, num? wakeTs) {
    if (onsetTs == null || wakeTs == null || wakeTs <= onsetTs) return null;
    final onset = DateTime.fromMillisecondsSinceEpoch(onsetTs.round() * 1000);
    // Anchor at the noon BEFORE sleep onset, so a 23:40 start and a 01:10 start
    // land in the same column rather than a day apart.
    final anchor = onset.hour < 12
        ? DateTime(onset.year, onset.month, onset.day - 1, 12)
        : DateTime(onset.year, onset.month, onset.day, 12);
    final a = anchor.millisecondsSinceEpoch / 1000;
    final lo = (onsetTs - a) / 3600, hi = (wakeTs - a) / 3600;
    if (hi <= 0 || lo >= 24) return null;
    return [
      for (var h = 0; h < 24; h++)
        ((hi < h + 1 ? hi : h + 1) - (lo > h ? lo : h)).clamp(0.0, 1.0).toDouble(),
    ];
  }
}

/// Hours past midnight → a wall clock, in the app's one clock format.
String _hourClock(num? h) => h == null ? '' : clock(((h % 24) * 60).round());

class CircadianDetail extends StatefulWidget {
  final CircadianData? data;
  const CircadianDetail({super.key, this.data});

  @override
  State<CircadianDetail> createState() => _CircadianDetailState();
}

class _CircadianDetailState extends State<CircadianDetail> {
  CircadianData? _d;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _d = widget.data;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final d = await CircadianData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d ?? const CircadianData();
    final drawn = d.actogram.where((e) => e != null).length;

    return detailScaffold(c, 'Body clock', [
      if (_loading && _d == null) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else ...[
        if (drawn == 0)
          const StatusCard(
            'No nights to plot yet',
            'The actogram is one column per night of recorded sleep, and none '
                'have been scored.',
            fix: 'Wear the band overnight',
            icon: LucideIcons.calendarClock,
          )
        else
          Surface(
            child: ChartFrame(
              title: 'Sleep, night by night',
              // Hour of day is what the vertical axis IS. The old card replaced
              // the axis with a sentence describing it.
              unit: 'hour of day',
              height: 190,
              yAxis: AxisSpec(
                  min: 0,
                  max: 24,
                  ticks: 3,
                  // Rows run noon → noon, so 0 and 24 are both midday and 12 is
                  // midnight — read straight off the anchor the columns use.
                  format: (v) => clock(((12 + v) * 60).round())),
              xLabels: d.labels.isEmpty
                  ? const []
                  : [d.labels.first, d.labels.last],
              legend: const [('Asleep', C.indigo)],
              footnote: '$drawn night${drawn == 1 ? '' : 's'} drawn, one column '
                  'each. A darker block is more of that hour asleep; a blank '
                  'column is a night with no record.',
              child: CustomPaint(
                size: Size.infinite,
                painter: Actogram(d.actogram, C.indigo),
              ),
            ),
          ),

        Section('Your rhythm', _rhythm(c, p, d)),

        if (d.midFreeH != null && d.midWorkH != null && d.jetlag.value != null
            && d.jetlag.value! >= 1) ...[
          const SizedBox(height: S.x4),
          Builder(builder: (c) {
            // `abs_hours` is unsigned. The direction is the SIGN of free minus
            // work, and this card used to assert "later" from a magnitude.
            final later = d.midFreeH! >= d.midWorkH!;
            return InsightCard(
              'Your free-day clock runs ${_hm(d.jetlag.value!)} '
              '${later ? 'later' : 'earlier'}',
              'The gap between when you sleep on free days and on working days '
                  'is what makes the first working morning hard. It is measured '
                  'from ${(d.nFree ?? 0).round()} free nights and '
                  '${(d.nWork ?? 0).round()} working nights.',
              icon: LucideIcons.clock,
              color: C.indigo,
            );
          }),
        ],
      ],
    ]);
  }

  String _hm(num hours) {
    final m = (hours * 60).round();
    return m < 60 ? '${m}m' : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  Widget _rhythm(BuildContext c, P p, CircadianData d) {
    // Mid-sleep free and mid-sleep work are FIELDS OF the social-jetlag
    // envelope, so they carry its confidence — that is the same envelope, not
    // a borrowed one.
    final sjl = ConfX.of(d.jetlag);
    final rows = <(String, String, Conf)>[
      if (d.chronotypeLabel.isNotEmpty)
        ('Chronotype', d.chronotypeLabel, d.chronotypeConf),
      if (d.midFreeH != null)
        ('Mid-sleep, free days', _hourClock(d.midFreeH), sjl),
      if (d.midWorkH != null)
        ('Mid-sleep, working days', _hourClock(d.midWorkH), sjl),
      if (d.jetlag.value != null)
        ('Social jetlag', _hm(d.jetlag.value!), sjl),
      if (d.regularity.value != null)
        ('Regularity index', '${d.regularity.value!.round()} / 100',
            ConfX.of(d.regularity)),
    ];

    if (rows.isEmpty) {
      return StatusCard.forMetric('Your rhythm is not established yet',
              d.regularity,
              why: 'Chronotype and social jetlag are measured by comparing free '
                  'nights against working nights, which takes a few weeks of '
                  'both.') ??
          const SizedBox.shrink();
    }

    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(children: [
              Expanded(
                  child:
                      Text(rows[i].$1, style: F.body.copyWith(color: p.ink))),
              Text(rows[i].$2,
                  style: F.body
                      .copyWith(color: p.ink2, fontWeight: FontWeight.w600)),
              const SizedBox(width: S.x3),
              ConfDots(rows[i].$3),
            ]),
          ),
        ],
      ]),
    );
  }
}
