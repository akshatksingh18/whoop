// Synthetic Flutter captures only. Manrope substitutes for native SF on CI.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const auditCaptureKey = ValueKey('audit-capture');

Future<void> loadAuditFonts() async {
  for (final family in ['Manrope', '.SF Pro Text']) {
    final loader = FontLoader(family);
    for (final file in Directory(
      'assets/fonts/Manrope',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
      loader.addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
    }
    await loader.load();
  }
  final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
    ..addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
  await icons.load();
}

Future<void> captureAuditScroll(
  WidgetTester t,
  String name, {
  String prefix = 'build99',
}) async {
  if (!const bool.fromEnvironment('UI_CAPTURE')) return;
  final pos = t.state<ScrollableState>(find.byType(Scrollable).last).position;
  pos.jumpTo(0);
  await t.pumpAndSettle();
  for (var page = 0; page < 60; page++) {
    expect(t.takeException(), isNull);
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(auditCaptureKey),
    );
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await Directory('build/ui_capture').create(recursive: true);
      await File(
        '${dir.path}/${prefix}_${name}_$page.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    if (pos.extentAfter <= .5) return;
    pos.jumpTo(
      (pos.pixels + 500).clamp(pos.minScrollExtent, pos.maxScrollExtent),
    );
    await t.pumpAndSettle();
  }
  fail('The full scroll was not reached');
}
