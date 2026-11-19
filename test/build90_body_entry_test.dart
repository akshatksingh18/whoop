// Build 90: the body entry form validates every field before it writes
// (B90-01), and weight with Save comes first, tape and photos optional below.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _app(AppState app) => ChangeNotifierProvider<AppState>.value(
  value: app,
  child: MaterialApp(
    theme: buildTheme(Brightness.light),
    home: const BodyEntryScreen(unit: 'kg'),
  ),
);

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'whoop_body_entry_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    // Open it outside the widget tests' fake clock.
    await LocalDb.instance;
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  testWidgets('weight and Save come first; tape and photos are optional', (
    t,
  ) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    await t.pumpWidget(_app(app));
    await _until(t, () => find.text('Save').evaluate().isNotEmpty);
    expect(find.text('WEIGHT (KG)'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    // Tape fields stay closed until asked for.
    expect(find.text(BodySite.waistNavel.title.toUpperCase()), findsNothing);
    expect(find.text('Measurements'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
  });

  testWidgets('an invalid tape value saves nothing, not even the weight', (
    t,
  ) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    await t.pumpWidget(_app(app));
    await _until(t, () => find.text('Save').evaluate().isNotEmpty);
    await t.enterText(find.byType(TextField).first, '80');
    await t.tap(find.text('Measurements'));
    await t.pump();
    final waist = find.ancestor(
      of: find.text(BodySite.waistNavel.title.toUpperCase()),
      matching: find.byType(Column),
    );
    await t.enterText(
      find.descendant(of: waist.first, matching: find.byType(TextField)),
      'abc',
    );
    await t.ensureVisible(find.text('Save'));
    await t.pump();
    await t.tap(find.text('Save'));
    await _until(
      t,
      () => find.textContaining('must be one number').evaluate().isNotEmpty,
    );
    final saved = await t.runAsync(() => BodyLogDb.weightOn(todayLabel()));
    expect(saved, isNull, reason: 'B90-01: nothing is written before every field validates');
    // The draft stays in the form.
    final field = t.widget<TextField>(
      find.byType(TextField, skipOffstage: false).first,
    );
    expect(field.controller?.text, '80');
  });

  testWidgets('a valid weight alone saves and closes', (t) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    await t.pumpWidget(_app(app));
    await _until(t, () => find.text('Save').evaluate().isNotEmpty);
    await t.enterText(find.byType(TextField).first, '79.4');
    await t.tap(find.text('Save'));
    await _until(t, () => find.text('Save').evaluate().isEmpty);
    // Let the profile update that follows today's first reading finish.
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(seconds: 1));
    }
    final saved = await t.runAsync(() => BodyLogDb.weightOn(todayLabel()));
    expect(saved?.kg, closeTo(79.4, 1e-9));
  });
}
