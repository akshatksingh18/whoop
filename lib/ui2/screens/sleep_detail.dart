// SLEEP — glance, explore and investigate on one screen.
//
// There is no sleep score. The old design put an 85 in a ring and then had to
// invent "Why 85?" underneath it; no composite exists in the pipeline, and
// inventing one here would mean choosing weights in a UI file. The ring holds
// sleep efficiency, which is a measured ratio, and the rows underneath are the
// real numbers rather than a decomposition of a number that never existed.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/local_repository.dart';
import '../../models/metric.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'investigate.dart';
import 'metric_detail.dart';

SleepStage _stageOf(Object? raw) => switch (raw?.toString()) {
      'wake' || 'awake' => SleepStage.awake,
      'rem' => SleepStage.rem,
      'deep' => SleepStage.deep,
      _ => SleepStage.light,
    };

/// Two call sites drew this byte-identical card; one const so they cannot
/// drift apart.
const _noOvernightLines = StatusCard(
  'No overnight signal lines',
  'No overnight recordings reached this day.',
  icon: LucideIcons.activity,
);

class SleepData {
  final String? day;
  final Map<String, dynamic> night;
  final Map<String, dynamic> timeline;
  final Metric need, debt, bedtime, wake, regularity;
  final num? napCreditMin, strainBonusMin;

  const SleepData({
    this.day,
    this.night = const {},
    this.timeline = const {},
    this.need = Metric.empty,
    this.debt = Metric.empty,
    this.bedtime = Metric.empty,
    this.wake = Metric.empty,
    this.regularity = Metric.empty,
    this.napCreditMin,
    this.strainBonusMin,
  });

  bool get hasNight => night['duration_min'] is num;

  /// Stage samples for the painter — the segment list resampled onto a fixed
  /// number of columns so a four-hour segment and a four-minute one stay in
  /// proportion.
  List<SleepStage> get stages {
    final pts = night['hypnogram'];
    if (pts is! List || pts.length < 2) return const [];
    final ts = <int>[], st = <SleepStage>[];
    for (final e in pts) {
      if (e is Map && e['t'] is num) {
        ts.add((e['t'] as num).round());
        st.add(_stageOf(e['stage']));
      }
    }
    if (ts.length < 2) return const [];
    final t0 = ts.first, t1 = ts.last;
    if (t1 <= t0) return const [];
    const cols = 240;
    return [
      for (var i = 0; i < cols; i++)
        st[_indexAt(ts, t0 + ((t1 - t0) * i / cols).round())],
    ];
  }

  static int _indexAt(List<int> ts, int t) {
    var lo = 0;
    for (var i = 0; i < ts.length; i++) {
      if (ts[i] <= t) lo = i;
    }
    return lo;
  }

  static Future<SleepData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    var day = (today['status'] as Map?)?['today_day']?.toString();
    final days = await repo.availableDays();
    if (days.isNotEmpty && (day == null || !days.contains(day))) day = days.first;
    if (day == null) return const SleepData();

    final night = await repo.getDaySleepV2(day);
    final timeline = await repo.getDayTimeline(day);
    final cd = await repo.getInsights();
    final coach = cd['sleep_coach'];
    final needEnv = coach is Map ? coach['need'] : null;
    final needSec = envValue(needEnv)?['need_sec'] as num?;
    final debtEnv = cd['sleep_debt'];
    final debtH = envValue(debtEnv)?['debt_hours'] as num?;
    final bedEnv = coach is Map ? coach['bedtime'] : null;
    final wakeEnv = coach is Map ? coach['wake'] : null;
    final regEnv = cd['regularity'];

    return SleepData(
      day: day,
      night: night,
      timeline: timeline,
      need: envMetric(needEnv, needSec == null ? null : needSec / 60, unit: 'min'),
      debt: envMetric(debtEnv, debtH == null ? null : debtH * 60, unit: 'min'),
      bedtime:
          envMetric(bedEnv, envValue(bedEnv)?['bedtime_min_of_day'] as num?),
      wake: envMetric(wakeEnv, envValue(wakeEnv)?['wake_min_of_day'] as num?),
      regularity: envMetric(regEnv, envValue(regEnv)?['sri'] as num?),
      napCreditMin: coach is Map ? coach['nap_credit_min'] as num? : null,
      strainBonusMin: coach is Map ? coach['strain_bonus_min'] as num? : null,
    );
  }
}

class SleepDetail extends StatefulWidget {
  final SleepData? data;
  const SleepDetail({super.key, this.data});

  @override
  State<SleepDetail> createState() => _SleepDetailState();
}

