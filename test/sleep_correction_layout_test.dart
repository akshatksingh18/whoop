import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/models/metric.dart';
import 'package:whoop_companion/ui2/ui2.dart';

Future<void> capturePages(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('UI_CAPTURE')) return;
  final scroll = t
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstOrNull;
  if (scroll != null) {
    scroll.position.jumpTo(0);
    await t.pumpAndSettle();
  }
  var page = 0;
  while (true) {
    await t.runAsync(() async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      Directory('build/ui_capture').createSync(recursive: true);
      File(
        'build/ui_capture/sleep_correction_${name}_$page.png',
      ).writeAsBytesSync(bytes.buffer.asUint8List());
      image.dispose();
    });
    if (scroll == null ||
        scroll.position.pixels >= scroll.position.maxScrollExtent) {
      break;
    }
    final next =
        (scroll.position.pixels + scroll.position.viewportDimension * .8).clamp(
          0.0,
          scroll.position.maxScrollExtent,
        );
    scroll.position.jumpTo(next);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    page++;
    expect(
      page,
      lessThan(30),
      reason: 'A complete bounded page sequence must reach the footer',
    );
  }
}

void main() {
  setUpAll(() async {
    for (final family in ['Manrope', '.SF Pro Text', 'Roboto']) {
      final font = FontLoader(family);
      for (final file in Directory(
        'assets/fonts/Manrope',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
        font.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
      await font.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
    icons.addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
    await icons.load();
  });
  for (final state in ['clear', 'rejected', 'pending']) {
    final rejected = state == 'rejected';
    for (final view in [(390.0, 1.0), (320.0, 2.0), (430.0, 3.1)]) {
      testWidgets(
        'corrected unknown night keeps reviewed actions at $view state=$state',
        (t) async {
          final app = AppState.forTesting();
          addTearDown(app.dispose);
          t.view.physicalSize = Size(view.$1, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            ChangeNotifierProvider.value(
              value: app,
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildTheme(Brightness.light),
                  locale: const Locale('en'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(
                      c,
                    ).copyWith(textScaler: TextScaler.linear(view.$2)),
                    child: child!,
                  ),
                  home: SleepDetail(
                    data: SleepData(
                      day: '2021-04-06',
                      days: const ['2021-04-06', '2021-04-05'],
                      night: {
                        'has_sleep': false,
                        'sleep_source': rejected ? 'rejected' : 'auto',
                        'sleep_correction': {
                          'action': rejected ? 'rejected' : 'clear',
                          'pending': state == 'pending',
                          'usable': false,
                        },
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(find.text('Naps'), findsOneWidget);
          expect(find.text('Fix sleep times'), findsNothing);
          expect(
            find.textContaining('The previous result is kept for recovery.'),
            findsOneWidget,
          );
          await t.scrollUntilVisible(
            find.text('Breathing pattern in sleep'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Breathing pattern in sleep'), findsOneWidget);
          if (rejected) {
            await t.scrollUntilVisible(
              find.textContaining('Undo'),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            expect(find.textContaining('Undo'), findsOneWidget);
          } else {
            expect(find.textContaining('Undo'), findsNothing);
          }
          expect(t.takeException(), isNull);
          await capturePages(t, 'sleep_${state}_${view.$1}_${view.$2}x');
        },
      );
    }
  }
  for (final reason in ['pending', 'rejected', 'no_replacement']) {
    for (final view in [(390.0, 1.0), (320.0, 2.0), (430.0, 3.1)]) {
      testWidgets('corrected Recovery explains $reason at $view', (t) async {
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        t.view.physicalSize = Size(view.$1, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final note = 'sleep_correction_$reason';
        await t.pumpWidget(
          ChangeNotifierProvider.value(
            value: app,
            child: RepaintBoundary(
              key: const ValueKey('capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(Brightness.light),
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: TextScaler.linear(view.$2)),
                  child: child!,
                ),
                home: ReadinessDetail(
                  day: '2021-04-06',
                  data: ReadinessData(
                    readiness: Metric(note: note),
                    absentDiag: {'sleep_correction': note},
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Recovery is not scored'), findsOneWidget);
        expect(find.text('What was missing'), findsOneWidget);
        expect(t.takeException(), isNull);
        await capturePages(t, 'recovery_${reason}_${view.$1}_${view.$2}x');
      });
    }
  }
}
