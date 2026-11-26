// Rough-night questions hand off the same dated Journal and preserve accepted edits.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/screens/rough_night.dart';

import 'session_destination_boundaries_test.dart' show io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

const day = '2021-04-06';
const night = RoughNight(
  day: day,
  signs: 2,
  descriptor: 'A harder night',
  moved: ['resting heart rate', 'HRV'],
  knows: [],
);

class QueuedWriter extends LocalRepositoryImpl {
  QueuedWriter() : super(getProfileMap: () => const {});

  final release = Completer<void>();
  final calls = <(String, List<String>)>[];

  @override
  Future<void> mergeJournalTags(String date, List<String> tags) async {
    calls.add((date, List.of(tags)));
    await release.future;
    await super.mergeJournalTags(date, tags);
  }
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('rough-night-journal-handoff');
  });
  setUp(() async {
    await resetCoverageStore();
    await LocalDb.putJournal(day, '["travel"]', 'Original authored note');
  });
  tearDownAll(LocalDb.close);

  testWidgets('rough-night amounts open the historical draft without writing', (
    t,
  ) async {
    final app = AppState.forTesting()
      ..repo = LocalRepositoryImpl(getProfileMap: () => const {});
    addTearDown(app.dispose);
    final before = await LocalDb.journalRows();
    const card = RoughNightCard(night: night, ask: 'on');
    await localizedPage(t, const Scaffold(body: card), app: app);

    await t.tap(find.text('caffeine'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add how much'));
    await io(t);
    final editor = find.byType(JournalCompose);
    expect(t.widget<JournalCompose>(editor).date, day);
    expect(
      t
          .widgetList<TextField>(find.byType(TextField))
          .any((field) => field.controller?.text == 'Original authored note'),
      isTrue,
    );
    Navigator.of(t.element(editor)).pop();
    await io(t);
    expect(find.byWidget(card), findsOneWidget);
    expect(find.text('Add how much'), findsOneWidget);
    expect(Prefs.getString(kRoughNightDismissed, ''), isEmpty);
    expect(await t.runAsync(LocalDb.journalRows), before);
  });

  testWidgets('rough-night tag save locks until accepted and merges new tags', (
    t,
  ) async {
    final reader = QueuedWriter();
    final app = AppState.forTesting()..repo = reader;
    addTearDown(app.dispose);
    var dismissed = 0;
    await localizedPage(
      t,
      Scaffold(
        body: RoughNightCard(
          night: night,
          ask: 'on',
          onDismiss: () => dismissed++,
        ),
      ),
      app: app,
    );

    await t.tap(find.text('caffeine'));
    await t.pumpAndSettle();
    await t.tap(find.text('Log it for that night'));
    await t.pump();
    expect(find.text('Saving'), findsOneWidget);
    expect(find.text('Log it for that night'), findsNothing);
    await t.tap(find.text('Saving'));
    expect(reader.calls, hasLength(1));
    expect(reader.calls.single.$1, day);
    expect(reader.calls.single.$2, ['caffeine']);
    expect(dismissed, 0);

    await t.runAsync(
      () => LocalDb.putJournal(
        day,
        '["travel","stress"]',
        'Concurrent authored note',
      ),
    );
    reader.release.complete();
    await io(t);
    expect(dismissed, 1);
    expect(Prefs.getString(kRoughNightDismissed, ''), day);
    final row = (await t.runAsync(LocalDb.journalRows))!.single;
    expect(
      jsonDecode(row['tags_json'] as String),
      unorderedEquals(['travel', 'stress', 'caffeine']),
    );
    expect(row['note'], 'Concurrent authored note');
    expect(find.text('Saving'), findsNothing);
  });
}
