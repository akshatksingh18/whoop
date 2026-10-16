// Build 90: a segmented control that fits fills its track without squeezing
// any label ("3 months" once rendered as "3").
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/grammar.dart';
import 'package:openstrap_edge/ui2/theme.dart';

void main() {
  // The app's own font: the fit decision depends on real glyph widths.
  setUpAll(() async {
    for (final family in ['Manrope', '.SF Pro Text']) {
      final loader = FontLoader(family);
      for (final f in Directory('assets/fonts/Manrope')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ttf'))) {
        loader.addFont(
          f.readAsBytes().then((b) => ByteData.sublistView(Uint8List.fromList(b))),
        );
      }
      await loader.load();
    }
  });

  for (final scale in [1.0]) {
    testWidgets('every range label shows whole at ${scale}x', (t) async {
      t.view.physicalSize = const Size(390 * 3, 300 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 300),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: SubTabs(
                  const ['Today', '7 days', '30 days', '3 months'],
                  3,
                  (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      // At ordinary text the four fit, so all four are laid out as a row.
      expect(find.text('3 months'), findsOneWidget);
      for (final label in ['Today', '7 days', '30 days', '3 months']) {
        final p = t.renderObject<RenderParagraph>(find.text(label));
        expect(p.didExceedMaxLines, isFalse, reason: '$label was cut');
      }
      expect(t.takeException(), isNull);
    });
  }
}
