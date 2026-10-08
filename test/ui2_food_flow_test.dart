// Regression coverage for the personal food/UI cleanup. Uses synthetic food
// and the real SQLite store; no barcode network requests or personal records.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/data/off_lookup.dart';
import 'package:openstrap_edge/ui2/screens/log_food.dart';
import 'package:openstrap_edge/gps/run_history.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/locale_controller.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/ui2/screens/food_diary.dart';
import 'package:openstrap_edge/ui2/screens/food_picker.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart';
import 'package:openstrap_edge/ui2/screens/nutrition_screen.dart';
import 'package:openstrap_edge/ui2/screens/sleep_detail.dart';
import 'package:openstrap_edge/ui2/screens/readiness_detail.dart';
import 'package:openstrap_edge/ui2/screens/day_steps.dart';
import 'package:openstrap_edge/notify/tap_router.dart';
import 'package:openstrap_edge/ui2/screens/week_card.dart';
import 'package:openstrap_edge/ui2/screens/workout_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

const _profile = <String, dynamic>{
  'age': 23,
  'sex': 'm',
  'weight_kg': 80.5,
  'height_cm': 186.69,
  'protein_target': 150,
  'kcal_target': 2200,
};

class _Repo extends LocalRepository {
  bool failWorkouts = false;
  bool failToday = false;
  int measuredSteps = 5000;
  final blockedSteps = <String, Completer<Map<String, dynamic>>>{};
  final stepReads = <String>[];
  @override
  Future<Map<String, dynamic>> getProfile() async => _profile;
  @override
  Future<Map<String, dynamic>> getToday() async {
    if (failToday) throw StateError('synthetic read failure');
    return {
      'daily': {
        'steps': {'value': 5000},
      },
    };
  }

  @override
  Future<List<String>> availableDays() async => [];
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async => {'points': []};
  @override
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'}) async {
    if (failWorkouts) throw StateError('synthetic read failure');
    return {'workouts': []};
  }

  @override
  Future<Map<String, dynamic>> getInsights() async => {};
  @override
  Future<Map<String, dynamic>> getDaySteps(String date) {
    stepReads.add(date);
    return blockedSteps[date]?.future ??
        Future.value({'day_total': measuredSteps});
  }
}

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: 'async UI did not reach the expected state');
}

Widget _app(AppState app, Widget child, {double scale = 1}) => MultiProvider(
  providers: [ChangeNotifierProvider<AppState>.value(value: app)],
  child: RepaintBoundary(
    key: const ValueKey('capture'),
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(
        body: ColoredBox(color: const P(true).bg, child: child),
      ),
    ),
  ),
);

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
  matching: find.byType(TextField),
);

Future<void> _capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('UI_CAPTURE')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    Directory('test/goldens').createSync(recursive: true);
    File('test/goldens/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 100; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
}

