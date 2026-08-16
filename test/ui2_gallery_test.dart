// Developer mode is a tool, not a feature.
//
// The failure mode is one line wide: a developer surface that ships visible.
// So the two things asserted here are that the flag is OFF on a fresh install,
// and that nothing in Settings can reach the gallery until it is on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/gallery.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: child,
    );

/// Tall enough that the whole settings list is BUILT. A `ListView` only
/// builds what fits, so on the default 800 pt view every assertion about the
/// bottom of the screen passes whether the row is there or not — including
/// the one that has to fail if the gallery ever ships visible.
void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('developer mode is off on a fresh install', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    expect(Prefs.getBool(Prefs.devMode, false), isFalse);
  });

  testWidgets('settings offers no way into the gallery until it is on',
      (tester) async {
    _tallPhone(tester);
    await tester.pumpWidget(_wrap(
        const MoreSettingsView(version: '0.9.26 (57)', devMode: false)));
    expect(find.text('Component gallery'), findsNothing);
    expect(find.text('Developer'), findsNothing);
    // …and the row that reveals it says nothing about what it does.
    expect(find.text('Version'), findsOneWidget);
  });

  testWidgets('and offers one once it is', (tester) async {
    _tallPhone(tester);
    var opened = false;
    await tester.pumpWidget(_wrap(MoreSettingsView(
      version: '0.9.26 (57)',
      devMode: true,
      onGallery: () => opened = true,
    )));
    expect(find.text('Developer'), findsOneWidget);
    await tester.tap(find.text('Component gallery'));
    expect(opened, isTrue);
  });

  testWidgets('the gallery needs neither a database nor a band',
      (tester) async {
    _tallPhone(tester);
    await tester.pumpWidget(_wrap(const GalleryScreen()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Component gallery'), findsOneWidget);
  });

  test('every component in the gallery has a name and a widget', () {
    final cases = galleryCases();
    // The goldens shoot a subset by design; nothing may be in the goldens and
    // missing from the screen a developer actually opens.
    expect(cases.keys, containsAll(goldenCases().keys));
    expect(cases.keys.where((k) => k.trim().isEmpty), isEmpty);
  });
}
