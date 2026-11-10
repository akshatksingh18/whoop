import 'package:flutter/material.dart';
import 'theme.dart';

/// Quiet decoration, deliberately excluded from metric and accessibility data.
class CalmIllustration extends StatelessWidget {
  const CalmIllustration({
    super.key,
    this.sleep = false,
    this.color = C.recovery,
  });
  final bool sleep;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 72,
      height: 78,
      child: CustomPaint(painter: _Scene(sleep, P.of(context).on(color))),
    ),
  );
}

class _Scene extends CustomPainter {
  const _Scene(this.sleep, this.ink);
  final bool sleep;
  final Color ink;
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / 72, size.height / 78);
    final fill = Paint()..color = ink.withValues(alpha: .22);
    final stroke = Paint()
      ..color = ink.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    if (sleep) {
      final moon = Path()
        ..moveTo(46, 12)
        ..cubicTo(8, 10, 3, 66, 43, 66)
        ..quadraticBezierTo(62, 66, 67, 49)
        ..cubicTo(39, 56, 23, 28, 46, 12);
      c.drawPath(moon, fill);
      c.drawPath(moon, stroke);
      c.drawCircle(
        const Offset(59, 18),
        2,
        Paint()..color = ink.withValues(alpha: .5),
      );
    } else {
      final left = Path()
        ..moveTo(38, 55)
        ..cubicTo(13, 55, 9, 34, 17, 19)
        ..cubicTo(39, 20, 42, 39, 38, 55);
      final right = Path()
        ..moveTo(38, 64)
        ..cubicTo(39, 39, 52, 30, 65, 33)
        ..cubicTo(67, 51, 57, 61, 38, 64);
      c.drawPath(left, fill);
      c.drawPath(right, fill);
      c.drawPath(left, stroke);
      c.drawPath(right, stroke);
      c.drawPath(
        Path()
          ..moveTo(38, 72)
          ..quadraticBezierTo(42, 45, 26, 31),
        stroke,
      );
      c.drawPath(
        Path()
          ..moveTo(39, 64)
          ..quadraticBezierTo(47, 48, 57, 43),
        stroke,
      );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_Scene old) => old.sleep != sleep || old.ink != ink;
}