class _SleepDetailState extends State<SleepDetail> {
  SleepData? _d;
  bool _loading = true;
  double? _scrub; // 0..1 across the night

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
      final d = await SleepData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d ?? const SleepData();

    if (_loading && _d == null) {
      return detailScaffold(c, 'Sleep', const [
        SizedBox(height: S.x8),
        Center(child: CircularProgressIndicator()),
      ]);
    }

    if (!d.hasNight) {
      return detailScaffold(c, 'Sleep', [
        const SizedBox(height: S.x2),
        const StatusCard(
          'No night to show',
          'No stretch of band recordings long enough to score.',
          fix: 'Wear the band overnight and sync in the morning',
          icon: LucideIcons.moon,
        ),
      ]);
    }

    final n = d.night;
    final tst = n['duration_min'] as num?;
    final eff = (n['efficiency'] as num?); // 0..1
    final stages = d.stages;

    return detailScaffold(c, 'Sleep', sub: (d.day ?? '').toUpperCase(), [
      // ── GLANCE ──
      Surface(
        child: Column(children: [
          Row(children: [
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hm(tst), style: F.n48.copyWith(color: p.ink)),
                const SizedBox(height: S.x1),
                Text('Total sleep', style: F.cap.copyWith(color: p.ink3)),
              ]),
            ),
            const SizedBox(width: S.x3),
            if (eff != null)
              SizedBox(
                width: 66,
                height: 66,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(
                    size: const Size(66, 66),
                    painter: Ring(eff.clamp(0, 1).toDouble(), p.on(C.green), p.track,
                        stroke: 7, t: animate(c, 1)),
                  ),
                  // The ring is a fixed 66 pt; at 2x text the label inside it
                  // has to shrink rather than push the ring out of shape.
                  FittedBox(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${(eff * 100).round()}%',
                          style: F.n17.copyWith(color: p.ink)),
                      Text('EFF', style: F.over.copyWith(color: p.ink3)),
                    ]),
                  ),
                ]),
              ),
          ]),
          const SizedBox(height: S.x5),
          if (stages.isEmpty)
            const StatusCard(
              'No hypnogram for this night',
              'Staging needs movement and beat timing. One was missing.',
              icon: LucideIcons.chartNoAxesColumn,
            )
          else
            ChartFrame(
              title: 'Hypnogram',
              unit: 'stage',
              height: 110,
              xLabels: [
                clockOfTs(n['onset_ts'] as num?),
                clockOfTs(n['wake_ts'] as num?),
              ],
              // Driven by the night, not by the enum: a night with no REM in
              // it used to still print REM in its key.
              legend: [
                for (final e in Hypnogram.legend(p))
                  if (stages.any((s) => s.label == e.$1)) e,
              ],
              child: _hypnogram(c, p, stages, n),
            ),
        ]),
      ),

      if (_scrub != null) _scrubCard(c, p, d),

      Section('Stages', _stages(c, p, n, tst)),

      const SizedBox(height: S.x4),
      StatusCard(
        'Stages are a low-confidence estimate',
        'Total sleep and timing are reliable. The light, deep and REM split is '
        'an overlay, and deep is the weakest of the three.',
        fix: 'How this is computed',
        icon: LucideIcons.moon,
        // A staging caveat used to open the HRV workbench.
        onFix: () => go(c, const Investigate('sleep')),
      ),

      Section('How the night went', _quality(c, p, d, n)),

      if ((n['cycle_count'] as num?) != null && (n['cycle_count'] as num) > 0)
        Section('Cycles', _cycles(c, p, n)),

      Section('Overnight signals', _overnight(c, p, d)),

      Section('Tonight', _tonight(c, p, d)),

      const SizedBox(height: S.x5),
      investigateRow(c, () => go(c, const Investigate('sleep'))),
    ]);
  }

  /// A [Scrubber], not a drag gesture: what matters is where the pointer IS,
  /// and the 44 pt tap rule does not apply to a continuous readout. What DOES
  /// apply is that the readout has to exist without a pointer — [Scrubber]
  /// carries the slider role and speaks [describe] at each step.
  Widget _hypnogram(
          BuildContext c, P p, List<SleepStage> stages, Map<String, dynamic> n) =>
      Scrubber(
        value: _scrub,
        onChanged: (v) => setState(() => _scrub = v),
        label: 'Hypnogram',
        describe: (v) {
          final t0 = (n['onset_ts'] as num?)?.toInt();
          final t1 = (n['wake_ts'] as num?)?.toInt();
          final st = stages.isEmpty
              ? null
              : stages[(v * (stages.length - 1)).round().clamp(0, stages.length - 1)];
          final at = (t0 == null || t1 == null || t1 <= t0)
              ? '${(v * 100).round()}% through the night'
              : clockOfTs(t0 + ((t1 - t0) * v).round());
          return st == null ? at : '$at, ${_stageName(st)}';
        },
        child: SizedBox(
          height: 110,
          child: Stack(children: [
            CustomPaint(
                size: Size.infinite,
                painter: Hypnogram(stages, p, t: animate(c, 1))),
            if (_scrub != null)
              // Aligned by fraction rather than by a measured offset, so the
              // cursor needs no width from the layout.
              Align(
                alignment: Alignment(_scrub! * 2 - 1, 0),
                child: SizedBox(width: 2, height: double.infinity,
                    child: ColoredBox(color: p.ink)),
              ),
          ]),
        ),
      );

  /// What every signal read at the scrubbed instant. Each line abstains on its
  /// own — a night with no respiration series still shows heart rate.
  Widget _scrubCard(BuildContext c, P p, SleepData d) {
    final n = d.night;
    final t0 = (n['onset_ts'] as num?)?.toInt();
    final t1 = (n['wake_ts'] as num?)?.toInt();
    if (t0 == null || t1 == null || t1 <= t0) return const SizedBox.shrink();
    final t = t0 + ((t1 - t0) * _scrub!).round();

    num? at(String key) {
      final list = d.timeline[key];
      if (list is! List) return null;
      num? best;
      var bestGap = 1 << 30;
      for (final e in list) {
        if (e is Map && e['t'] is num && e['v'] is num) {
          final gap = ((e['t'] as num).round() - t).abs();
          if (gap < bestGap) {
            bestGap = gap;
            best = e['v'] as num;
          }
        }
      }
      return bestGap > 900 ? null : best;
    }

    final stages = d.stages;
    final stage = stages.isEmpty
        ? null
        : stages[(_scrub! * (stages.length - 1)).round()];
    final items = <(String, String, Color)>[
      if (at('hr') != null) ('Heart rate', '${at('hr')!.round()} bpm', C.red),
      if (at('hrv') != null) ('HRV', '${at('hrv')!.round()} ms', C.green),
      if (at('resp') != null)
        ('Breathing', '${at('resp')!.toStringAsFixed(1)} br/min', C.teal),
      if (at('skin_temp') != null)
        ('Temp', at('skin_temp')!.toStringAsFixed(2), C.orange),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: Surface(
        color: p.card2,
        elevation: 0,
        child: Column(children: [
          Row(children: [
            Text(clockOfTs(t),
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (stage != null)
              Pill(_stageName(stage), Hypnogram.pigment[stage] ?? C.blue),
          ]),
          if (items.isEmpty) ...[
            const SizedBox(height: S.x3),
            Text('No signal recorded at this moment.',
                style: F.cap.copyWith(color: p.ink3)),
          ] else ...[
            const SizedBox(height: S.x4),
            InlineMetrics(items),
          ],
        ]),
      ),
    );
  }

  String _stageName(SleepStage s) => switch (s) {
        SleepStage.awake => 'Awake',
        SleepStage.rem => 'REM',
        SleepStage.light => 'Light sleep',
        SleepStage.deep => 'Deep sleep',
      };

  Widget _stages(BuildContext c, P p, Map<String, dynamic> n, num? tst) {
    final rows = <(String, num?, Color)>[
      ('Deep', n['deep_min'] as num?, C.blue),
      ('REM', n['rem_min'] as num?, C.teal),
      ('Light', n['light_min'] as num?, C.sky),
      ('Awake', n['awake_min'] as num?, C.orange),
    ];
    final present = [for (final r in rows) if (r.$2 != null) r];
    if (present.isEmpty) {
      return const StatusCard(
        'No stage split for this night',
        'No beat timing across the whole window.',
        icon: LucideIcons.chartNoAxesColumn,
      );
    }
    final total = tst ?? present.fold<num>(0, (a, r) => a + r.$2!);
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(children: [
        for (var i = 0; i < present.length; i++) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: present[i].$3, shape: BoxShape.circle)),
              const SizedBox(width: S.x3),
              Expanded(
                  child: Text(present[i].$1,
                      style: F.body.copyWith(color: p.ink))),
              Text(hm(present[i].$2),
                  style: F.cap
                      .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              const SizedBox(width: S.x3),
              SizedBox(
                width: 40,
                child: Text(
                  total == 0
                      ? ''
                      : '${((present[i].$2! / total) * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _quality(
      BuildContext c, P p, SleepData d, Map<String, dynamic> n) {
    final eff = n['efficiency'] as num?;
    final waso = n['awake_min'] as num?;
    final inBed = n['in_bed_min'] as num?;
    final adv = n['advanced'];
    final advV = adv is Map
        ? (adv['value'] is Map
            ? (adv['value'] as Map).cast<String, dynamic>()
            : adv.cast<String, dynamic>())
        : const <String, dynamic>{};
    final solSec = advV['sol_s'] as num?;
    final sri = d.regularity.value;
    final bed = d.bedtime.value;
    final onset = n['onset_ts'] as num?;

    final rows = <Widget>[
      if (eff != null)
        ProgressCard('Efficiency', '${(eff * 100).round()}%',
            'of ${hm(inBed)} in bed', eff.clamp(0, 1).toDouble(), C.green),
      if (solSec != null)
        ProgressCard('Time to fall asleep', hm(solSec / 60), '',
            (1 - (solSec / 3600)).clamp(0, 1).toDouble(), C.blue),
      if (waso != null)
        ProgressCard('Awake in the night', hm(waso), '',
            (1 - (waso / 120)).clamp(0, 1).toDouble(), C.orange),
      if (sri != null)
        ProgressCard('Regularity', '${sri.round()} / 100',
            'same hours, night to night', (sri / 100).clamp(0, 1).toDouble(),
            C.indigo),
      if (bed != null && onset != null)
        ProgressCard(
            'Timing',
            _vsTarget(bed, onset),
            'target ${clock(bed)}',
            // Was a literal .5 — a bar that was always exactly half full and
            // meant nothing. Full when you fell asleep on target, empty at an
            // hour out either way. The hour is a display normaliser, like the
            // one on WASO above it; the number beside the bar is the real one.
            (1 - _offTargetMin(bed, onset) / 60).clamp(0, 1).toDouble(),
            C.indigo),
    ];

    if (rows.isEmpty) {
      return StatusCard.forMetric('Nothing to judge the night by yet',
              d.regularity,
              why: 'None of their inputs were available.') ??
          const SizedBox.shrink();
    }

    return Surface(
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: S.x4),
          rows[i],
        ],
      ]),
    );
  }

  /// Signed minutes between the target bedtime and when sleep actually began,
  /// wrapped across midnight.
  num _diffMin(num bedMinOfDay, num onsetTs) {
    final d = DateTime.fromMillisecondsSinceEpoch(onsetTs.round() * 1000);
    var diff = (d.hour * 60 + d.minute) - bedMinOfDay;
    if (diff > 720) diff -= 1440;
    if (diff < -720) diff += 1440;
    return diff;
  }

  num _offTargetMin(num bedMinOfDay, num onsetTs) =>
      _diffMin(bedMinOfDay, onsetTs).abs();

  String _vsTarget(num bedMinOfDay, num onsetTs) {
    final diff = _diffMin(bedMinOfDay, onsetTs);
    if (diff.abs() < 10) return 'on target';
    return '${hm(diff.abs())} ${diff > 0 ? 'late' : 'early'}';
  }

  Widget _cycles(BuildContext c, P p, Map<String, dynamic> n) {
    final count = (n['cycle_count'] as num?)?.toInt() ?? 0;
    final mean = n['cycles_mean_min'] as num?;
    return Surface(
      child: Column(children: [
        InlineMetrics([
          ('CYCLES', '$count', C.indigo),
          if (mean != null) ('MEAN LENGTH', hm(mean), C.blue),
        ]),
        const SizedBox(height: S.x3),
        Text(
            'Cycles are found as peaks and troughs in the smoothed beat-timing '
            'variability across the night, not from staging.',
            style: F.over.copyWith(color: p.ink3, height: 1.5)),
      ]),
    );
  }

  Widget _overnight(BuildContext c, P p, SleepData d) {
    /// One lane as `(timestamp, value)`. The timestamp is the point — the
    /// three signals arrive on three different cadences.
    List<(int, double)> stamped(String key) {
      final l = d.timeline[key];
      if (l is! List) return const [];
      return [
        for (final e in l)
          if (e is Map && e['v'] is num && e['t'] is num)
            ((e['t'] as num).round(), (e['v'] as num).toDouble()),
      ];
    }

    final n = d.night;
    final hr = stamped('hr'), hrv = stamped('hrv'), resp = stamped('resp');
    final all = [...hr, ...hrv, ...resp];

    if (all.isEmpty) {
      return _noOvernightLines;
    }

    // ONE grid for all three lanes. `NightStack` reads index as instant, so
    // lanes of different lengths spread across the same width put three
    // different times under one vertical slice — which is the entire premise
    // of a stacked night view. The window is the night the axis labels name,
    // and the column count is the densest lane, capped: past ~a column per
    // pixel the extra buckets only add holes.
    var t0 = (n['onset_ts'] as num?)?.round() ??
        all.map((e) => e.$1).reduce((a, b) => a < b ? a : b);
    var t1 = (n['wake_ts'] as num?)?.round() ??
        all.map((e) => e.$1).reduce((a, b) => a > b ? a : b);
    if (t1 <= t0) {
      t0 = all.map((e) => e.$1).reduce((a, b) => a < b ? a : b);
      t1 = all.map((e) => e.$1).reduce((a, b) => a > b ? a : b);
    }
    final cols = t1 <= t0
        ? 0
        : [hr.length, hrv.length, resp.length]
            .reduce((a, b) => a > b ? a : b)
            .clamp(2, 480);

    /// Bucket mean per column; null where the lane has nothing in that
    /// bucket. A null is a HOLE — the painter breaks the line rather than
    /// drawing across a gap the data never covered.
    List<double?> grid(List<(int, double)> v) {
      final sum = List<double>.filled(cols, 0), cnt = List<int>.filled(cols, 0);
      for (final (t, x) in v) {
        if (t < t0 || t > t1) continue;
        final i = (((t - t0) / (t1 - t0)) * (cols - 1)).round().clamp(0, cols - 1);
        sum[i] += x;
        cnt[i]++;
      }
      return [
        for (var i = 0; i < cols; i++)
          cnt[i] == 0 ? null : sum[i] / cnt[i],
      ];
    }

    final series = <List<double?>>[], colors = <Color>[];
    final legend = <(String, Color)>[];
    final axes = <AxisSpec?>[];
    final units = <String>[];

    // Each lane keeps its own scale — they are different quantities — but the
    // scale is PINNED to the night's own range and its unit is named. Three
    // unlabelled lines on three invisible axes was the least readable chart
    // in the app.
    void lane(List<(int, double)> raw, String label, String unit, Color col) {
      if (raw.isEmpty || cols == 0) return;
      final g = grid(raw);
      final present = <double>[for (final v in g) ?v];
      if (present.length < 2) return;
      series.add(g);
      colors.add(col);
      legend.add(('$label ($unit)', col));
      axes.add(AxisSpec.of(present, ticks: 2));
      units.add(unit);
    }

    // Solved against the card, like every other mark: raw pigment measures
    // 1.7-2.5:1 on white and a lane's colour is what tells you which signal
    // you are looking at.
    lane(hr, 'Heart rate', 'bpm', p.on(C.red));
    lane(hrv, 'HRV', 'ms', p.on(C.green));
    lane(resp, 'Breathing', 'br/min', p.on(C.teal));

    if (series.isEmpty) {
      return _noOvernightLines;
    }
    return Surface(
      child: ChartFrame(
        title: 'Through the night',
        unit: units.join(' · '),
        height: 44.0 * series.length + 20,
        xLabels: [
          clockOfTs(n['onset_ts'] as num?),
          clockOfTs(n['wake_ts'] as num?),
        ],
        legend: legend,
        footnote: 'One lane per signal on one shared clock, each on its own '
            'scale — they are different quantities and a shared axis would be '
            'a lie. A break is a stretch the signal did not cover.',
        child: CustomPaint(
            size: Size.infinite,
            painter: NightStack(series, colors, axes: axes)),
      ),
    );
  }

  Widget _tonight(BuildContext c, P p, SleepData d) {
    final need = d.need.value;
    if (need == null) {
      return StatusCard.forMetric('Sleep need not established', d.need,
              why: 'Learned from your own nights. Eight hours is a slogan, not '
                   'your need.') ??
          const SizedBox.shrink();
    }
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(hm(need), style: F.n34.copyWith(color: p.ink)),
              const SizedBox(width: S.x2),
              Text('needed tonight', style: F.cap.copyWith(color: p.ink3)),
            ]),
        const SizedBox(height: S.x4),
        InlineMetrics([
          if (d.debt.value != null) ('DEBT', hm(d.debt.value), C.orange),
          // Null here means "we do not know", never zero — so the row is absent
          // rather than showing +0m.
          if (d.strainBonusMin != null)
            ('STRAIN BONUS', '+${hm(d.strainBonusMin)}', C.purple),
          if (d.napCreditMin != null)
            ('NAP CREDIT', '−${hm(d.napCreditMin)}', C.teal),
          if (d.bedtime.value != null) ('BED', clock(d.bedtime.value), C.indigo),
          if (d.wake.value != null) ('WAKE', clock(d.wake.value), C.blue),
        ]),
      ]),
    );
  }
}
