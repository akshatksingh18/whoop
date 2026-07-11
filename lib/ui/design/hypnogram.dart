
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

class _GanttPainter extends CustomPainter {
  final List<HypnoSeg> segments;
  _GanttPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final rowH = size.height / 4;

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
      ..color = AppColors.divider.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = i * rowH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw the segments as progress bar blocks
    for (final seg in segments) {
      final yIdx = stageToY(seg.stage);
      final top = yIdx * rowH;
      final bottom = top + rowH;
      final left = seg.start * size.width;
      final right = seg.end * size.width;

      if (right <= left) continue;

      final paint = Paint()
        ..color = stageColor(seg.stage)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top + 2, right, bottom - 2),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GanttPainter old) => true;
}

/// A beautiful Gantt chart hypnogram showing each stage on separated colored progress bars.
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

    final plot = RepaintBoundary(
      child: SizedBox(
        height: height,
        child: CustomPaint(
          size: Size.infinite,
          painter: _GanttPainter(segments),
        ),
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
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Awake', style: AppText.captionMuted.copyWith(fontSize: 10)),
                    Text('REM', style: AppText.captionMuted.copyWith(fontSize: 10)),
                    Text('Light', style: AppText.captionMuted.copyWith(fontSize: 10)),
                    Text('Deep', style: AppText.captionMuted.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              Expanded(child: plot),
            ],
          )
        else
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

/// Separate progress bars for each stage, as requested.
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
    // A stage is INCLUDED whenever the caller passed a value at all — even an
    // explicit 0 — and OMITTED only when the caller never supplied it
    // (stays null). This matters: a genuinely-absent stage (e.g. no Deep
    // sleep detected) must render an honest labelled row saying so, never an
    // invisible gap (see sleep_detail_screen.dart's _stageBreakdown doc
    // comment) — but a caller that never tracks a given stage at all (e.g.
    // sleep_periods_screen.dart's per-period breakdown never passes
    // awakeMin) should still see that stage cleanly omitted, not a spurious
    // "none detected" row for something it never asked about.
    final mins = <SleepStage, int?>{
      SleepStage.awake: awakeMin,
      SleepStage.rem: remMin,
      SleepStage.light: lightMin,
      SleepStage.deep: deepMin,
    };
    if (mins.values.every((m) => m == null)) return const SizedBox.shrink();
    final total = mins.values.fold<int>(0, (a, m) => a + (m ?? 0));

    String hm(int m) =>
        m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m' : '${m}m';

    final stages = SleepStage.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < stages.length; i++)
          if (mins[stages[i]] != null) ...[
            if (i > 0) const SizedBox(height: Sp.x2),
            _buildStageBar(stages[i], mins[stages[i]]!, total, hm),
          ],
      ],
    );
  }

  Widget _buildStageBar(
    SleepStage stage,
    int mins,
    int total,
    String Function(int) hm,
  ) {
    final absent = mins <= 0;
    final pct = (!absent && total > 0) ? (mins * 100 / total).round() : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                stageName(stage),
                style: AppText.body.copyWith(
                  color: absent ? AppColors.inkMuted : stageColor(stage),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Sp.x2),
            Flexible(
              child: Text(
                absent
                    ? (stage == SleepStage.deep
                        ? 'none detected · low-confidence estimate'
                        : 'none detected')
                    : '$pct% (${hm(mins)})',
                style: AppText.captionMuted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: SizedBox(
            height: height,
            child: absent
                ? Container(color: AppColors.divider.withValues(alpha: 0.1))
                : Row(
                    children: [
                      Expanded(
                        flex: pct.clamp(1, 100),
                        child: Container(color: stageColor(stage)),
                      ),
                      Expanded(
                        flex: (100 - pct).clamp(0, 100),
                        child: Container(
                          color: AppColors.divider.withValues(alpha: 0.1),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
