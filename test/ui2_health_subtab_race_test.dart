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

/// The Vitals read, with a hand on its clock.
///
/// Only the four calls `VitalsData.load` makes are answered; the Overview
/// load's own queries throw their `re-layer` default, which that loader
/// catches, and nothing in this test looks at Overview.
class _Repo extends LocalRepository {
  /// The respiratory rate the database holds. Changing it is "an import
  /// landed".
  double resp = 11;

  /// Parks the NEXT lungs read until completed. One-shot.
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
  Future<Map<String, dynamic>> getDayLungs(String date) async {
    // Read the value BEFORE parking: a read that started before the import
    // saw the pre-import database, whenever it happens to be resumed.
    final v = resp;
    final h = hold;
    if (h != null) {
      hold = null;
      await h.future;
    }
    return {
      'resp': {'value': v}
    };
  }

  @override
  Future<Map<String, dynamic>> getDayWear(String date) async => const {};

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
    // Wide enough that all five sub-tab chips are on screen to be tapped.
    t.view.physicalSize = const Size(800 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final repo = _Repo();
    app.repo = repo;

    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const Scaffold(body: HealthScreen()),
      ),
    ));
    await _settle(t);

    // The user opens Vitals for the first time. Its read parks mid-flight.
    final parked = Completer<void>();
    repo.hold = parked;
    await t.tap(find.text('Vitals'));
    await _settle(t);
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'the sub-tab should still be loading — nothing to race yet');

    final before = t.state(find.byType(HealthScreen));

    // An import lands while that read is parked. Its cache is still null.
    repo.resp = 17;
    app.bumpInsights();
    await _settle(t);

    // …and only NOW does the pre-import read come back.
    parked.complete();
    await _settle(t);

    expect(find.text('17.0'), findsOneWidget,
        reason: 'the post-revision read must be what is on screen');
    expect(find.text('11.0'), findsNothing,
        reason: 'a read that started before the revision committed after it');
    expect(identical(t.state(find.byType(HealthScreen)), before), isTrue,
        reason: 'the screen was remounted — that is the workaround, not the fix');
  });
}
