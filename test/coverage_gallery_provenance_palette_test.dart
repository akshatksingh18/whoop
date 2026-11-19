// Exercise the actual Gallery version marker during a palette change.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/profile/gallery.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'support/audit_visual.dart' show loadAuditFonts;

class MarkerCanvas implements Canvas {
  final lines = <(Offset, Offset, Color)>[];

  @override
  void drawLine(Offset start, Offset end, Paint paint) {
    lines.add((start, end, paint.color));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadAuditFonts);

  testWidgets(
    'the Gallery provenance mark preserves its position when the palette changes',
    (t) async {
      final fixture = goldenCases()['chart_line_algo_break']!;
      Future<void> draw(Brightness brightness) async {
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(brightness),
            home: Scaffold(
              body: Center(child: SizedBox(width: 380, child: fixture)),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      final frame = find.byType(ChartFrame);
      final marker = find.descendant(
        of: frame,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is IgnorePointer &&
              widget.child is CustomPaint &&
              (widget.child! as CustomPaint).painter != null,
        ),
      );
      CustomPaint overlay() =>
          t.widget<IgnorePointer>(marker).child! as CustomPaint;
      MarkerCanvas capture(CustomPaint paint) {
        final element = t.element(find.byWidget(paint));
        expect(
          element.findAncestorWidgetOfExactType<IgnorePointer>()?.ignoring,
          isTrue,
        );
        final recording = MarkerCanvas();
        paint.painter!.paint(recording, t.getSize(find.byWidget(paint)));
        return recording;
      }

      await draw(Brightness.light);
      final light = overlay();
      final before = capture(light).lines;
      final size = t.getSize(find.byWidget(light));
      expect(before, isNotEmpty);
      expect(before.every((line) => line.$1.dx == before.first.$1.dx), isTrue);
      expect(before.first.$1.dx, closeTo(size.width * .55, 1e-8));
      expect(before.last.$2.dy, lessThanOrEqualTo(size.height));
      expect(
        find.textContaining('The dotted line is a change'),
        findsOneWidget,
      );

      await draw(Brightness.dark);
      final dark = overlay();
      final after = capture(dark).lines;
      expect(dark.painter!.shouldRepaint(light.painter!), isTrue);
      expect(
        after.map((line) => (line.$1, line.$2)),
        before.map((line) => (line.$1, line.$2)),
      );
      expect(after.first.$3, isNot(before.first.$3));
      expect(
        find.textContaining('The dotted line is a change'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
}
