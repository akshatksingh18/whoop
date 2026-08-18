// SCRATCH — deleted before commit. Renders widgets to /tmp so they can be
// looked at instead of reasoned about.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/platform/app_icon.dart';
import 'package:openstrap_edge/ui2/onboarding/splash.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/theme.dart';

final _shot = GlobalKey();

Future<void> _loadType() async {
  final files = Directory('assets/fonts/Manrope')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ttf'));
  for (final family in const ['Manrope', '.SF Pro Text']) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(f
          .readAsBytes()
          .then((b) => ByteData.sublistView(Uint8List.fromList(b))));
    }
    await loader.load();
  }
}

Future<void> _save(String name) async {
  final b = _shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await b.toImage(pixelRatio: 2);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File('/tmp/render_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

Widget _frame(Widget child, Brightness b, double scale) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        home: RepaintBoundary(key: _shot, child: child),
      ),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadType();
  });

  for (final b in Brightness.values) {
    testWidgets('splash ${b.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_frame(
          const BootSplash(ready: false, child: SizedBox.shrink()), b, 1));
      await tester.pump();
      final ctx = tester.element(find.text('OpenStrap'));
      // ignore: avoid_print
      print('DECORATION ${DefaultTextStyle.of(ctx).style.decoration}');
      await _save('splash_${b.name}');
    });
  }

  for (final entry in {'1x': 1.0, '3x': 3.1}.entries) {
    for (final b in Brightness.values) {
      testWidgets('icon row ${b.name} ${entry.key}', (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_frame(
            const MoreSettingsView(
                units: 'Metric',
                appearance: 'Dark',
                appIcon: AppIconChoice.colourful),
            b,
            entry.value));
        await tester.pumpAndSettle();
        // Image.asset decodes off the main loop; without runAsync + precache
        // the preview is a blank box in every widget test.
        await tester.runAsync(() async {
          final ctx = tester.element(find.text('Icon'));
          for (final c in AppIconChoice.values) {
            await precacheImage(AssetImage(c.asset), ctx);
          }
        });
        await tester.dragUntilVisible(
            find.text('Icon'), find.byType(ListView), const Offset(0, -80));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _save('iconrow_${b.name}_${entry.key}');
      });
    }
  }
}
