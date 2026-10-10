// The Progress tab renders with real records and with none, at a narrow
// width and large text, without overflow; switching measurement and range
// keeps it drawing (build 86).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

Widget _app(AppState app, double scale) => ChangeNotifierProvider<AppState>.value(
  value: app,
  child: MaterialApp(
    theme: buildTheme(Brightness.dark),
    builder: (c, w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: w!,
    ),
    home: const Scaffold(body: ProgressScreen()),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_progress_screen_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('empty, then with records, at ${scale}x', (t) async {
      // Taller at 2x so the page's first controls are laid out under the
      // Goal card; the width stays the narrow 360 the test is about.
      t.view.physicalSize = Size(360, 780 * scale * 1.5);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.runAsync(() async {
        final db = await LocalDb.instance;
        await db.delete('body_weight');
        await db.delete('body_measure');
      });
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await t.pumpWidget(_app(app, scale));
      await _until(t, () => find.text('Add entry').evaluate().isNotEmpty);
      expect(t.takeException(), isNull);
      expect(find.textContaining('Nothing recorded'), findsWidgets);

      final today = DateTime.parse(todayLabel());
      await t.runAsync(() async {
        for (var i = 0; i < 20; i += 2) {
          final d = dayLabelOf(DateTime(today.year, today.month, today.day - i));
          await BodyLogDb.putWeight(d, 80 + i / 10, 'kg', historyOnly: true);
        }
        await BodyLogDb.putMeasure(BodyMeasure(
          date: dayLabelOf(DateTime(today.year, today.month, today.day - 3)),
          recordedAt: DateTime.now(),
          inches: {'waistNavel': 34, 'neck': 15.5},
        ));
      });
      app.bumpInsights();
      await _until(t, () => find.text('LATEST').evaluate().isNotEmpty);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Waist (navel)'));
      await t.pump();
      await t.tap(find.text('1 month'));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }
}
