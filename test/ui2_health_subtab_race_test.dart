// A revision landed WHILE a sub-tab was loading for the first time.
//
// The token in RevisionReload only rejects an old read once a NEWER token has
// been issued for that key — and nothing issues one unless `reload` re-reads
// the key. Health's `reload` used to re-read a sub-tab on its cached value
// being non-null, which is false for exactly the read that is still in flight.
// So the pre-revision read passed `stillNewest` and committed pre-import data
// AFTER the import, on the first load after the import, which is the one
// moment the data is guaranteed to be changing.
//
// The order below is the whole test: start the read, bump the revision while
// it is parked, and let the OLD read finish LAST. Bumping after the first read
// settles passes on the broken code too — that is how this hole got here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

const _day = '2026-08-16';

/// The vitals read (now part of Overview), with a hand on its clock.
///
/// Only the four calls `VitalsData.load` makes are answered; the Overview
/// load's own queries throw their `re-layer` default, which that loader
/// catches.
class _Repo extends LocalRepository {
  /// Minutes worn that the database holds. Changing it is "an import landed".
  int worn = 300;

  /// Parks the NEXT wear read until completed. One-shot.
  Completer<void>? hold;

  @override
  Future<Map<String, dynamic>> getToday() async => const {
        'status': {'today_day': _day}
      };

  @override
  Future<List<String>> availableDays() async => const [_day];

  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) async =>
      {'date': date};

  @override
  Future<Map<String, dynamic>> getDayLungs(String date) async => const {};

  @override
  Future<Map<String, dynamic>> getDayWear(String date) async {
    // Read the value BEFORE parking: a read that started before the import
    // saw the pre-import database, whenever it happens to be resumed.
    final v = worn;
    final h = hold;
    if (h != null) {
      hold = null;
      await h.future;
    }
    return {'worn_min': v};
  }

  @override
  Future<Map<String, dynamic>> getDayHrv(String date) async => const {};
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump();
  }
}

void main() {
  testWidgets('a read in flight when the revision lands does not win',
      (t) async {
    t.view.physicalSize = const Size(800 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final repo = _Repo();
    app.repo = repo;

    // Overview's first vitals read parks mid-flight.
    final parked = Completer<void>();
    repo.hold = parked;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const Scaffold(body: HealthScreen()),
      ),
    ));
    await _settle(t);
    expect(find.text('Wear time'), findsNothing,
        reason: 'the vitals read should still be in flight');

    final before = t.state(find.byType(HealthScreen));

    // An import lands while that read is parked.
    repo.worn = 420;
    app.bumpInsights();
    await _settle(t);

    // …and only NOW does the pre-import read come back.
    parked.complete();
    await _settle(t);

    expect(find.text('7h 00m'), findsOneWidget,
        reason: 'the post-revision read must be what is on screen');
    expect(find.text('5h 00m'), findsNothing,
        reason: 'a read that started before the revision committed after it');
    expect(identical(t.state(find.byType(HealthScreen)), before), isTrue,
        reason: 'the screen was remounted — that is the workaround, not the fix');
  });
}