FoodEntry _entry(
  String id,
  String date, {
  double? kcal = 500,
  double? protein = 30,
  int hour = 19,
  int second = 0,
}) => FoodEntry(
  id: id,
  date: date,
  meal: 'dinner',
  label: id,
  kcal: kcal,
  proteinG: protein,
  atTs:
      DateTime.parse(
        date,
      ).add(Duration(hours: hour, seconds: second)).millisecondsSinceEpoch ~/
      1000,
  confirmed: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'personal_food_flow_test.db';
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
    for (final family in ['Manrope', '.SF Pro Text']) {
      final loader = FontLoader(family);
      for (final f in Directory(
        'assets/fonts/Manrope',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
        loader.addFont(
          f.readAsBytes().then(
            (b) => ByteData.sublistView(Uint8List.fromList(b)),
          ),
        );
      }
      await loader.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
    icons.addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
    await icons.load();
    final materialIcons = FontLoader('MaterialIcons');
    materialIcons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await materialIcons.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    runsChanged();
    for (final table in [
      'baselines',
      'live_coverage',
      'sessions',
      'food_entry',
      'food_def',
      'meal_template',
      'body_weight',
    ]) {
      await db.delete(table);
    }
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  test(
    'library lookup defers persistence and saved barcodes work offline',
    () async {
      await Prefs.setBoolAcked('nutrition.barcode_lookup', true);
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 1,
            'product': {
              'product_name': 'Synthetic oats',
              'brands': 'Test brand',
              'serving_quantity': 50,
              'nutriments': {'energy-kcal_100g': 200, 'proteins_100g': 10},
            },
          }),
          200,
        ),
      );
      final result = await lookupBarcodeFood(
        '1234567890123',
        cacheProduct: false,
        client: client,
      );
      expect(result.outcome, OffOutcome.ok);
      final db = await LocalDb.instance;
      expect(await NutritionDb.foodDef(db, '1234567890123'), isNull);
      expect(result.product!.carbsG, isNull);
      await NutritionDb.putFoodDef(db, result.product!.toDefRow());
      final offline = MockClient(
        (_) async => throw StateError('Must use saved food'),
      );
      expect(
        (await lookupBarcodeFood(
          '1234567890123',
          cacheProduct: false,
          client: offline,
        )).outcome,
        OffOutcome.ok,
      );
      expect(await db.query('food_def'), hasLength(1));
      expect(await db.query('food_entry'), isEmpty);
      final missing = MockClient((_) async => http.Response('', 404));
      expect(
        (await lookupBarcodeFood(
          '999',
          cacheProduct: false,
          client: missing,
        )).outcome,
        OffOutcome.notFound,
      );
      expect(await db.query('food_def'), hasLength(1));
      client.close();
      offline.close();
      missing.close();
    },
  );

  testWidgets(
    'library Scan reviews saved food, cancels cleanly and saves once without logging',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting()
        ..repo = _Repo()
        ..user = {..._profile};
      addTearDown(app.dispose);
      await Prefs.setBoolAcked('nutrition.barcode_lookup', true);
      final db = await LocalDb.instance;
      await t.runAsync(
        () => NutritionDb.putFoodDef(
          db,
          const OffProduct(
            barcode: '1234567890123',
            label: 'Synthetic oats',
            brand: 'Test brand',
            servingG: 50,
            kcal: 200,
            proteinG: 10,
            sodiumMg: 10,
          ).toDefRow(),
        ),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final suffix in ['method', 'event', 'deviceOrientation']) {
        final channel = MethodChannel(
          'dev.steenbakker.mobile_scanner/scanner/$suffix',
        );
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'start') {
            throw PlatformException(code: 'PERMISSION_ERROR');
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      await t.pumpWidget(_app(app, const NutritionScreen()));
      await _until(t, () => find.text('Foods').evaluate().isNotEmpty);
      await t.tap(find.text('Foods'));
      await _until(t, () => find.text('Scan').evaluate().isNotEmpty);
      await _capture(t, 'food-library-scan');
      Future<void> scan() async {
        await t.tap(find.text('Scan'));
        await _until(t, () => find.byType(MobileScanner).evaluate().isNotEmpty);
        t.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
          BarcodeCapture(barcodes: [Barcode(rawValue: '1234567890123')]),
        );
        await _until(
          t,
          () => find.text('Review scanned food').evaluate().isNotEmpty,
        );
      }

      await scan();
      await _capture(t, 'food-library-review');
      expect(find.byType(QuickAddSheet), findsNothing);
      expect(
        t.widget<TextField>(_field('Calories (kcal)')).controller!.text,
        '100',
      );
      expect(
        t.widget<TextField>(_field('Carbs (g)')).controller!.text,
        isEmpty,
      );
      Navigator.of(t.element(find.byType(FoodEditor))).pop();
      await _until(t, () => find.byType(FoodEditor).evaluate().isEmpty);
      await t.pumpAndSettle();
      expect(
        (await t.runAsync(
          () => NutritionDb.foodDef(db, '1234567890123'),
        ))!['kcal_100'],
        200,
      );
      await scan();
      await t.enterText(_field('Calories (kcal)'), '120');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save to My foods'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save to My foods'));
      await _until(t, () => find.byType(FoodEditor).evaluate().isEmpty);
      final saved = (await t.runAsync(
        () => NutritionDb.foodDef(db, '1234567890123'),
      ))!;
      expect(saved['kcal_100'], 240);
      expect(saved['carbs_g_100'], isNull);
      expect(saved['brand'], 'Test brand');
      expect(saved['sodium_mg_100'], 10);
      expect(await t.runAsync(() => db.query('food_def')), hasLength(1));
      expect(await t.runAsync(() => db.query('food_entry')), isEmpty);
      await t.pumpAndSettle();
      await t.tap(find.text('Scan'));
      await _until(
        t,
        () => find.text('Type the numbers instead').evaluate().isNotEmpty,
      );
      await t.tap(find.text('Type the numbers instead'));
      await _until(t, () => find.text('New food').evaluate().isNotEmpty);
      expect(find.byType(QuickAddSheet), findsNothing);
      Navigator.of(t.element(find.byType(FoodEditor))).pop();
      await t.pumpAndSettle();
      expect(await t.runAsync(() => db.query('food_def')), hasLength(1));
      await _unmount(t);
      final mealDay = dayLabelOf(
        DateTime.now().subtract(const Duration(days: 2)),
      );
      await t.pumpWidget(
        _app(app, LogFoodScreen(date: mealDay, meal: 'breakfast')),
      );
      await _until(t, () => find.text('Scan').evaluate().isNotEmpty);
      await scan();
      expect(await t.runAsync(() => db.query('food_entry')), isEmpty);
      await t.enterText(_field('Protein (g)'), '8');
      await t.enterText(_field('Unit'), 'link');
      await t.enterText(_field('Amount'), '1');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save to My foods'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save to My foods'));
      await _until(t, () => find.byType(FoodDetailSheet).evaluate().isNotEmpty);
      expect(await t.runAsync(() => db.query('food_entry')), isEmpty);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Log'));
      await t.pumpAndSettle();
      await t.tap(find.text('Log'));
      await _until(t, () => find.byType(FoodDetailSheet).evaluate().isEmpty);
      final entries = await t.runAsync(() => db.query('food_entry'));
      expect(entries, hasLength(1));
      expect(entries!.single['date'], mealDay);
      expect(entries.single['meal'], 'breakfast');
      expect(entries.single['protein_g'], 8);
      expect(entries.single['unit'], 'link');
      expect(
        (await t.runAsync(
          () => NutritionDb.foodDef(db, '1234567890123'),
        ))!['sodium_mg_100'],
        500,
      );
      await _unmount(t);
    },
  );

  testWidgets(
    'long selected chart values stay fully visible at phone widths and enlarged text',
    (t) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      addTearDown(t.view.reset);
      for (final width in [320.0, 375.0, 390.0, 430.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          t.view.physicalSize = Size(width, 900);
          t.view.devicePixelRatio = 1;
          for (final sample in [
            (
              'Through the night',
              '2:19 AM · Light sleep\n49 bpm · HRV 67 ms · Temp Δ +0.2 °C',
              '',
            ),
            (
              'Maintenance and eaten',
              'Yesterday\nMaintenance 2,465 · Eaten 2,100 · −365',
              'kcal',
            ),
          ]) {
            await t.pumpWidget(
              _app(
                app,
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ChartFrame(
                      title: sample.$1,
                      unit: sample.$3,
                      readout: sample.$2,
                      child: const SizedBox(height: 130),
                    ),
                  ),
                ),
                scale: scale,
              ),
            );
            await t.pump();
            final readout = find.byWidgetPredicate(
              (w) => w is RichText && w.text.toPlainText().contains(sample.$2),
            );
            expect(readout, findsOneWidget);
            expect(
              t.renderObject<RenderParagraph>(readout).didExceedMaxLines,
              isFalse,
            );
            expect(t.getRect(readout).left, greaterThanOrEqualTo(16));
            expect(t.getRect(readout).right, lessThanOrEqualTo(width - 16));
            expect(t.takeException(), isNull);
            if (width == 375 && scale == 1)
              await _capture(
                t,
                'chart-${sample.$3.isEmpty ? 'sleep' : 'food'}',
              );
          }
        }
      }
      await _unmount(t);
    },
  );

  test(
    'numeric inputs reject non-finite values and preserve explicit zero or blank',
    () {
      for (final value in ['NaN', 'Infinity', '-Infinity', '1e999']) {
        expect(Typed.of(value).bad, isTrue);
      }
      expect(Typed.of('-1', nonNegative: true).bad, isTrue);
      expect(Typed.of('-1').value, -1);
      expect(Typed.of('0', nonNegative: true).value, 0);
      expect(Typed.of(' ', nonNegative: true).blank, isTrue);
    },
  );

  testWidgets(
    'invalid daily targets stay editable and optional targets can remain blank',
    (t) async {
      final app = AppState.forTesting()..user = {..._profile};
      addTearDown(app.dispose);
      await t.pumpWidget(
        _app(
          app,
          Builder(
            builder: (c) => TextButton(
              onPressed: () => editNutritionGoals(c),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.enterText(_field('Calories (kcal)'), '-100');
      await t.ensureVisible(find.text('Save'));
      await t.tap(find.text('Save'));
      await t.pump();
      expect(
        find.textContaining('enter a non-negative number'),
        findsOneWidget,
      );
      expect(find.text('Daily targets'), findsOneWidget);
      expect(app.user!['kcal_target'], 2200);
      await t.enterText(_field('Calories (kcal)'), '2100');
      await t.ensureVisible(find.text('Save'));
      await t.tap(find.text('Save'));
      await _until(t, () => find.text('Daily targets').evaluate().isEmpty);
      expect(app.user!['kcal_target'], 2100);
      expect(app.user!['protein_target'], 150);
      expect(app.user!['fat_target'], isNull);
      expect(app.user!['fibre_target'], isNull);
      await _unmount(t);
    },
  );

  testWidgets(
    'quick add explains missing calories, saves once, and leaves optional macros blank',
    (t) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final day = todayLabel();
      await t.pumpWidget(
        _app(
          app,
          Builder(
            builder: (c) => TextButton(
              onPressed: () =>
                  QuickAddSheet.show(c, date: day, meal: 'breakfast'),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Add'));
      await t.tap(find.text('Add'));
      await t.pump();
      expect(
        find.text('Enter calories. Other macros can stay blank.'),
        findsOneWidget,
      );
      await t.enterText(_field('Calories (kcal)'), '-1');
      await t.ensureVisible(find.text('Add'));
      await t.tap(find.text('Add'));
      await t.pump();
      expect(find.textContaining('non-negative number'), findsOneWidget);
      await t.enterText(_field('Name'), 'Shake');
      await t.enterText(_field('Calories (kcal)'), '210');
      await t.enterText(_field('Protein (g)'), '35');
      final save = t
          .widget<BigButton>(find.widgetWithText(BigButton, 'Add'))
          .onTap!;
      save();
      save(); // The same old callback invoked twice before the DB returns.
      await _until(t, () => find.byType(QuickAddSheet).evaluate().isEmpty);
      final entries = await t.runAsync(
        () => NutritionDb.entriesForDay(db, day),
      );
      expect(entries, hasLength(1));
      expect(entries!.single.kcal, 210);
      expect(entries.single.proteinG, 35);
      expect(entries.single.carbsG, isNull);
      expect(entries.single.fatG, isNull);
      expect(entries.single.fibreG, isNull);
      await _unmount(t);
    },
  );

  testWidgets(
    'quick-add editing preserves identity, time, group and omitted fields; fibre can be set',
    (t) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final day = shiftDay(todayLabel(), -2);
      final original = _entry(
        'editable shake',
        day,
        second: 17,
        protein: 30.25,
      ).inGroup('After training');
      await t.runAsync(() => NutritionDb.put(db, original));
      await t.pumpWidget(
        _app(
          app,
          Builder(
            builder: (c) => TextButton(
              onPressed: () => QuickAddSheet.show(
                c,
                date: day,
                meal: original.meal,
                from: original,
                editing: true,
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      await t.enterText(_field('Calories (kcal)'), '600');
      // Every macro is on the sheet; no dropdown to open first.
      expect(find.text('Other macros (optional)'), findsNothing);
      await t.ensureVisible(_field('Fibre (g)'));
      await t.enterText(_field('Fibre (g)'), '4.5');
      await t.enterText(_field('Fat (g)'), '0');
      await t.ensureVisible(find.text('Save changes'));
      await t.tap(find.text('Save changes'));
      await _until(t, () => find.byType(QuickAddSheet).evaluate().isEmpty);
      final entries = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, day),
      ))!;
      expect(entries, hasLength(1));
      final edited = entries.single;
      expect(edited.id, original.id);
      expect(edited.atTs, original.atTs);
      expect(edited.group, original.group);
      expect(edited.kcal, 600);
      expect(edited.proteinG, 30.25);
      expect(edited.fibreG, 4.5);
      expect(edited.fatG, 0);
      expect(edited.carbsG, isNull);
      await _unmount(t);
    },
  );

  testWidgets(
    'meal entry offers edit, Undo works and deletion notice expires',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final day = todayLabel();
      await t.runAsync(() => NutritionDb.put(db, _entry('Dinner shake', day)));
      await t.pumpWidget(_app(app, MealPage(date: day, meal: 'dinner')));
      await _until(t, () => find.text('Dinner shake').evaluate().isNotEmpty);
      await t.tap(find.text('Dinner shake'));
      await t.pumpAndSettle();
      expect(find.text('Edit entry'), findsOneWidget);
      await t.tap(find.text('Edit entry'));
      await t.pumpAndSettle();
      expect(find.byType(QuickAddSheet), findsOneWidget);
      await t.tap(
        find
            .byWidgetPredicate(
              (w) => w is Pressable && w.semanticLabel == 'Close',
            )
            .last,
      );
      await _until(t, () => find.byType(Dismissible).evaluate().isNotEmpty);
      await t.pumpAndSettle();
      // Let the read started by closing the editor finish before interacting.
      await t.runAsync(() => NutritionDb.entriesForDay(db, day));
      await t.pumpAndSettle();
      await t.drag(find.byType(Dismissible), const Offset(-500, 0));
      await t.pumpAndSettle();
      await _until(t, () => find.text('Undo').evaluate().isNotEmpty);
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('Undo'));
      await _until(t, () => find.text('Dinner shake').evaluate().isNotEmpty);
      expect(
        (await t.runAsync(
          () => NutritionDb.entriesForDay(db, day),
        ))!.single.label,
        'Dinner shake',
      );
      await _until(t, () => find.byType(Dismissible).evaluate().isNotEmpty);
      await t.pumpAndSettle();
      await t.drag(find.byType(Dismissible), const Offset(-500, 0));
      await t.pumpAndSettle();
      await _until(t, () => find.text('Undo').evaluate().isNotEmpty);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Deleted Dinner shake'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Deleted Dinner shake'), findsNothing);
      expect(
        await t.runAsync(() => NutritionDb.entriesForDay(db, day)),
        isEmpty,
      );
      expect(t.takeException(), isNull);
      await _unmount(t);
    },
  );

  testWidgets(
    'food picker defaults to My foods and Scan reaches camera, not occasion entry',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await Prefs.ensureLoaded();
      await Prefs.setBoolAcked('nutrition.barcode_lookup', true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(
              'dev.steenbakker.mobile_scanner/scanner/method',
            ),
            (call) async {
              if (call.method == 'start')
                throw PlatformException(code: 'PERMISSION_ERROR');
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(
                'dev.steenbakker.mobile_scanner/scanner/method',
              ),
              null,
            ),
      );
      for (final suffix in ['event', 'deviceOrientation']) {
        final channel = MethodChannel(
          'dev.steenbakker.mobile_scanner/scanner/$suffix',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
      }
      await t.pumpWidget(
        _app(app, LogFoodScreen(date: todayLabel(), meal: 'breakfast')),
      );
      await _until(
        t,
        () => find
            .text('Create a food once from its label.')
            .evaluate()
            .isNotEmpty,
      );
      await _capture(t, 'food-picker');
      await t.tap(find.text('Scan'));
      await t.pump(const Duration(milliseconds: 500));
      await _until(t, () => find.byType(MobileScanner).evaluate().isNotEmpty);
      expect(find.text('Log an eating occasion'), findsNothing);
      expect(find.text('Add the numbers'), findsNothing);
      await _until(
        t,
        () => find.text('Type the numbers instead').evaluate().isNotEmpty,
      );
      await t.tap(find.text('Type the numbers instead'));
      await _until(t, () => find.byType(FoodEditor).evaluate().isNotEmpty);
      expect(find.text('Log an eating occasion'), findsNothing);
      await _unmount(t);
    },
  );

  testWidgets(
    'history groups retained months and opens older entries only on expansion',
    (t) async {
      final app = AppState.forTesting()
        ..user = {..._profile}
        ..repo = _Repo();
      addTearDown(app.dispose);
      final now = DateTime.now();
      final older = dayLabelOf(DateTime(now.year, now.month - 2, 10));
      await t.runAsync(() async {
        await NutritionDb.put(db, _entry('Old meal', older));
        await NutritionDb.put(db, _entry('Current meal', todayLabel()));
      });
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(app, const NutritionScreen()));
      await _until(t, () => find.byType(DayHeader).evaluate().isNotEmpty);
      await t.tap(find.text('History'));
      await t.pump();
      await _until(t, () => find.byType(ExpansionTile).evaluate().length >= 2);
      await _until(
        t,
        () => find.textContaining('1 day logged').evaluate().isNotEmpty,
      );
      await t.pumpAndSettle();
      final selected = t.widget<Text>(find.text('History'));
      final chip = t.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('History'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final wash = (chip.decoration! as BoxDecoration).color!;
      expect(wash.a, closeTo(.18, .001));
      expect(
        P.contrast(
          selected.style!.color!,
          Color.alphaBlend(wash, const P(true).bg),
        ),
        greaterThanOrEqualTo(4.5),
      );
      final oldMonth = MaterialLocalizations.of(
        t.element(find.byType(NutritionScreen)),
      ).formatMonthYear(DateTime(now.year, now.month - 2));
      expect(find.text(prettyDayForTest(older)), findsNothing);
      await _capture(t, 'food-history');
      await t.ensureVisible(find.text(oldMonth));
      await t.tap(find.text(oldMonth));
      await t.pump();
      await _until(
        t,
        () => find.text(prettyDayForTest(older)).evaluate().isNotEmpty,
      );
      expect(t.takeException(), isNull);
      await _unmount(t);
    },
  );

  testWidgets('weekly card reloads in place after food writes without a pull', (
    t,
  ) async {
    final app = AppState.forTesting()
      ..repo = _Repo()
      ..user = {..._profile};
    addTearDown(app.dispose);
    await t.pumpWidget(_app(app, const WeekCard()));
    await _until(t, () => find.text('This week').evaluate().isNotEmpty);
    final state = t.state(find.byType(WeekCard));
    final first = WeekCard.debugLoads;
    await t.runAsync(
      () => NutritionDb.put(db, _entry('Today food', todayLabel())),
    );
    await _until(t, () => WeekCard.debugLoads > first);
    expect(identical(state, t.state(find.byType(WeekCard))), isTrue);
    expect(
      find.textContaining('Food summary awaits a completed day'),
      findsOneWidget,
    );
    final second = WeekCard.debugLoads;
    app.bumpInsights();
    await _until(t, () => WeekCard.debugLoads > second);
    await _unmount(t);
  });

  testWidgets('a slower old day cannot replace a newly selected food day', (
    t,
  ) async {
    final repo = _Repo();
    final app = AppState.forTesting()
      ..repo = repo
      ..user = {..._profile};
    addTearDown(app.dispose);
    final a = shiftDay(todayLabel(), -2), b = shiftDay(todayLabel(), -1);
    await t.runAsync(() async {
      await NutritionDb.put(db, _entry('Day A food', a));
      await NutritionDb.put(db, _entry('Day B food', b));
    });
    final blocked = Completer<Map<String, dynamic>>();
    repo.blockedSteps[a] = blocked;
    await t.pumpWidget(
      _app(
        app,
        SingleChildScrollView(
          child: NutritionDayView(
            key: const ValueKey('same day view'),
            date: a,
          ),
        ),
      ),
    );
    await _until(t, () => repo.stepReads.contains(a));
    await t.pumpWidget(
      _app(
        app,
        SingleChildScrollView(
          child: NutritionDayView(
            key: const ValueKey('same day view'),
            date: b,
          ),
        ),
      ),
    );
    await _until(t, () => find.text('Day B food').evaluate().isNotEmpty);
    blocked.complete({'day_total': 90000});
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump();
    expect(find.text('Day B food'), findsOneWidget);
    expect(find.text('Day A food'), findsNothing);
    await _unmount(t);
  });

  testWidgets('failed food read is retryable rather than an endless spinner', (
    t,
  ) async {
    final app = AppState.forTesting()
      ..repo = _Repo()
      ..user = {..._profile};
    addTearDown(app.dispose);
    await t.runAsync(
      () => db.execute('ALTER TABLE food_entry RENAME TO food_entry_held'),
    );
    try {
      await t.pumpWidget(_app(app, const NutritionScreen()));
      await _until(
        t,
        () => find.text('Food could not load').evaluate().isNotEmpty,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    } finally {
      await t.runAsync(
        () => db.execute('ALTER TABLE food_entry_held RENAME TO food_entry'),
      );
    }
    await t.tap(find.text('Retry'));
    await _until(t, () => find.byType(DayHeader).evaluate().isNotEmpty);
    await _unmount(t);
  });

  testWidgets('failed Train session read is not presented as empty history', (
    t,
  ) async {
    final repo = _Repo()..failWorkouts = true;
    final app = AppState.forTesting()
      ..repo = repo
      ..user = {..._profile};
    addTearDown(app.dispose);
    await t.pumpWidget(_app(app, const WorkoutScreen()));
    await _until(
      t,
      () => find.text('Training history could not load').evaluate().isNotEmpty,
    );
    repo.failWorkouts = false;
    await t.tap(find.text('Retry'));
    await _until(
      t,
      () =>
          find.text('Training history could not load').evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await _unmount(t);
  });

  testWidgets(
    'a failed quick-add save retains values and allows a successful retry',
    (t) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await t.runAsync(
        () => db.execute(
          "CREATE TEMP TRIGGER reject_save BEFORE INSERT ON food_entry "
          "BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END",
        ),
      );
      try {
        await t.pumpWidget(
          _app(
            app,
            Builder(
              builder: (c) => TextButton(
                onPressed: () =>
                    QuickAddSheet.show(c, date: todayLabel(), meal: 'lunch'),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open'));
        await t.pumpAndSettle();
        await t.enterText(_field('Name'), 'Retained shake');
        await t.enterText(_field('Calories (kcal)'), '250');
        await t.enterText(_field('Protein (g)'), '40');
        await t.ensureVisible(find.text('Add'));
        await t.tap(find.text('Add'));
        await _until(
          t,
          () => find.textContaining('Could not save').evaluate().isNotEmpty,
        );
        expect(
          t.widget<TextField>(_field('Calories (kcal)')).controller!.text,
          '250',
        );
      } finally {
        await t.runAsync(() => db.execute('DROP TRIGGER reject_save'));
      }
      await t.ensureVisible(find.text('Add'));
      await t.tap(find.text('Add'));
      await _until(t, () => find.byType(QuickAddSheet).evaluate().isEmpty);
      expect(
        (await t.runAsync(() => NutritionDb.entriesForDay(db, todayLabel())))!,
        hasLength(1),
      );
      await _unmount(t);
    },
  );

  testWidgets(
    'Sleep read failures offer Retry rather than claiming no night exists',
    (t) async {
      final repo = _Repo()..failToday = true;
      final app = AppState.forTesting()..repo = repo;
      addTearDown(app.dispose);
      await t.pumpWidget(_app(app, const SleepDetail()));
      await _until(
        t,
        () => find.text('Sleep could not load').evaluate().isNotEmpty,
      );
      expect(find.text('No night to show'), findsNothing);
      repo.failToday = false;
      await t.tap(find.text('Retry'));
      await _until(
        t,
        () => find.text('No night to show').evaluate().isNotEmpty,
      );
      await _unmount(t);
    },
  );

  testWidgets(
    'fresh launch ignores a saved Food tab while warm navigation is retained',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await Prefs.ensureLoaded();
      await Prefs.setBoolAcked('onboard.completed', true);
      Prefs.setInt(Prefs.shellTab, ShellDomain.nutrition.index);
      final app = AppState.forTesting()
        ..initialized = true
        ..repo = _Repo()
        ..user = {..._profile};
      await t.runAsync(app.chooseNewUser);
      final locale = LocaleController.seed('en');
      final theme = ThemeController.seed(AppThemeChoice.dark, Brightness.dark);
      final coach = CoachConfig();
      addTearDown(app.dispose);
      addTearDown(locale.dispose);
      addTearDown(theme.dispose);
      addTearDown(coach.dispose);
      Widget root() => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<LocaleController>.value(value: locale),
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<CoachConfig>.value(value: coach),
        ],
        child: const OpenStrapApp(),
      );
      await t.pumpWidget(root());
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await t.pump();
      expect(
        t.widget<AppShell>(find.byType(AppShell)).initial,
        ShellDomain.home,
      );
      await t.tap(find.text('Food').last);
      await t.pump();
      expect(
        t.widget<IndexedStack>(find.byType(IndexedStack).first).index,
        ShellDomain.nutrition.index,
      );
      await t.pumpWidget(root());
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await t.pump();
      expect(
        t.widget<IndexedStack>(find.byType(IndexedStack).first).index,
        ShellDomain.nutrition.index,
      );
      await _unmount(t);
      await t.pumpWidget(root());
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await t.pump();
      expect(
        t.widget<AppShell>(find.byType(AppShell)).initial,
        ShellDomain.home,
      );
      final nav = Navigator.of(t.element(find.byType(AppShell)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Old detail')),
          ),
        ),
      );
      await t.pumpAndSettle();
      unawaited(
        showModalBottomSheet<void>(
          context: t.element(find.text('Old detail')),
          isScrollControlled: true,
          builder: (_) => const InputSheet(
            children: [
              Text('Draft'),
              TextField(
                decoration: InputDecoration(labelText: 'Unsaved entry'),
              ),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      app.screenRequest.value = datedRoute(kRouteRecovery, '2026-10-03');
      app.navRequest.value = 0;
      await t.pump();
      expect(find.text('Unsaved entry'), findsOneWidget);
      expect(find.byType(ReadinessDetail), findsNothing);
      Navigator.of(t.element(find.byType(InputSheet))).pop();
      await _until(t, () => find.byType(ReadinessDetail).evaluate().isNotEmpty);
      await _until(t, () => find.text('Old detail').evaluate().isEmpty);
      expect(
        t.widget<ReadinessDetail>(find.byType(ReadinessDetail)).day,
        '2026-10-03',
      );
      await _unmount(t);
      app.screenRequest.value = datedRoute(kRouteSteps, '2026-10-02');
      app.navRequest.value = 0;
      await t.pumpWidget(root());
      await _until(t, () => find.byType(DayStepsDetail).evaluate().isNotEmpty);
      expect(
        t.widget<DayStepsDetail>(find.byType(DayStepsDetail)).day,
        '2026-10-02',
      );
      await _unmount(t);
      app.stopForegroundRefresh();
      await t.pump(const Duration(seconds: 1));
    },
  );

  test(
    'calendar month query reaches old history and respects a leap February',
    () async {
      await NutritionDb.put(db, _entry('Leap day food', '2024-02-29'));
      final months = await NutritionDb.historyMonths(
        db,
        now: DateTime(2026, 10, 3),
      );
      expect(months, ['2026-10', '2024-02']);
      final month = await NutritionDb.month(
        db,
        '2024-02',
        now: DateTime(2026, 10, 3),
      );
      expect(month.days, hasLength(29));
      expect(month.days.last.entries.single.label, 'Leap day food');
    },
  );

  test(
    'saved meal uses its historical date and meal time, then emits one committed change',
    () async {
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(
          key: 'my:oats',
          label: 'Oats',
          refGrams: 100,
          kcal: 400,
          protein: 12,
        ),
      );
      const meal = MealTemplate(
        key: 'm',
        label: 'My dinner',
        meal: 'dinner',
        items: [('my:oats', 50), ('my:oats', 25)],
      );
      final before = NutritionDb.revision.value;
      await MyFoods.logMeal(
        db,
        meal,
        '2026-09-30',
        'dinner',
        now: DateTime(2026, 10, 3, 8),
      );
      expect(NutritionDb.revision.value, before + 1);
      final entries = await NutritionDb.entriesForDay(db, '2026-09-30');
      expect(entries, hasLength(2));
      for (final e in entries) {
        expect(
          DateTime.fromMillisecondsSinceEpoch(e.atTs! * 1000),
          DateTime(2026, 9, 30, 19),
        );
      }
      expect(
        rollupDay(
          '2026-09-30',
          entries,
          today: '2026-10-03',
        ).countsTowardAverages,
        isTrue,
      );
    },
  );

  testWidgets(
    'weekly energy excludes today, unknown calories and breakfast-only days; blank fat is fine',
    (t) async {
      const atDay = '2026-09-30';
      await t.runAsync(
        () => NutritionDb.put(
          db,
          _entry('Complete', '2026-09-28', kcal: 1800, protein: 120),
        ),
      );
      await t.runAsync(
        () => NutritionDb.put(
          db,
          _entry('Forgot evening', '2026-09-29', hour: 8, kcal: 300),
        ),
      );
      await t.runAsync(
        () => NutritionDb.put(
          db,
          _entry('Unknown dinner', '2026-09-29', kcal: null),
        ),
      );
      await t.runAsync(
        () => NutritionDb.put(db, _entry('Today so far', atDay, kcal: 100)),
      );
      final summary = (await t.runAsync(
        () => WeekNumbers.load(
          _Repo(),
          const Profile(
            ageYears: 23,
            weightKg: 80.5,
            heightCm: 186.69,
            sex: 'm',
          ),
          {},
          at: DateTime(2026, 9, 30),
        ),
      ))!;
      expect(summary.daysLogged, 1);
      expect(summary.daysExcluded, 2);
      expect(summary.avgProtein, 120);
      expect(
        summary.deficit,
        closeTo(
          maintenance(
                const Profile(
                  ageYears: 23,
                  weightKg: 80.5,
                  heightCm: 186.69,
                  sex: 'm',
                ),
                eatenKcal: 1800,
                // 120 g protein at 20% + the other 1,320 kcal at 5% = 162.
                digestionKcal: digestionKcal(kcal: 1800, proteinG: 120),
                steps: 5000,
              )!.total -
              1800,
          .01,
        ),
      );
    },
  );

  testWidgets(
    'an already-open maintenance breakdown reacts to measured steps and food writes',
    (t) async {
      t.view.physicalSize = const Size(390, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repo = _Repo()..measuredSteps = 0;
      final app = AppState.forTesting()
        ..repo = repo
        ..user = {..._profile};
      addTearDown(app.dispose);
      await t.pumpWidget(
        _app(
          app,
          Builder(
            builder: (c) => TextButton(
              onPressed: () => showMaintenance(
                c,
                DayUpkeep(
                  Profile.fromMap(_profile),
                  steps: 0,
                  date: todayLabel(),
                ),
                today: true,
              ),
              child: const Text('Open breakdown'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open breakdown'));
      await t.pumpAndSettle();
      await _until(
        t,
        () => find.textContaining('0 steps at').evaluate().isNotEmpty,
      );
      repo.measuredSteps = 10000;
      app.bumpInsights();
      await _until(
        t,
        () => find.textContaining('10,000 steps at').evaluate().isNotEmpty,
      );
      expect(find.text('264 kcal'), findsOneWidget);
      await t.runAsync(
        () =>
            NutritionDb.put(db, _entry('fresh-food', todayLabel(), kcal: 2000)),
      );
      await _until(
        t,
        () =>
            find.textContaining('2,000 kcal you logged').evaluate().isNotEmpty,
      );
      // 30 g protein at 20% (24) + the other 1,880 kcal at 5% (94).
      expect(find.text('118 kcal'), findsOneWidget);
      await _capture(t, 'build73-maintenance');
      expect(t.takeException(), isNull);
      await _unmount(t);
    },
  );

  testWidgets(
    'picker logs into a new heading with haptics and removes saved items in place',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final taps = <MethodCall>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          taps.add(call);
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final def = myFoodDef(
        key: 'sausage',
        label: 'Chicken sausage',
        refGrams: 1,
        unit: 'link',
        kcal: 110,
        protein: 13,
      );
      await t.runAsync(() async {
        await NutritionDb.putFoodDef(db, def);
        await MyFoods.putMeal(
          db,
          const MealTemplate(
            key: 'saved',
            label: 'Breakfast favourite',
            meal: 'breakfast',
            items: [('sausage', 2)],
            units: {'sausage': 'link'},
          ),
        );
      });
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await t.pumpWidget(
        _app(app, LogFoodScreen(date: todayLabel(), meal: 'breakfast')),
      );
      await _until(t, () => find.text('Chicken sausage').evaluate().isNotEmpty);
      expect(find.text('Recent'), findsNothing);
      await _capture(t, 'build73-picker');
      await t.tap(find.text('Meal heading'));
      await _until(
        t,
        () => find.text('Create a heading').evaluate().isNotEmpty,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Create a heading'));
      await t.tap(find.text('Create a heading'));
      await t.pumpAndSettle();
      await t.enterText(_field('Name'), 'Power breakfast');
      await t.ensureVisible(find.text('Save').last);
      await t.tap(find.text('Save').last);
      await _until(
        t,
        () =>
            find.text('Power breakfast').evaluate().isNotEmpty &&
            find.text('Create a heading').evaluate().isEmpty,
      );
      final log = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Log Chicken sausage',
      );
      await t.ensureVisible(log);
      await t.tap(log);
      // Build 75: + opens the portion screen first; nothing is written
      // until Log.
      await _until(t, () => find.text('Log').evaluate().isNotEmpty);
      await t.pumpAndSettle();
      expect(
        (await t.runAsync(() => NutritionDb.entriesForDay(db, todayLabel())))!,
        isEmpty,
      );
      await t.ensureVisible(find.text('Log').last);
      await t.tap(find.text('Log').last);
      await _until(
        t,
        () =>
            find.textContaining('Added Chicken sausage').evaluate().isNotEmpty,
      );
      expect(
        taps.where((c) => c.method == 'HapticFeedback.vibrate'),
        isNotEmpty,
      );
      final es = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, todayLabel()),
      ))!;
      expect(es.single.group, 'Power breakfast');
      expect(es.single.unit, 'link');
      expect(es.single.kcal, 110);
      await t.drag(
        find.byKey(const ValueKey('saved-sausage')),
        const Offset(450, 0),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Remove').last);
      await _until(t, () => find.text('Chicken sausage').evaluate().isEmpty);
      expect(
        (await t.runAsync(() => NutritionDb.entriesForDay(db, todayLabel())))!,
        hasLength(1),
      );
      await t.tap(find.text('My meals'));
      await t.pump();
      await _until(
        t,
        () => find.text('Breakfast favourite').evaluate().isNotEmpty,
      );
      // Build 75: a swipe either way removes, as on every food list.
      await t.drag(
        find.byKey(const ValueKey('saved-saved')),
        const Offset(-450, 0),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Remove').last);
      await _until(
        t,
        () => find.text('Breakfast favourite').evaluate().isEmpty,
      );
      expect(t.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      await _unmount(t);
    },
  );

  testWidgets(
    'decimal serving sheet can close or drag away above the keyboard without saving',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      t.view.padding = FakeViewPadding(top: 59);
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final def = myFoodDef(
        key: 'portion',
        label: 'Decimal sausage',
        refGrams: 1,
        unit: 'link',
        kcal: 110,
        protein: 13,
      );
      await t.pumpWidget(
        _app(
          app,
          Builder(
            builder: (c) => TextButton(
              onPressed: () => GramsSheet.show(c, def, initial: 2.5),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(_field('Amount (link)')).controller!.text,
        '2.5',
      );
      await t.tap(_field('Amount (link)'));
      t.view.viewInsets = FakeViewPadding(bottom: 330);
      await t.pumpAndSettle();
      final close = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Close',
      );
      expect(t.getTopLeft(close).dy, greaterThanOrEqualTo(59));
      expect(t.getBottomLeft(close).dy, lessThan(514));
      await _capture(t, 'build73-decimal-keyboard');
      await t.tap(close);
      await t.pumpAndSettle();
      expect(find.byType(GramsSheet), findsNothing);
      t.view.viewInsets = FakeViewPadding();
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.tap(_field('Amount (link)'));
      t.view.viewInsets = FakeViewPadding(bottom: 330);
      await t.pumpAndSettle();
      await t.fling(find.text('Decimal sausage'), const Offset(0, 200), 1000);
      await t.pumpAndSettle();
      expect(find.byType(GramsSheet), findsNothing);
      expect(
        (await t.runAsync(() => NutritionDb.entriesForDay(db, todayLabel())))!,
        isEmpty,
      );
      expect(t.takeException(), isNull);
      await _unmount(t);
    },
  );

  test(
    'a failed multi-food meal rolls back entirely and emits no committed change',
    () async {
      for (final label in ['Good', 'Broken']) {
        await NutritionDb.putFoodDef(
          db,
          myFoodDef(key: label, label: label, refGrams: 100, kcal: 200),
        );
      }
      await db.execute(
        "CREATE TEMP TRIGGER fail_food BEFORE INSERT ON food_entry WHEN NEW.label = 'Broken' "
        "BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END",
      );
      final before = NutritionDb.revision.value;
      try {
        await expectLater(
          MyFoods.logMeal(
            db,
            const MealTemplate(
              key: 'm',
              label: 'Two foods',
              meal: 'dinner',
              items: [('Good', 100), ('Broken', 100)],
            ),
            '2026-09-30',
            'dinner',
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect(await NutritionDb.entriesForDay(db, '2026-09-30'), isEmpty);
        expect(NutritionDb.revision.value, before);
      } finally {
        await db.execute('DROP TRIGGER fail_food');
      }
    },
  );

  testWidgets('Food → Foods searches saved meals and foods by name', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = AppState.forTesting()
      ..repo = _Repo()
      ..user = {..._profile};
    addTearDown(app.dispose);
    final db = await LocalDb.instance;
    await t.runAsync(() async {
      await db.delete('food_def');
      await db.delete('meal_template');
      for (final n in ['Banana', 'Kerrygold butter']) {
        await NutritionDb.putFoodDef(
          db,
          myFoodDef(key: 'my:$n', label: n, refGrams: 100, kcal: 90),
        );
      }
    });
    await t.pumpWidget(_app(app, const NutritionScreen()));
    await _until(t, () => find.text('Foods').evaluate().isNotEmpty);
    await t.tap(find.text('Foods'));
    await _until(t, () => find.text('Banana').evaluate().isNotEmpty);
    await t.enterText(_field('Search'), 'ban');
    await t.pump();
    expect(find.text('Banana'), findsOneWidget);
    expect(find.text('Kerrygold butter'), findsNothing);
    expect(find.text('No matches'), findsOneWidget, reason: 'no saved meal');
    await t.enterText(_field('Search'), '');
    await t.pump();
    expect(find.text('Kerrygold butter'), findsOneWidget);
    await _unmount(t);
  });
}

// Mirrors the visible date label through the production formatter.
String prettyDayForTest(String date) => dayTitle(date);
