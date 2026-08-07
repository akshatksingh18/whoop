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

import 'package:openstrap_edge/theme/theme.dart';
import 'package:openstrap_edge/theme/tokens.dart';
import 'package:openstrap_edge/ui/sleep/sleep_detail_screen.dart'
    show SleepNightContent;


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
      // The vocabulary the producer emits since #204. This used to be built by
      // `sleepPeriodsForScreen`, which translated the old
      // start/end/asleep_min shape; that translator is gone because the writer
      // now emits these keys directly and `_periodsWithMainStages` enriches
      // them on read.
      'periods': const [
        {
          'is_main': true,
          'onset_ts': 1000000,
          'wake_ts': 1024600,
          'duration_min': 400,
          'efficiency': 0.93,
          'confidence': 0.62,
          'stages': {'light_min': 220, 'deep_min': 60, 'rem_min': 120},
        },
        {
          'is_main': false,
          'onset_ts': 1060000,
          'wake_ts': 1066060,
          'duration_min': 101,
        },
      ],
    };

void main() {
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
      // Main sleep only — the nap row must not appear.
      data['periods'] =
          [(data['periods'] as List).first as Map<String, dynamic>];
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

  group('an unknown nap duration is never rendered as zero', () {
    testWidgets('the naps row shows "—" when a nap duration is unknown',
        (t) async {
      t.view.physicalSize = const Size(390, 3600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      final data = _nightWithNap();
      final periods = (data['periods'] as List).cast<Map<String, dynamic>>();
      data['periods'] = [
        periods.first,
        {...periods[1], 'duration_min': null},
      ];

      await t.pumpWidget(_host(SleepNightContent(
        data: data,
        date: _today(),
        onEditTimes: () {},
        onConfirmFallback: () {},
        onClearOverride: () {},
        onOpenPeriods: () {},
      )));
      await t.pumpAndSettle();

      expect(find.text('Daytime nap'), findsOneWidget);
      expect(
        find.text('—'),
        findsWidgets,
        reason: 'summing an unknown as 0 would under-report the nap total',
      );
      expect(find.text('0m'), findsNothing);
    });
  });
}
