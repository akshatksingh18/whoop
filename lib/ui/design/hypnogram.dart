import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import 'domains.dart';

/// Canonical stage order, top row → bottom row.
enum SleepStage { awake, rem, light, deep }

Color stageColor(SleepStage s) => switch (s) {
  SleepStage.awake => DomainAccent.stageAwake,
  SleepStage.rem => DomainAccent.stageRem,
  SleepStage.light => DomainAccent.stageLight,
  SleepStage.deep => DomainAccent.stageDeep,
};

String stageName(SleepStage s) => switch (s) {
  SleepStage.awake => 'Awake',
  SleepStage.rem => 'REM',
  SleepStage.light => 'Light',
  SleepStage.deep => 'Deep',
};

/// One hypnogram segment over normalized night time (0..1).
class HypnoSeg {
  final SleepStage stage;
  final double start;
  final double end;
  const HypnoSeg(this.stage, this.start, this.end);
}

/// Parse the repository's hypnogram points ([{t, stage}], stage strings like
/// 'awake'/'rem'/'light'/'deep'/'core'/'nrem') into normalized segments.
List<HypnoSeg> hypnoSegmentsFromPoints(List<dynamic> points) {
  SleepStage? parse(Object? s) => switch ('$s'.toLowerCase()) {
    'awake' || 'wake' => SleepStage.awake,
    'rem' => SleepStage.rem,
    'light' || 'core' || 'nrem' => SleepStage.light,
    'deep' => SleepStage.deep,
    _ => null,
  };
  final pts = <(num, SleepStage)>[];
  for (final p in points) {
    if (p is! Map) continue;
    final t = p['t'] as num?;
    final st = parse(p['stage']);
    if (t == null || st == null) continue;
    pts.add((t, st));
  }
  if (pts.length < 2) return const [];
  final t0 = pts.first.$1, t1 = pts.last.$1;
  final span = (t1 - t0).toDouble();
  if (span <= 0) return const [];
  final segs = <HypnoSeg>[];
  for (var i = 0; i + 1 < pts.length; i++) {
    segs.add(
      HypnoSeg(
        pts[i].$2,
        ((pts[i].$1 - t0) / span).toDouble(),
        ((pts[i + 1].$1 - t0) / span).toDouble(),
      ),
    );
  }
  return segs;
}

/// A beautiful stepped line chart hypnogram powered by fl_chart.
class Hypnogram extends StatelessWidget {
  final List<HypnoSeg> segments;
  final double height;
  final bool labels;
  final String? startLabel;
  final String? endLabel;

  const Hypnogram(
    this.segments, {
    super.key,
    this.height = 100,
    this.labels = true,
    this.startLabel,
    this.endLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    // Map stages to Y values (0 = Deep, 1 = Light, 2 = REM, 3 = Awake)
    double stageToY(SleepStage s) {
      switch (s) {
        case SleepStage.deep:
          return 0;
        case SleepStage.light:
          return 1;
        case SleepStage.rem:
          return 2;
        case SleepStage.awake:
          return 3;
      }
    }

    final spots = <FlSpot>[];
    for (final seg in segments) {
      spots.add(FlSpot(seg.start, stageToY(seg.stage)));
      spots.add(FlSpot(seg.end, stageToY(seg.stage)));
    }

    final plot = SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: 1,
          minY: 0,
          maxY: 3,
          lineTouchData: LineTouchData(enabled: false), // Disable touch for cleaner UI
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: AppColors.divider.withValues(alpha: 0.6),
                strokeWidth: 1,
                dashArray: [4, 4], // dotted grid lines
              );
            },
          ),
          titlesData: FlTitlesData(
            show: labels,
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: labels,
                interval: 1,
                reservedSize: 42,
                getTitlesWidget: (value, meta) {
                  String text;
                  switch (value.toInt()) {
                    case 0:
                      text = 'Deep';
                      break;
                    case 1:
                      text = 'Light';
                      break;
                    case 2:
                      text = 'REM';
                      break;
                    case 3:
                      text = 'Awake';
                      break;
                    default:
                      return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      text,
                      style: AppText.captionMuted.copyWith(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              isStepLineChart: true,
              color: AppColors.accent, // A singular uniform color or gradient can be applied here
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.accent.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        plot,
        if (startLabel != null || endLabel != null) ...[
          const SizedBox(height: Sp.x1),
          Padding(
            padding: EdgeInsets.only(left: labels ? 46 : 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(startLabel ?? '', style: AppText.captionMuted),
                Text(endLabel ?? '', style: AppText.captionMuted),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact stage distribution: one rounded stacked bar + a quiet legend.
/// Pass minutes per stage; nulls/zeros are skipped honestly.
class StageBars extends StatelessWidget {
  final int? awakeMin;
  final int? remMin;
  final int? lightMin;
  final int? deepMin;
  final double height;
  final bool legend;

  const StageBars({
    super.key,
    this.awakeMin,
    this.remMin,
    this.lightMin,
    this.deepMin,
    this.height = 10,
    this.legend = true,
  });

  @override
  Widget build(BuildContext context) {
    final entries = <(SleepStage, int)>[
      if ((awakeMin ?? 0) > 0) (SleepStage.awake, awakeMin!),
      if ((remMin ?? 0) > 0) (SleepStage.rem, remMin!),
      if ((lightMin ?? 0) > 0) (SleepStage.light, lightMin!),
      if ((deepMin ?? 0) > 0) (SleepStage.deep, deepMin!),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    final total = entries.fold<int>(0, (a, e) => a + e.$2);

    String hm(int m) =>
        m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}' : '${m}m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (var i = 0; i < entries.length; i++)
                  Expanded(
                    flex: (entries[i].$2 * 1000 / total).round().clamp(1, 1000000),
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i == entries.length - 1 ? 0 : 2,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: stageColor(entries[i].$1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (legend) ...[
          const SizedBox(height: Sp.x2),
          Wrap(
            spacing: Sp.x3,
            runSpacing: Sp.x1,
            children: [
              for (final (stage, min) in entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: stageColor(stage),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${stageName(stage)} ${hm(min)}',
                      style: AppText.captionMuted.copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
