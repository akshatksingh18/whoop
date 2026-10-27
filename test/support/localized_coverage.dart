// Real shipped localization delegates; authored state, no native acceptance claim.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/ui2.dart';

Future<void> localizedPage(
  WidgetTester t,
  Widget child, {
  AppState? app,
  String language = 'en',
  double scale = 1,
  bool push = false,
  bool settle = true,
}) async {
  t.view.physicalSize = const Size(430, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  Widget frame = MaterialApp(
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(Brightness.light),
    builder: (c, w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: w!,
    ),
    home: push
        ? Navigator(
            onGenerateInitialRoutes: (_, _) => [
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Closed test page')),
              ),
              MaterialPageRoute<void>(builder: (_) => Material(child: child)),
            ],
          )
        : Material(child: child),
  );
  if (app != null) {
    frame = ChangeNotifierProvider<AppState>.value(value: app, child: frame);
  }
  await t.pumpWidget(frame);
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump(const Duration(milliseconds: 200));
  }
  expect(t.takeException(), isNull);
  expect(AppLocalizations.of(t.element(find.byWidget(child))), isNotNull);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
}

// Await the rendered control's real async callback so SQLite does not deadlock
// against the widget fake clock. Gesture wiring is tested separately.
Future<void> invokeControl(WidgetTester t, dynamic callback) async {
  expect(callback, isNotNull);
  await t.runAsync(() async {
    await callback();
  });
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> reveal(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      finder,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
  }
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
}

Future<Set<String>> readPage(WidgetTester t) async {
  final seen = <String>{};
  final scroll = find.byType(Scrollable);
  if (scroll.evaluate().isEmpty) return seen;
  final position = t.state<ScrollableState>(scroll.first).position;
  position.jumpTo(0);
  for (var i = 0; i < 80; i++) {
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    seen.addAll(t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''));
    if (position.extentAfter < .5) return seen;
    position.jumpTo((position.pixels + 500).clamp(0, position.maxScrollExtent));
  }
  fail('Complete component content was not reached');
}
