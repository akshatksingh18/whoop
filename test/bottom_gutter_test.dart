// The last card of a scrolling screen must clear the shell's floating chrome.
//
// Screens carried a hardcoded 120 pt bottom padding. The shell's chrome is 106
// pt on a current iPhone (72 pt pill + 34 pt home indicator), so that left 14
// pt — and the live-workout banner stacks ABOVE the pill inside the same
// `bottomNavigationBar`, which pushes the chrome past 120 and buries the last
// card while a workout is running.
//
// `Scaffold(extendBody: true)` reports the true height of that chrome as
// `MediaQuery.padding.bottom` inside the body, so the padding is derived from it
// rather than guessed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/ui/design/app_scaffold.dart';
import 'package:openstrap_edge/ui/design/nav_pill.dart';
import 'package:openstrap_edge/ui/kit/os_icons.dart';

/// iPhone 17 Pro-ish: 34 pt home indicator.
const _phone = MediaQueryData(
  size: Size(393, 852),
  padding: EdgeInsets.only(top: 59, bottom: 34),
  viewPadding: EdgeInsets.only(top: 59, bottom: 34),
);

Widget _shell({Widget? banner, required Widget page}) => MaterialApp(
      home: MediaQuery(
        data: _phone,
        child: ShellScaffold(
          controller: PageController(),
          index: 0,
          items: const [NavPillItem(OsIcon.today, 'Today')],
          pages: [page],
          onSelect: (_) {},
          onPageChanged: (_) {},
          banner: banner,
        ),
      ),
    );

void main() {
  testWidgets('the gutter covers the whole nav pill, not a guessed constant',
      (t) async {
    late double gutter;
    await t.pumpWidget(_shell(
      page: Builder(builder: (c) {
        gutter = dsBottomGutter(c, gap: 0);
        return const SizedBox.expand();
      }),
    ));

    final pill = t.getSize(find.byType(FloatingNavPill));
    expect(gutter, greaterThanOrEqualTo(pill.height + _phone.padding.bottom),
        reason: 'the pill and the home indicator both have to be cleared');
  });

  testWidgets('a live-workout banner grows the gutter with it', (t) async {
    late double plain;
    await t.pumpWidget(_shell(
      page: Builder(builder: (c) {
        plain = dsBottomGutter(c, gap: 0);
        return const SizedBox.expand();
      }),
    ));

    late double withBanner;
    await t.pumpWidget(_shell(
      banner: const SizedBox(height: 64),
      page: Builder(builder: (c) {
        withBanner = dsBottomGutter(c, gap: 0);
        return const SizedBox.expand();
      }),
    ));

    expect(withBanner, plain + 64,
        reason: 'the banner stacks above the pill and must be cleared too');
    // The old constant is the regression this pins: it was already smaller than
    // the plain chrome, and a running workout put it far under.
    expect(withBanner, greaterThan(120));
  });

  testWidgets('a screen outside the shell only clears its own safe area',
      (t) async {
    late double gutter;
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: _phone,
        child: Builder(builder: (c) {
          gutter = dsBottomGutter(c, gap: 0);
          return const SizedBox.expand();
        }),
      ),
    ));
    // No pill on a pushed sub-screen — padding it for one would leave a hole.
    expect(gutter, _phone.padding.bottom);
  });
}
