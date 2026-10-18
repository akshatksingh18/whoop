// The Progress tab renders with real records and with none, at a narrow
// width and large text, without overflow; the Body page's measurement and
// History range keep it drawing (build 86; Build 90 overview and details).

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
    theme: buildTheme(Brightness.light),
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
    testWidgets('overview, then the Body page, empty and with records, at ${scale}x', (t) async {
      // Taller at 2x so the overview's results sit in view; the width stays
      // the narrow 360 the test is about.
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
      await _until(t, () => find.text('Add body entry').evaluate().isNotEmpty);
      expect(t.takeException(), isNull);
      // Build 90: while the goal check cannot judge, the card says when it
      // first can and shows this week's evidence, not a "Not yet" verdict.
      expect(find.text('THIS WEEK SO FAR'), findsOneWidget);
      expect(find.text('Not yet'), findsNothing);
      await t.scrollUntilVisible(
        find.text('No waist reading yet'),
        150,
        scrollable: find.byType(Scrollable).first,
      );

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
      // The waist row stays in view: a known reading shows even with nothing
      // to compare it with.
      await _until(t, () => find.text('34 in').evaluate().isNotEmpty);
      final list = find.byType(Scrollable).first;
      expect(t.takeException(), isNull);

      // The Average weight row opens Body with weight chosen; History range explores.
      await t.scrollUntilVisible(
        find.text('Average weight'),
        150,
        scrollable: list,
      );
      // Build 91: the waiting goal card is taller, so at large text the row
      // can stop under the tab bar; bring it to the top before tapping.
      await t.ensureVisible(find.text('Average weight'));
      await t.pumpAndSettle();
      await t.tap(find.text('Average weight'));
      await _until(t, () => find.text('HISTORY RANGE').evaluate().isNotEmpty);
      // The Body page's own vertical scroll view: the nearest Scrollable
      // around its header, not whichever horizontal strip happens to be built
      // last (Build 90: a segmented control that fits is a Row now).
      // Resolved once, while the header is built: a lazy list drops it after
      // the first scroll step, but the Scrollable element itself stays.
      final pageElement = t.element(
        find
            .ancestor(
              of: find.text('HISTORY RANGE'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final page = find.byElementPredicate((e) => identical(e, pageElement));
      await t.scrollUntilVisible(find.text('Latest'), 200, scrollable: page);
      expect(t.takeException(), isNull);
      final waist = find.text('Waist (navel)');
      await t.scrollUntilVisible(waist.first, 150, scrollable: page);
      await t.ensureVisible(waist.first);
      await t.pumpAndSettle();
      await t.tap(waist.first);
      await t.pumpAndSettle();
      await t.drag(page, const Offset(0, 5000));
      await t.pumpAndSettle();
      await t.tap(find.text('30 days').first);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('More periods'));
      await t.pumpAndSettle();
      await t.tap(find.text('1 year').last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      // Back returns to the overview, which the range never changed.
      Navigator.of(t.element(find.text('HISTORY RANGE'))).pop();
      await t.pumpAndSettle();
      await t.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await t.pumpAndSettle();
      expect(find.text('Add body entry'), findsOneWidget);
      expect(find.text('THIS WEEK SO FAR'), findsOneWidget);
    });
  }
}
