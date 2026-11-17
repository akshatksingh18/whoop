// Reach history controls and destinations over the real synthetic session store.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

Finder action(String name) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == name);
Future<void> settleIo(WidgetTester t, {bool Function()? ready}) async {
  for (var i = 0; i < 200; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
    if (i >= 15 &&
        (ready?.call() ??
            find.byType(CircularProgressIndicator).evaluate().isEmpty))
      break;
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    // Material's calendar retains Roboto in its default text theme. Substitute
    // the same bundled font here too; Ahem gives it artificial overflows.
    final font = FontLoader('Roboto')
      ..addFont(
        File(
          'assets/fonts/Manrope/Manrope-400.ttf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    await font.load();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/history',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    app = AppState.forTesting()
      ..user = {'age': 30, 'sex': 'f', 'weight_kg': 70, 'height_cm': 170};
    app.repo = LocalRepositoryImpl(
      getProfileMap: () => app.user,
      onSessionChanged: app.publishSessionChange,
    );
    for (final (id, type, age) in [
      ('recent', 'running', 0),
      ('walk', 'walking', 1),
      ('old', 'yoga', 45),
    ]) {
      final at =
          DateTime.now()
              .subtract(Duration(days: age, hours: 3))
              .millisecondsSinceEpoch ~/
          1000;
      await LocalDb.putSession({
        'id': id,
        'type': type,
        'start_ts': at,
        'end_ts': at + 1200,
        'status': 'done',
        'source': 'manual',
        'created_at': at * 1000,
        'steps': 2000,
        'strain': 3.2,
        'avg_hr': 110,
        'calories': 80,
      });
    }
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS synthetic_delete_refusal');
    app.dispose();
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, {Widget? page, double scale = 1}) async {
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      for (var i = 0; i < 40; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
      }
    });
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: page ?? const WorkoutHistoryScreen(weightKg: 70),
        ),
      ),
    );
    await settleIo(t);
  }

  Future<void> dates(WidgetTester t, String value) async {
    await t.tap(find.byTooltip('Select Dates'));
    await t.pumpAndSettle();
    await t.tap(find.text(value).last);
    await t.pumpAndSettle();
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'history filters, reset and month disclosure preserve all stored sessions at ${scale}x',
      (t) async {
        await open(t, scale: scale);
        await t.tap(find.byTooltip('Select Activity'));
        await t.pumpAndSettle();
        await t.tap(find.text('Running').last);
        await t.pumpAndSettle();
        expect(find.text('1 of 3 sessions'), findsOneWidget);
        expect(action('Open Running session'), findsOneWidget);
        expect(action('Open Walking session'), findsNothing);
        await dates(t, 'Last 7 days');
        expect(find.text('1 of 3 sessions'), findsOneWidget);
        await t.tap(find.byTooltip('Clear workout filters'));
        await t.pumpAndSettle();
        expect(find.text('All activities'), findsOneWidget);
        expect(find.text('All dates'), findsOneWidget);
        expect(await t.runAsync(() => db.query('sessions')), hasLength(3));
        await t.tap(find.byTooltip('Select Activity'));
        await t.pumpAndSettle();
        await t.tap(find.text('Other').last);
        await t.pumpAndSettle();
        await dates(t, 'Last 7 days');
        expect(find.text('No matching sessions'), findsOneWidget);
        await dates(t, 'All dates');
        expect(find.text('1 of 3 sessions'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'cancelling a custom date selection leaves the prior filter intact',
    (t) async {
      await open(t);
      await dates(t, 'Last 30 days');
      expect(find.text('2 of 3 sessions'), findsOneWidget);
      await dates(t, 'Choose dates');
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('2 of 3 sessions'), findsOneWidget);
    },
  );
  for (final choice in ['Keep it', 'Remove', 'refused']) {
    testWidgets(
      'history deletion $choice keeps the displayed row consistent with the committed store',
      (t) async {
        await open(t);
        await t.tap(action('Session options').first);
        await t.pumpAndSettle();
        await t.tap(find.text('Delete').last);
        await t.pumpAndSettle();
        expect(find.text('Delete this running?'), findsOneWidget);
        if (choice == 'refused')
          await t.runAsync(
            () => db.execute(
              "CREATE TRIGGER synthetic_delete_refusal BEFORE DELETE ON sessions BEGIN SELECT RAISE(ABORT, 'synthetic refusal'); END",
            ),
          );
        await t.tap(find.text(choice == 'Keep it' ? 'Keep it' : 'Remove').last);
        await settleIo(
          t,
          ready: choice == 'Remove'
              ? () => action('Open Running session').evaluate().isEmpty
              : choice == 'refused'
              ? () => find
                    .text('That workout was not deleted. Try again.')
                    .evaluate()
                    .isNotEmpty
              : null,
        );
        final row = await t.runAsync(() => LocalDb.session('recent'));
        expect(row == null, choice == 'Remove');
        expect(
          action('Open Running session'),
          choice == 'Remove' ? findsNothing : findsOneWidget,
        );
        if (choice == 'refused')
          expect(
            find.text('That workout was not deleted. Try again.'),
            findsOneWidget,
          );
      },
    );
  }
  testWidgets(
    'a saved row opens its full summary, and Back returns to filtered history',
    (t) async {
      await open(t);
      await dates(t, 'Last 7 days');
      await t.tap(action('Open Running session'));
      await settleIo(t);
      expect(find.byType(ActivitySummary), findsOneWidget);
      await t.tap(action('Back').last);
      await settleIo(t);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('2 of 3 sessions'), findsOneWidget);
    },
  );
  testWidgets(
    'a stale session deep link explains removal without inventing a workout',
    (t) async {
      await open(t, page: const SessionDestination('missing'));
      expect(find.text('Session unavailable'), findsOneWidget);
      expect(find.text('It may have been removed.'), findsOneWidget);
      expect(await t.runAsync(() => db.query('sessions')), hasLength(3));
    },
  );
}
