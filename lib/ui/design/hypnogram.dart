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

class _SteppedHypnogramPainter extends CustomPainter {
  final List<HypnoSeg> segments;
  _SteppedHypnogramPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;
    
    final rowH = size.height / 3;

    int stageToY(SleepStage s) {
      switch (s) {
        case SleepStage.awake:
          return 0;
        case SleepStage.rem:
          return 1;
        case SleepStage.light:
          return 2;
        case SleepStage.deep:
          return 3;
      }
    }

    // Draw subtle grid lines
    final gridPaint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = i * rowH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw the continuous stepped line
    double? lastY;
    double? lastX;

    for (final seg in segments) {
      final y = stageToY(seg.stage) * rowH;
      final x1 = seg.start * size.width;
      final x2 = seg.end * size.width;

      if (x2 <= x1) continue;

      // Draw vertical step if needed
      if (lastX != null && lastY != null && (lastY - y).abs() > 0.01) {
        final stepPaint = Paint()
          ..color = AppColors.inkMuted.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawLine(Offset(x1, lastY), Offset(x1, y), stepPaint);
      }

      // Draw horizontal segment colored by stage
      final linePaint = Paint()
        ..color = stageColor(seg.stage)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
        
      canvas.drawLine(Offset(x1, y), Offset(x2, y), linePaint);

      lastX = x2;
      lastY = y;
    }
  }

  @override
  bool shouldRepaint(covariant _SteppedHypnogramPainter old) => true;
}

/// A beautiful continuous stepped hypnogram.
class Hypnogram extends StatelessWidget {
  final List<HypnoSeg> segments;
  final double height;
  final bool labels;
  final String? startLabel;
  final String? endLabel;

  const Hypnogram(
    this.segments, {
    super.key,
    this.height = 120,
    this.labels = true,
    this.startLabel,
    this.endLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    final plot = SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _SteppedHypnogramPainter(segments),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (labels)
          Row(
            children: [
              SizedBox(
                width: 46,
                height: height,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Awake', style: AppText.captionMuted.copyWith(fontSize: 10)),
                    Text('REM', style: AppText.captionMuted.copyWith(fontSize: 10)),
                    Text('Light', style: AppText.captionMuted.copyWith(fontSize: 10)),
                    Text('Deep', style: AppText.captionMuted.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: plot,
              )),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: plot,
          ),
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

/// Separate progress bars for each stage, as requested.
class StageBars extends StatelessWidget {
  final int? awakeMin;
  final int? remMin;
  final int? lightMin;
  final int? deepMin;
  final bool legend;

  const StageBars({
    super.key,
    this.awakeMin,
    this.remMin,
    this.lightMin,
    this.deepMin,
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
        m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m' : '${m}m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.x2),
          _buildStageBar(entries[i].$1, entries[i].$2, total, hm),
        ],
      ],
    );
  }

  Widget _buildStageBar(SleepStage stage, int mins, int total, String Function(int) hm) {
    final pct = (mins * 100 / total).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              stageName(stage),
              style: AppText.body.copyWith(
                color: stageColor(stage),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$pct% (${hm(mins)})',
              style: AppText.captionMuted,
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                Expanded(
                  flex: pct.clamp(1, 100),
                  child: Container(color: stageColor(stage)),
                ),
                Expanded(
                  flex: (100 - pct).clamp(0, 100),
                  child: Container(color: AppColors.divider.withValues(alpha: 0.1)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
