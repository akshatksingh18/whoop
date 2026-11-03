// Body history -> edit/delete/retain related records, over synthetic SQLite.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

class App extends AppState {
  App() : super.forTesting();
  final profileWrites = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> fields,
  ) async {
    profileWrites.add({...fields});
    user = {...?user, ...fields};
    return user!;
  }
}

Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 35));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Finder matchingAction(String text) => find.byWidgetPredicate(
  (w) => w is Pressable && (w.semanticLabel?.startsWith(text) ?? false),
);
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await flush(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late App app;
  late UnitsController units;
  late String today, earlier;
  late ProgressData data;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/body-history',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    DayClock.install([], []);
    await LocalDb.wipeAll();
    app = App()..user = {'weight_kg': 80.0};
    units = UnitsController.seed(UnitSystem.metric);
    today = todayLabel();
    final d = DateTime.parse(today);
    earlier = dayLabelOf(DateTime(d.year, d.month, d.day - 7));
    await BodyLogDb.putWeight(earlier, 77, 'kg', historyOnly: false);
    // Distinct recorded instants: a same-second tie is intentionally resolved
    // by the stored id, and cannot establish chronological order.
    await BodyLogDb.putWeight(today, 80, 'kg', at: DateTime.parse(today));
    await BodyLogDb.putWeight(
      today,
      81,
      'kg',
      at: DateTime.parse(today).add(const Duration(minutes: 1)),
    );
    await BodyLogDb.putMeasure(
      BodyMeasure(
        id: 'synthetic-tape',
        date: today,
        recordedAt: DateTime.now(),
        inches: {'waistNavel': 34, 'neck': 15},
      ),
    );
    data = ProgressData(
      weights: await BodyLogDb.weights(),
      measures: await BodyLogDb.measures(),
      photos: [],
      lifts: [],
      food: [],
      steps: [],
      sleepMin: [],
      recovery: [],
      sessions: [],
      baseline: earlier,
      heightCm: 180,
    );
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS synthetic_body_refusal');
    app.dispose();
    units.dispose();
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider.value(value: units),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: w!,
          ),
          home: BodyHistoryScreen(data: data),
        ),
      ),
    );
    await flush(t);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await flush(t);
    });
  }

  for (final remove in [false, true]) {
    testWidgets(
      'measurement deletion ${remove ? 'commits' : 'cancels'} without touching weigh-ins',
      (t) async {
        await open(t);
        await tap(t, matchingAction('Delete measurements on').first);
        await tap(t, find.text(remove ? 'Delete' : 'Keep it').last);
        expect(
          (await t.runAsync(BodyLogDb.measures))!,
          remove ? isEmpty : hasLength(1),
        );
        expect(
          (await t.runAsync(() => BodyLogDb.readingsOn(today)))!,
          hasLength(2),
        );
        expect(app.profileWrites, isEmpty);
      },
    );
  }
  testWidgets('measurement write refusal preserves the row and permits retry', (
    t,
  ) async {
    await db.execute(
      "CREATE TRIGGER synthetic_body_refusal BEFORE DELETE ON body_measure BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
    );
    await open(t);
    await tap(t, matchingAction('Delete measurements on').first);
    await tap(t, find.text('Delete').last);
    expect(find.text('Could not delete it. Try again.'), findsOneWidget);
    expect((await t.runAsync(BodyLogDb.measures))!, hasLength(1));
    await t.runAsync(() => db.execute('DROP TRIGGER synthetic_body_refusal'));
    await tap(t, matchingAction('Delete measurements on').first);
    await tap(t, find.text('Delete').last);
    expect((await t.runAsync(BodyLogDb.measures))!, isEmpty);
  });
  for (final remove in [false, true]) {
    testWidgets(
      'weight-day deletion ${remove ? 'removes every reading and follows remaining weight' : 'cancels'}',
      (t) async {
        await open(t);
        await tap(t, matchingAction('Delete weight on').first);
        await tap(t, find.text(remove ? 'Delete' : 'Keep it').last);
        expect(
          (await t.runAsync(() => BodyLogDb.readingsOn(today)))!,
          remove ? isEmpty : hasLength(2),
        );
        expect((await t.runAsync(BodyLogDb.measures))!, hasLength(1));
        expect(app.user!['weight_kg'], remove ? 77 : 80);
        expect(app.profileWrites, remove ? hasLength(1) : isEmpty);
      },
    );
  }
  testWidgets(
    'a refused weight-day delete rolls back readings and the daily projection',
    (t) async {
      await db.execute(
        "CREATE TRIGGER synthetic_body_refusal BEFORE DELETE ON body_weight BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
      );
      await open(t);
      await tap(t, matchingAction('Delete weight on').first);
      await tap(t, find.text('Delete').last);
      expect(find.text('Could not delete it. Try again.'), findsOneWidget);
      expect(
        (await t.runAsync(() => BodyLogDb.readingsOn(today)))!,
        hasLength(2),
      );
      expect((await t.runAsync(BodyLogDb.weights))!.last.kg, 80);
      expect(app.profileWrites, isEmpty);
    },
  );
  testWidgets(
    'history Edit opens the same day with its recorded first weight and tape',
    (t) async {
      await open(t);
      await tap(t, matchingAction('Edit ').first);
      expect(find.byType(BodyEntryScreen), findsOneWidget);
      final page = t.widget<BodyEntryScreen>(find.byType(BodyEntryScreen));
      expect(page.date, today);
      expect(page.measure!.id, 'synthetic-tape');
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller!.text,
        '80',
      );
      Navigator.of(t.element(find.byType(BodyEntryScreen))).pop();
      await flush(t);
      expect(find.byType(BodyHistoryScreen), findsOneWidget);
      expect(
        (await t.runAsync(() => BodyLogDb.readingsOn(today)))!,
        hasLength(2),
      );
    },
  );
  testWidgets(
    'changing display weight units does not change history or stored amounts',
    (t) async {
      await open(t);
      expect(find.text('80 kg'), findsOneWidget);
      await t.runAsync(() => units.setWeightUnit('lb'));
      await flush(t);
      expect(find.text('176.4 lb'), findsOneWidget);
      expect(find.text('80 kg'), findsNothing);
      expect((await t.runAsync(BodyLogDb.weights))!.last.kg, 80);
      await t.runAsync(() => units.setWeightUnit('kg'));
      await flush(t);
      expect(find.text('80 kg'), findsOneWidget);
      expect(app.profileWrites, isEmpty);
    },
  );
}
