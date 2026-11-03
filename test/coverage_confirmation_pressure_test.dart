// Shared confirmation controls with real caller copy and synthetic counts.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart';

void main() {
  setUpAll(loadAuditFonts);
  const cases = [
    (
      'Finish this workout?',
      'It is saved now and cannot be resumed.',
      'Finish',
      'Keep going',
    ),
    (
      'Delete this running?',
      'It is removed from this phone, with its route and sets. This cannot be undone.',
      'Remove',
      'Keep it',
    ),
    (
      'Discard changes?',
      'What you changed here has not been saved.',
      'Discard',
      'Keep editing',
    ),
    (
      'Link 12 to your WHOOP workouts?',
      '12 imported workouts overlap lifts you recorded with the band. Linking puts the sets on that session; its strain and calories stay as measured. The rest are kept as history only.',
      'Link them',
      'Keep separate',
    ),
  ];
  for (final data in cases) {
    for (final scale in [1.0, 2.0, 3.1]) {
      for (final confirm in [true, false]) {
        testWidgets(
          '${data.$1} at ${scale}x returns ${confirm ? 'confirm' : 'keep'} after the full message',
          (t) async {
            bool? result;
            t.view.physicalSize = const Size(390, 844);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            await t.pumpWidget(
              RepaintBoundary(
                key: auditCaptureKey,
                child: MaterialApp(
                  theme: buildTheme(Brightness.light),
                  builder: (c, w) => MediaQuery(
                    data: MediaQuery.of(
                      c,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: w!,
                  ),
                  home: Builder(
                    builder: (c) => Scaffold(
                      body: TextButton(
                        onPressed: () async {
                          result = await confirmRemove(
                            c,
                            title: data.$1,
                            body: data.$2,
                            remove: data.$3,
                            keep: data.$4,
                          );
                        },
                        child: const Text('Open confirmation'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await t.tap(find.text('Open confirmation'));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            expect(find.text(data.$2), findsOneWidget);
            final paragraph = t.renderObject<RenderParagraph>(
              find.text(data.$2),
            );
            final tail = paragraph
                .getBoxesForSelection(
                  TextSelection(
                    baseOffset: data.$2.length - 3,
                    extentOffset: data.$2.length,
                  ),
                )
                .last;
            expect(tail.bottom, lessThanOrEqualTo(paragraph.size.height + .5));
            paragraph.showOnScreen(rect: tail.toRect());
            await t.pumpAndSettle();
            expect(
              paragraph.localToGlobal(Offset(tail.right, tail.bottom)).dy,
              lessThanOrEqualTo(844.5),
              reason: 'the message end must be reachable',
            );
            if (confirm)
              await captureAuditScroll(
                t,
                'confirmation_${cases.indexOf(data)}_$scale',
                prefix: 'coverage102',
                scrollable: find
                    .descendant(
                      of: find.byType(SingleChildScrollView),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
            final button = find.text(confirm ? data.$3 : data.$4);
            await t.ensureVisible(button);
            await t.pumpAndSettle();
            await t.tap(button);
            await t.pumpAndSettle();
            expect(result, confirm);
            expect(find.text(data.$1), findsNothing);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
          },
        );
      }
    }
  }
}
