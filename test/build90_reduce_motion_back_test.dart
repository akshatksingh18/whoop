// B90-03: with Reduce Motion on, iOS edge-back must still return. The motion
// gate used to return the bare page, which also dropped the platform's back
// gesture; it now keeps the builder and snaps its animations.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Widget _app({required bool reduceMotion}) => MaterialApp(
  theme: buildTheme(Brightness.light),
  builder: (c, w) => MediaQuery(
    data: MediaQuery.of(c).copyWith(disableAnimations: reduceMotion),
    child: w!,
  ),
  home: Builder(
    builder: (c) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Center(child: Text('Detail'))),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

Future<void> _edgeSwipe(WidgetTester t) async {
  final g = await t.startGesture(const Offset(4, 300));
  for (var i = 0; i < 10; i++) {
    await g.moveBy(const Offset(40, 0));
    await t.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await t.pumpAndSettle();
}

void main() {
  for (final reduce in [false, true]) {
    testWidgets('iOS edge-back returns with Reduce Motion ${reduce ? 'on' : 'off'}', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await t.pumpWidget(_app(reduceMotion: reduce));
        await t.tap(find.text('Open'));
        await t.pumpAndSettle();
        expect(find.text('Detail'), findsOneWidget);
        await _edgeSwipe(t);
        expect(find.text('Detail'), findsNothing);
        expect(find.text('Open'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('with Reduce Motion a push lands without sliding', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await t.pumpWidget(_app(reduceMotion: true));
      await t.tap(find.text('Open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      // One frame in, the page is already in place: no slide from the edge.
      expect(t.getTopLeft(find.text('Detail')).dx, lessThan(400));
      await t.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
