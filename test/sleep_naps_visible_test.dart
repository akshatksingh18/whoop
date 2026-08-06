// A two-hour afternoon nap was detected, stored, and drawn as a band on the
// day timeline — and was still nowhere to be found on the Sleep screen. Two
// separate reasons, both pinned here:
//
//   1. The engine writes each period as `is_main` / `start` / `end` /
//      `asleep_min`; the periods screen reads `onset_ts` / `wake_ts` /
//      `duration_min`. Every card rendered as "0m" with no time range.
//   2. The only route into that screen was an AppScaffold action, and the Sleep
//      tab embeds SleepNightContent (embedded: true), so the scaffold — and the
//      action with it — never builds in the shipped app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/data/local_repository_impl.dart'
    show sleepPeriodsForScreen;
import 'package:openstrap_edge/theme/theme.dart';
import 'package:openstrap_edge/theme/tokens.dart';
import 'package:openstrap_edge/ui/sleep/sleep_detail_screen.dart'
    show SleepNightContent;

/// Periods exactly as `_sleepPeriods` writes them into the bundle.
const _rawPeriods = [
  {'is_main': true, 'start': 1000000, 'end': 1024600, 'asleep_min': 410},
  {'is_main': false, 'start': 1060000, 'end': 1066060, 'asleep_min': 101},
];

/// The night payload the mapping enriches the main period from.
const _night = <String, dynamic>{
  'duration_min': 400, // TST — less than the 410-minute window
  'efficiency': 0.93,
  'stages_confidence': 0.62,
  'light_min': 220,
  'deep_min': 60,
  'rem_min': 120,
  'hypnogram': [
    {'t': 1000000, 'stage': 'light'},
  ],
};

Widget _host(Widget child) {
  AppColors.active = kDarkPalette;
  return MaterialApp(
    theme: buildOpenStrapTheme(kDarkPalette),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

String _today() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _nightWithNap() => {
      ..._night,
      'has_sleep': true,
      'sleep_source': 'auto',
      'need_min': 480,
      'onset_ts': 1000000,
      'wake_ts': 1024600,
      'periods': sleepPeriodsForScreen(_rawPeriods, night: _night),
    };

void main() {
  group('sleepPeriodsForScreen', () {
    test('maps the engine keys onto the ones the screen reads', () {
      final p = sleepPeriodsForScreen(_rawPeriods, night: _night);
      expect(p, hasLength(2));
      expect(p[0]['onset_ts'], 1000000);
      expect(p[0]['wake_ts'], 1024600);
      expect(p[1]['onset_ts'], 1060000);
      expect(p[1]['duration_min'], 101);
    });

    test('main period shows TST, not the window length', () {
      final main = sleepPeriodsForScreen(_rawPeriods, night: _night).first;
      expect(main['duration_min'], 400);
      expect(main['efficiency'], 0.93);
      expect(main['confidence'], 0.62);
      expect((main['stages'] as Map)['deep_min'], 60);
      expect(main['hypnogram'], isA<List>());
    });

    test('a nap carries no invented stages, efficiency or confidence', () {
      final nap = sleepPeriodsForScreen(_rawPeriods, night: _night)[1];
      expect(nap.containsKey('stages'), isFalse);
      expect(nap.containsKey('efficiency'), isFalse);
      expect(nap.containsKey('confidence'), isFalse);
    });

    test('a length outside its own window falls back to the window', () {
      final p = sleepPeriodsForScreen([
        {'is_main': false, 'start': 1060000, 'end': 1066060, 'asleep_min': -30},
        {'is_main': false, 'start': 1060000, 'end': 1066060, 'asleep_min': 900},
        {'is_main': false, 'start': 1060000, 'end': 1066060},
      ]);
      expect(p.map((e) => e['duration_min']), everyElement(101));
    });

    test('drops junk instead of rendering a zero-length card', () {
      final p = sleepPeriodsForScreen([
        {'is_main': false, 'start': 1060000, 'end': 1060000},
        {'is_main': false, 'end': 1066060},
        'not a period',
      ]);
      expect(p, isEmpty);
      expect(sleepPeriodsForScreen(null), isEmpty);
    });
  });

  group('SleepNightContent naps row', () {
    testWidgets('a nap is visible on the night screen and opens the breakdown',
        (t) async {
      t.view.physicalSize = const Size(390, 3600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      var opened = 0;
      await t.pumpWidget(_host(SleepNightContent(
        data: _nightWithNap(),
        date: _today(),
        onEditTimes: () {},
        onConfirmFallback: () {},
        onClearOverride: () {},
        onOpenPeriods: () => opened++,
      )));
      await t.pump(const Duration(milliseconds: 1200));

      expect(find.text('Daytime nap'), findsOneWidget);
      expect(find.text('1h 41m'), findsOneWidget);
      await t.tap(find.text('Daytime nap'));
      await t.pump(const Duration(milliseconds: 400));
      expect(opened, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('no naps, no row', (t) async {
      t.view.physicalSize = const Size(390, 3600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      final data = _nightWithNap();
      data['periods'] = sleepPeriodsForScreen(
        [_rawPeriods.first],
        night: _night,
      );
      await t.pumpWidget(_host(SleepNightContent(
        data: data,
        date: _today(),
        onEditTimes: () {},
        onConfirmFallback: () {},
        onClearOverride: () {},
        onOpenPeriods: () {},
      )));
      await t.pump(const Duration(milliseconds: 1200));

      expect(find.text('Daytime nap'), findsNothing);
    });
  });
}
