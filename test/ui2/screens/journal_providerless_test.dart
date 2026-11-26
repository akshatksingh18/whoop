// The journal editor with nothing behind it: no repository reads as a failed
// load, the weight dialog without a units controller works in kg, and a trend
// that cannot read its history says it has too little. Authored values only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

Finder _action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is WhoopTextField && w.label == label),
  matching: find.byType(TextField),
);

Future<void> _until(WidgetTester t, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
}

Future<void> _press(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('journal-providerless');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting();
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t, String day) async {
    await localizedPage(t, JournalCompose(date: day), app: app, settle: false);
    await _until(
      t,
      () =>
          _action('Enter weight').evaluate().isNotEmpty ||
          find.text('This day could not load').evaluate().isNotEmpty,
    );
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    });
  }

  testWidgets('no repository reads as a day that could not load', (t) async {
    await open(t, '2021-04-06');
    expect(find.text('This day could not load'), findsOneWidget);
    expect(find.text('Nothing was changed.'), findsOneWidget);
  });

  testWidgets('without a units controller the weight dialog works in kg', (
    t,
  ) async {
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    const day = '2021-04-06';
    await open(t, day);
    await _press(t, _action('Enter weight'));
    final input = _field('Weight (kg)');
    await t.enterText(input, 'not a number');
    await _press(t, find.widgetWithText(TextButton, 'Save').last);
    expect(find.textContaining('is not a number'), findsOneWidget);
    await t.enterText(input, '70.25');
    await _press(t, find.widgetWithText(TextButton, 'Save').last);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('70.3 kg'), findsOneWidget);
  });

  testWidgets('a trend that cannot read history shows too few entries', (
    t,
  ) async {
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    await open(t, todayLabel());
    final original = LocalDb.dbName;
    final dir = Directory.systemTemp.createTempSync('authored-blocker-');
    final blocker = File('${dir.path}/file')..writeAsStringSync('');
    await t.runAsync(LocalDb.close);
    LocalDb.dbName = '${blocker.path}/unopenable.sqlite';
    addTearDown(() async {
      await t.runAsync(LocalDb.close);
      LocalDb.dbName = original;
      dir.deleteSync(recursive: true);
    });
    // The trend opens on a spinner, so this tap cannot wait for a settle.
    await t.ensureVisible(_action('See the weight trend'));
    await t.tap(_action('See the weight trend'));
    await _until(
      t,
      () => find.text('Not enough entries for a trend').evaluate().isNotEmpty,
    );
  });
}
