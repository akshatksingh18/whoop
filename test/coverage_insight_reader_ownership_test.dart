// Real Trends/Recovery/What changed readers over authored SQLite. Only the
// first repository read's completion/refusal is controlled; all data stays real.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/health_screen.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/ui2/screens/what_changed.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class _Reader extends LocalRepositoryImpl {
  _Reader() : super(getProfileMap: () => {});
  final refusals = <int>{};
  Completer<void>? heldFirst;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> getToday() async {
    final n = ++calls;
    final refused = refusals.contains(n);
    if (n == 1) await heldFirst?.future;
    if (refused) throw StateError('authored insight read refusal');
    return super.getToday();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('insight-reader-ownership');
  });
  late AppState app;
  late _Reader reader;
  setUp(() async {
    await resetCoverageStore();
    reader = _Reader();
    app = AppState.forTesting()..repo = reader;
    await LocalDb.putJournal(
      '2021-04-06',
      '["authored"]',
      'Preserve this unrelated record',
    );
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  const failures = {
    'trends': 'Trends could not be read',
    'recovery': 'Recovery could not load',
    'findings': 'Findings could not load',
  };
  Widget page(String kind) => switch (kind) {
    'trends' => const HealthScreen(),
    'recovery' => const ReadinessDetail(),
    _ => const WhatChangedScreen(),
  };
  Future<void> open(WidgetTester t, String kind) async {
    await localizedPage(t, Scaffold(body: page(kind)), app: app, settle: false);
    if (reader.heldFirst == null) {
      await io(t);
    } else {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> intact(WidgetTester t) async {
    final rows = await t.runAsync(
      () => LocalDb.journalRows(date: '2021-04-06'),
    );
    expect(rows!.single['note'], 'Preserve this unrelated record');
    expect(
      await t.runAsync(
        () async => (await LocalDb.instance).query('day_result'),
      ),
      isEmpty,
    );
    expect(t.takeException(), isNull);
  }

  for (final kind in failures.keys) {
    testWidgets(
      '$kind missing repository stays absent and creates no measurements',
      (t) async {
        app.repo = null;
        await open(t, kind);
        expect(reader.calls, 0);
        expect(find.text(failures[kind]!), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await intact(t);
      },
    );

    testWidgets(
      '$kind refused first read retries and observes a revision without replacing its State',
      (t) async {
        reader.refusals.add(1);
        await open(t, kind);
        expect(find.text(failures[kind]!), findsOneWidget);
        final state = t.state(
          find.byWidgetPredicate(
            (w) => w.runtimeType == page(kind).runtimeType,
          ),
        );
        reader.refusals.clear();
        final status = find.byWidgetPredicate(
          (w) => w is StatusCard && w.what == failures[kind],
        );
        // Invoke the actual rendered Retry control; its completion performs real reads.
        final retry = t.widget<StatusCard>(status).onFix!;
        // This existing control starts a fire-and-forget read. Run real I/O
        // before settling its loading animation under Flutter's fake clock.
        await t.runAsync(() async {
          retry();
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await io(t);
        expect(find.text(failures[kind]!), findsNothing);
        final before = reader.calls;
        app.bumpInsights();
        await io(t);
        expect(reader.calls, greaterThan(before));
        expect(
          t.state(
            find.byWidgetPredicate(
              (w) => w.runtimeType == page(kind).runtimeType,
            ),
          ),
          same(state),
        );
        expect(find.text(failures[kind]!), findsNothing);
        await intact(t);
      },
    );

    for (final oldFails in [false, true]) {
      testWidgets(
        '$kind late ${oldFails ? 'refusal' : 'success'} cannot replace the newer result',
        (t) async {
          final held = reader.heldFirst = Completer<void>();
          reader.refusals.add(oldFails ? 1 : 2);
          await open(t, kind);
          expect(reader.calls, 1);
          app.bumpInsights();
          await io(t);
          expect(reader.calls, 2);
          expect(
            find.text(failures[kind]!),
            oldFails ? findsNothing : findsOneWidget,
          );
          held.complete();
          await io(t);
          expect(
            find.text(failures[kind]!),
            oldFails ? findsNothing : findsOneWidget,
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);
          await intact(t);
        },
      );

      testWidgets(
        '$kind disposal ignores late ${oldFails ? 'refusal' : 'success'} and detaches revisions',
        (t) async {
          final held = reader.heldFirst = Completer<void>();
          if (oldFails) reader.refusals.add(1);
          await open(t, kind);
          expect(reader.calls, 1);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          held.complete();
          await io(t);
          final before = reader.calls;
          app.bumpInsights();
          await io(t);
          expect(reader.calls, before);
          await intact(t);
        },
      );
    }
  }
}
